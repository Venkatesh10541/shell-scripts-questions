#Given a CSV file containing hostname, cpu, memory, and disk, write a 
#script that identifies servers exceeding configured utilization
# thresholds and generates a report of unhealthy servers.
# ans) To evaluate server metrics from a CSV file (hostname,cpu,memory,disk) against configurable thresholds, use awk with a comma field separator (-F,), skip the header row and blank lines, flag any server where CPU, memory, or disk exceeds its limit, and write a clean report to both stdout and a report file.
#!/bin/bash

CSV_FILE="${1:-${CSV_FILE:-./servers_metrics.csv}}"
CPU_LIMIT="${CPU_LIMIT:-80}"
MEM_LIMIT="${MEM_LIMIT:-85}"
DISK_LIMIT="${DISK_LIMIT:-90}"
REPORT_FILE="${REPORT_FILE:-./unhealthy_servers_report_$(date "+%Y%m%d_%H%M%S").txt}"

if [ ! -f "$CSV_FILE" ] || [ ! -r "$CSV_FILE" ]; then
  echo "Error: CSV file '$CSV_FILE' is missing or not readable." >&2
  echo "Usage: $0 [csv_file]" >&2
  echo "Optional env vars: CPU_LIMIT (default 80), MEM_LIMIT (default 85), DISK_LIMIT (default 90), REPORT_FILE" >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"

{
  echo "=========================================================================="
  echo "UNHEALTHY SERVERS REPORT"
  echo "Generated on : $(date "+%Y-%m-%d %H:%M:%S")"
  echo "Source CSV   : $CSV_FILE"
  echo "Thresholds   : CPU > ${CPU_LIMIT}%, MEM > ${MEM_LIMIT}%, DISK > ${DISK_LIMIT}%"
  echo "=========================================================================="
  printf "%-20s  %-8s  %-8s  %-8s  %s\n" "HOSTNAME" "CPU (%)" "MEM (%)" "DISK (%)" "EXCEEDED METRICS"
  echo "--------------------------------------------------------------------------"

  unhealthy_count=$(
    awk -F',' -v cpu_lim="$CPU_LIMIT" -v mem_lim="$MEM_LIMIT" -v disk_lim="$DISK_LIMIT" '
      function trim(s) {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
        return s
      }
      NR == 1 && tolower($1) ~ /^hostname$/ { next }
      {
        host = trim($1)
        cpu  = trim($2) + 0
        mem  = trim($3) + 0
        disk = trim($4) + 0

        if (host == "") next

        reasons = ""
        if (cpu > cpu_lim) {
          reasons = reasons (reasons != "" ? ", " : "") sprintf("CPU (%s%% > %s%%)", cpu, cpu_lim)
        }
        if (mem > mem_lim) {
          reasons = reasons (reasons != "" ? ", " : "") sprintf("MEM (%s%% > %s%%)", mem, mem_lim)
        }
        if (disk > disk_lim) {
          reasons = reasons (reasons != "" ? ", " : "") sprintf("DISK (%s%% > %s%%)", disk, disk_lim)
        }

        if (reasons != "") {
          printf "%-20s  %-8s  %-8s  %-8s  %s\n", host, cpu, mem, disk, reasons
          bad++
        }
      }
      END {
        print bad + 0 > "/tmp/unhealthy_count.tmp"
      }
    ' "$CSV_FILE"
  )

  count=0
  if [ -f /tmp/unhealthy_count.tmp ]; then
    count=$(cat /tmp/unhealthy_count.tmp)
    rm -f /tmp/unhealthy_count.tmp
  fi

  if [ "$count" -eq 0 ]; then
    echo "(No servers exceeded the configured thresholds.)"
  fi

  echo "--------------------------------------------------------------------------"
  echo "Total unhealthy servers: $count"
  echo "=========================================================================="
} | tee "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"

if [ "$count" -gt 0 ]; then
  exit 1
fi
exit 0
#CSV parsing with awk -F',': Splits each row on commas and trims accidental spaces around values (trim(s)), while skipping a hostname header row (NR == 1 && tolower($1) ~ /^hostname$/).

#Configurable limits via environment variables: CPU_LIMIT, MEM_LIMIT, and DISK_LIMIT default to 80, 85, and 90 percent, and can be overridden per run without editing the script.

#Collecting every breached metric per host: Instead of stopping on the first high metric, reasons appends each violated threshold (CPU, MEM, DISK) so a server running hot on both CPU and disk shows both issues clearly.

#Dual output and exit code (tee + exit 1): Prints the formatted report on screen, saves a copy to $REPORT_FILE, and exits with 1 when unhealthy servers are found (or 0 when all hosts are within limits).