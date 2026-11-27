#Develop a script that connects to multiple Linux servers over SSH, 
#collects CPU, memory, disk, and uptime information, and generates a
# consolidated health report. Handle connection failures 
# and command timeouts without stopping checks on other servers. 
#ans) To collect CPU, memory, disk, and uptime across many Linux hosts without one dead or hung server blocking the fleet, run a single self-contained remote probe over SSH with ConnectTimeout, BatchMode=yes, and a remote command timeout (timeout inside the remote shell), capture structured output per host into a temp directory (mktemp -d), and assemble a consolidated health report across all hosts—including unreachable or timed-out targets.
#!/bin/bash

SERVER_FILE="${1:-${SERVER_FILE:-./servers.txt}}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PORT="${SSH_PORT:-22}"
SSH_KEY="${SSH_KEY:-}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
CMD_TIMEOUT="${CMD_TIMEOUT:-10}"
MOUNT_POINT="${MOUNT_POINT:-/}"
REPORT_FILE="${REPORT_FILE:-./fleet_health_report_$(date "+%Y%m%d_%H%M%S").txt}"

if [ -z "$SERVER_FILE" ] || [ ! -f "$SERVER_FILE" ] || [ ! -r "$SERVER_FILE" ]; then
  echo "Error: Server list file '$SERVER_FILE' is missing or not readable." >&2
  echo "Usage: $0 [servers_file]" >&2
  echo "Optional env vars: SSH_USER, SSH_PORT, SSH_KEY, CONNECT_TIMEOUT, CMD_TIMEOUT, MOUNT_POINT, REPORT_FILE" >&2
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  echo "Error: 'ssh' client is not installed." >&2
  exit 1
fi

report_dir=$(dirname "$REPORT_FILE")
mkdir -p "$report_dir"
if [ ! -d "$report_dir" ] || [ ! -w "$report_dir" ]; then
  echo "Error: Report directory '$report_dir' is not writable." >&2
  exit 1
fi

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

# Build SSH option array safely
ssh_opts=(
  -p "$SSH_PORT"
  -o "ConnectTimeout=$CONNECT_TIMEOUT"
  -o "BatchMode=yes"
  -o "StrictHostKeyChecking=accept-new"
)
if [ -n "$SSH_KEY" ]; then
  ssh_opts+=(-i "$SSH_KEY")
fi

# Remote payload runs under a remote timeout so hung commands cannot stall the session
build_remote_cmd() {
  local mnt="$1"
  local cmd_to="$2"

  cat <<EOF
timeout "${cmd_to}s" bash -s -- "$mnt" <<'REMOTE_EOF'
set -u
mnt="\$1"

# CPU delta over 0.5s from /proc/stat
if [ -r /proc/stat ]; then
  read -r _ u1 n1 s1 i1 w1 irq1 sirq1 _ < /proc/stat
  sleep 0.5
  read -r _ u2 n2 s2 i2 w2 irq2 sirq2 _ < /proc/stat
  idle1=\$((i1 + w1))
  idle2=\$((i2 + w2))
  tot1=\$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1))
  tot2=\$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2))
  tdiff=\$((tot2 - tot1))
  idiff=\$((idle2 - idle1))
  if [ "\$tdiff" -gt 0 ]; then
    cpu=\$(( (100 * (tdiff - idiff) + tdiff / 2) / tdiff ))
  else
    cpu=0
  fi
else
  cpu="N/A"
fi

# Memory utilization from free (Mem: row)
if command -v free >/dev/null 2>&1; then
  mem=\$(free | awk '/^Mem:/ {
    if (\$2 > 0) printf "%d", ((\$3 / \$2) * 100) + 0.5
    else print 0
  }')
else
  mem="N/A"
fi

# Disk utilization for target mount point
if command -v df >/dev/null 2>&1; then
  disk=\$(df -P "\$mnt" 2>/dev/null | awk 'NR==2 {
    gsub("%", "", \$5)
    print \$5 + 0
  }')
  [ -z "\$disk" ] && disk="N/A"
else
  disk="N/A"
fi

# Uptime summary
if command -v uptime >/dev/null 2>&1; then
  up=\$(uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/^[[:space:]]*//')
elif [ -r /proc/uptime ]; then
  up=\$(awk '{
    s = int(\$1)
    d = int(s / 86400)
    h = int((s % 86400) / 3600)
    m = int((s % 3600) / 60)
    printf "up %d days, %d hours, %d minutes\n", d, h, m
  }' /proc/uptime)
else
  up="N/A"
fi

# Sanitize pipes in uptime so single-line record parsing stays clean
up_clean=\$(printf "%s" "\$up" | tr '\n' ' ' | tr '|' '/')
printf "OK|%s|%s|%s|%s\n" "\$cpu" "\$mem" "\$disk" "\$up_clean"
REMOTE_EOF
EOF
}

remote_payload=$(build_remote_cmd "$MOUNT_POINT" "$CMD_TIMEOUT")

