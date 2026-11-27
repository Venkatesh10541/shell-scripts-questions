#Develop a script that collects CPU, memory, and disk utilization from a 
#Linux server. Compare each metric against configurable thresholds and 
#display an overall HEALTHY, WARNING, or CRITICAL status. 
# ans) To build a clean, beginner-friendly health check script, combine the core tools you already know—awk for parsing fields, free for memory, and df for disk usage—with warning and critical thresholds that roll up into a single overall status (CRITICAL beats WARNING, and HEALTHY means every metric stayed below warning).
#!/bin/bash

# Configurable thresholds (percentages)
CPU_WARN="${CPU_WARN:-70}"
CPU_CRIT="${CPU_CRIT:-90}"

MEM_WARN="${MEM_WARN:-75}"
MEM_CRIT="${MEM_CRIT:-90}"

DISK_WARN="${DISK_WARN:-80}"
DISK_CRIT="${DISK_CRIT:-95}"
MOUNT_POINT="${MOUNT_POINT:-/}"

overall_status="HEALTHY"

# Elevate overall_status only in one direction: HEALTHY -> WARNING -> CRITICAL
raise_status() {
  local new_state="$1"

  if [ "$new_state" = "CRITICAL" ]; then
    overall_status="CRITICAL"
  elif [ "$new_state" = "WARNING" ] && [ "$overall_status" != "CRITICAL" ]; then
    overall_status="WARNING"
  fi
}

evaluate_metric() {
  local name="$1"
  local value="$2"
  local warn_limit="$3"
  local crit_limit="$4"

  if [ "$value" -ge "$crit_limit" ]; then
    echo "[$name] ${value}% -> CRITICAL (crit >= ${crit_limit}%, warn >= ${warn_limit}%)"
    raise_status "CRITICAL"
  elif [ "$value" -ge "$warn_limit" ]; then
    echo "[$name] ${value}% -> WARNING (warn >= ${warn_limit}%, crit >= ${crit_limit}%)"
    raise_status "WARNING"
  else
    echo "[$name] ${value}% -> HEALTHY (warn >= ${warn_limit}%, crit >= ${crit_limit}%)"
  fi
}

# 1. CPU utilization from /proc/stat (two short samples for accuracy)
read -r _ u1 n1 s1 i1 w1 irq1 sirq1 _ < /proc/stat
sleep 1
read -r _ u2 n2 s2 i2 w2 irq2 sirq2 _ < /proc/stat

idle1=$((i1 + w1))
idle2=$((i2 + w2))
total1=$((u1 + n1 + s1 + i1 + w1 + irq1 + sirq1))
total2=$((u2 + n2 + s2 + i2 + w2 + irq2 + sirq2))

total_diff=$((total2 - total1))
idle_diff=$((idle2 - idle1))

if [ "$total_diff" -gt 0 ]; then
  cpu_pct=$(( (100 * (total_diff - idle_diff) + total_diff / 2) / total_diff ))
else
  cpu_pct=0
fi

# 2. Memory utilization from `free` (using Mem: row)
mem_pct=$(free | awk '/^Mem:/ {
  if ($2 > 0) {
    printf "%d\n", (($3 / $2) * 100) + 0.5
  } else {
    print 0
  }
}')

# 3. Disk utilization for target mount point using `df -P`
disk_pct=$(df -P "$MOUNT_POINT" | awk 'NR==2 {
  gsub("%", "", $5)
  print $5 + 0
}')

echo "=== Host Health Report ($(hostname)) ==="
evaluate_metric "CPU"  "$cpu_pct"  "$CPU_WARN"  "$CPU_CRIT"
evaluate_metric "MEM"  "$mem_pct"  "$MEM_WARN"  "$MEM_CRIT"
evaluate_metric "DISK ($MOUNT_POINT)" "$disk_pct" "$DISK_WARN" "$DISK_CRIT"

echo "--------------------------------------"
echo "OVERALL STATUS: $overall_status"

case "$overall_status" in
  HEALTHY)  exit 0 ;;
  WARNING)  exit 1 ;;
  CRITICAL) exit 2 ;;
esac
#Configurable thresholds via parameter expansion: Variables like CPU_WARN="${CPU_WARN:-70}" and CPU_CRIT="${CPU_CRIT:-90}" give sensible defaults while letting you override any limit on the fly (for example, CPU_WARN=50 DISK_WARN=60 ./health_check.sh).

#One-way severity state (raise_status): Instead of using a simple boolean flag, overall_status tracks three states. raise_status makes sure a later WARNING or HEALTHY metric never downgrades an earlier CRITICAL finding.

#CPU calculation with integer math: Reading /proc/stat twice 1 second apart measures real active vs. idle ticks, and (100 * busy + total / 2) / total rounds to the nearest whole percentage in pure Bash (-ge works cleanly on integers).

#Memory check with free and awk: On the Mem: line, $2 is total memory and $3 is used memory; awk calculates the rounded percentage without needing external tools.

#Disk check with df -P and awk: Using df -P (POSIX format) keeps long filesystem names on a single line so $5 is reliably the use percentage, and gsub("%", "", $5) strips % before comparing.

#Meaningful exit codes: Exiting 0 for HEALTHY, 1 for WARNING, and 2 for CRITICAL makes the script easy to chain with other commands or monitoring jobs.