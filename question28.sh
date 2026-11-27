#Write a script that collects hostname, IP address, uptime, CPU utilization,
# memory utilization, and disk utilization, then saves the results in
# CSV format with a timestamp. 
# ans) To record host snapshots over time in CSV format, create the output file with a header row if it does not exist yet, gather each metric cleanly into a variable, escape or quote text fields (such as uptime) so commas never break CSV columns, and append a timestamped row on every run.
#!/bin/bash

CSV_FILE="${1:-${CSV_FILE:-./host_metrics.csv}}"
MOUNT_POINT="${MOUNT_POINT:-/}"

mkdir -p "$(dirname "$CSV_FILE")"

get_ip_address() {
  local ip=""

  if command -v ip >/dev/null 2>&1; then
    # Prefer primary IPv4 address used for default routing
    ip=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{
      for (i = 1; i <= NF; i++) {
        if ($i == "src") {
          print $(i + 1)
          exit
        }
      }
    }')

    # Fallback to first non-loopback IPv4 address if no default route exists
    if [ -z "$ip" ]; then
      ip=$(ip -4 -o addr show scope global 2>/dev/null | awk 'NR==1 { split($4, a, "/"); print a[1] }')
    fi
  fi

  if [ -z "$ip" ] && command -v hostname >/dev/null 2>&1; then
    ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  fi

  printf "%s" "${ip:-N/A}"
}

get_uptime_summary() {
  if command -v uptime >/dev/null 2>&1; then
    uptime -p 2>/dev/null || uptime 2>/dev/null | sed 's/^[[:space:]]*//'
  elif [ -r /proc/uptime ]; then
    awk '{
      sec = int($1)
      days = int(sec / 86400)
      hrs = int((sec % 86400) / 3600)
      mins = int((sec % 3600) / 60)
      printf "up %d days, %d hours, %d minutes\n", days, hrs, mins
    }' /proc/uptime
  else
    printf "N/A"
  fi
}

get_cpu_pct() {
  local u1 n1 s1 i1 w1 irq1 sirq1 u2 n2 s2 i2 w2 irq2 sirq2
  read -r _ u1 n1 s1 i1 w1 irq1 sirq1 _ < /proc/stat
  sleep 1
  read -r _ u2 n2 s2 i2 w2 irq2 sirq2 _ < /proc/stat

  local idle1=$((i1 + w1))
  local idle2=$((i2 + w2))
  local total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1))
  local total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2))

  local total_diff=$((total2 - total1))
  local idle_diff=$((idle2 - idle1))

  if [ "$total_diff" -gt 0 ]; then
    printf "%d" "$(( (100 * (total_diff - idle_diff) + total_diff / 2) / total_diff ))"
  else
    printf "0"
  fi
}

get_mem_pct() {
  free | awk '/^Mem:/ {
    if ($2 > 0) {
      printf "%d", (($3 / $2) * 100) + 0.5
    } else {
      print 0
    }
  }'
}

get_disk_pct() {
  df -P "$MOUNT_POINT" 2>/dev/null | awk 'NR==2 {
    gsub("%", "", $5)
    print $5 + 0
  }'
}

csv_escape() {
  local val="$1"
  val="${val//\"/\"\"}"
  printf "\"%s\"" "$val"
}

timestamp=$(date "+%Y-%m-%d %H:%M:%S")
host_name=$(hostname 2>/dev/null || uname -n)
ip_addr=$(get_ip_address)
uptime_val=$(get_uptime_summary)
cpu_pct=$(get_cpu_pct)
mem_pct=$(get_mem_pct)
disk_pct=$(get_disk_pct)

# Write CSV header once when the file does not exist or is empty
if [ ! -s "$CSV_FILE" ]; then
  echo "timestamp,hostname,ip_address,uptime,cpu_pct,mem_pct,disk_pct" > "$CSV_FILE"
fi

{
  csv_escape "$timestamp"
  printf ","
  csv_escape "$host_name"
  printf ","
  csv_escape "$ip_addr"
  printf ","
  csv_escape "$uptime_val"
  printf ",%s,%s,%s\n" "$cpu_pct" "$mem_pct" "$disk_pct"
} >> "$CSV_FILE"

echo "Saved metrics snapshot to '$CSV_FILE':"
tail -n 2 "$CSV_FILE"
#Header-safe CSV initialization ([ ! -s "$CSV_FILE" ]): Creates the column header once on the first run and appends new rows on subsequent runs without duplicating the header or wiping historical snapshots.

#CSV field quoting (csv_escape): Wraps text values in double quotes and doubles any internal quotes (" becomes ""), which prevents commas inside uptime strings (such as up 3 days, 4 hours, 12 minutes) from splitting into extra CSV columns.

#Reliable IP detection (get_ip_address): Checks ip -4 route get first to pick the active outbound IPv4 address on multi-interface hosts, falling back to ip -4 -o addr show or hostname -I if needed.

#Two-sample CPU delta + free + df -P: Measures live CPU utilization over a 1-second interval from /proc/stat, computes rounded memory usage from free, and extracts filesystem percentage from df -P "$MOUNT_POINT".