total_hosts=0
ok_hosts=0
failed_hosts=0
idx=0

while IFS= read -r host || [ -n "$host" ]; do
  host=$(echo "$host" | awk '{$1=$1; print}')
  if [ -z "$host" ] || [[ "$host" == \#* ]]; then
    continue
  fi

  idx=$((idx + 1))
  total_hosts=$((total_hosts + 1))
  rec_file="${work_dir}/host_${idx}.rec"

  # Run SSH with an additional local safety timeout covering connection + command
  local_limit=$((CONNECT_TIMEOUT + CMD_TIMEOUT + 5))
  raw_out=$(timeout "${local_limit}s" ssh "${ssh_opts[@]}" "${SSH_USER}@${host}" "$remote_payload" 2>"${work_dir}/err_${idx}.txt")
  ssh_rc=$?

  # Extract the structured OK|... line if present
  ok_line=$(printf "%s\n" "$raw_out" | awk -F'|' '$1 == "OK" && NF >= 5 { print; exit }')

  if [ "$ssh_rc" -eq 0 ] && [ -n "$ok_line" ]; then
    ok_hosts=$((ok_hosts + 1))
    printf "%s|%s\n" "$host" "$ok_line" > "$rec_file"
  else
    failed_hosts=$((failed_hosts + 1))
    if [ "$ssh_rc" -eq 124 ]; then
      reason="TIMEOUT (exceeded ${CMD_TIMEOUT}s command / ${local_limit}s total)"
    else
      err_hint=$(head -n 1 "${work_dir}/err_${idx}.txt" 2>/dev/null | tr '\n' ' ' | tr '|' '/')
      [ -z "$err_hint" ] && err_hint="SSH connection or command error (rc=${ssh_rc})"
      reason="UNREACHABLE/ERROR: ${err_hint}"
    fi
    printf "%s|FAIL|%s\n" "$host" "$reason" > "$rec_file"
  fi
done < "$SERVER_FILE"

{
  echo "=========================================================================================================="
  echo "CONSOLIDATED LINUX FLEET HEALTH REPORT"
  echo "Generated At    : $(date "+%Y-%m-%d %H:%M:%S %Z")"
  echo "Server List     : $SERVER_FILE"
  echo "SSH User / Port : ${SSH_USER}:${SSH_PORT} | Connect Timeout: ${CONNECT_TIMEOUT}s | Cmd Timeout: ${CMD_TIMEOUT}s"
  echo "Disk Mount      : $MOUNT_POINT"
  echo "=========================================================================================================="
  printf "%-22s  %-11s  %-8s  %-8s  %-9s  %s\n" "HOST" "STATE" "CPU (%)" "MEM (%)" "DISK (%)" "UPTIME / FAILURE DETAIL"
  echo "----------------------------------------------------------------------------------------------------------"

  if [ "$total_hosts" -eq 0 ]; then
    echo "(No servers found in '$SERVER_FILE'.)"
  else
    for ((i = 1; i <= total_hosts; i++)); do
      IFS='|' read -r h_name h_state f1 f2 f3 f4 < "${work_dir}/host_${i}.rec"
      if [ "$h_state" = "OK" ]; then
        printf "%-22s  %-11s  %-8s  %-8s  %-9s  %s\n" "$h_name" "HEALTHY_SSH" "$f1" "$f2" "$f3" "$f4"
      else
        printf "%-22s  %-11s  %-8s  %-8s  %-9s  %s\n" "$h_name" "FAILED" "-" "-" "-" "$f1"
      fi
    done
  fi

  echo "----------------------------------------------------------------------------------------------------------"
  printf "Fleet Summary -> Total: %d | Collected: %d | Failed/Timed Out: %d\n" "$total_hosts" "$ok_hosts" "$failed_hosts"
  echo "=========================================================================================================="
} | tee "$REPORT_FILE"

echo "Consolidated report saved to: $REPORT_FILE"

if [ "$total_hosts" -eq 0 ] || [ "$failed_hosts" -gt 0 ]; then
  exit 1
fi
exit 0
#Per-host isolation and fault tolerance: Each host writes to its own file inside a temporary directory (mktemp -d, cleaned up on EXIT via trap), so a failed SSH handshake, non-zero exit status, or hung remote command records a FAILED row and immediately moves to the next server in the list.

#Two-layer timeout protection: ConnectTimeout and BatchMode=yes prevent interactive password prompts or stalled TCP handshakes, while timeout on both the remote command (CMD_TIMEOUT) and local ssh invocation (local_limit) stops a hung df, free, or /proc/stat call from freezing the batch run.

#Single remote round-trip: Sends one bash -s script per host to read /proc/stat (0.5s delta for fast fleet sweeps), free, df -P, and uptime in one SSH session rather than opening four separate connections per server.

#Consolidated report + dual output: Formats every reachable host's metrics alongside every unreachable or timed-out host's failure reason, prints the table on screen via tee, saves it to $REPORT_FILE, and exits with 1 if any host failed.