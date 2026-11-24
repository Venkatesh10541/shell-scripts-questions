# Write a script that collects actual system memory utilization and
# checks whether usage exceeds 80%. 
#Display total, used, available memory, and utilization percentage.
#!/bin/bash

# Read total and available memory (in MB) from the "Mem:" line
total=$(free -m | awk '/^Mem:/ {print $2}')
avail=$(free -m | awk '/^Mem:/ {print $7}')

# Actual used memory = total minus available
used=$((total - avail))
pct=$((used * 100 / total))

echo "Total Memory:     ${total} MB"
echo "Used Memory:      ${used} MB"
echo "Available Memory: ${avail} MB"
echo "Memory Usage:     ${pct}%"

if [ "$pct" -gt 80 ]; then
  echo "Status: ABOVE 80% (High memory usage)"
else
  echo "Status: OK (80% or below)"
fi
#free -m: Displays RAM in megabytes (MB) on a single Mem: row.

#awk '/^Mem:/ ...': Matches the line starting with Mem: and grabs column $2 (total) and column $7 (available).

#used=$((total - avail)): Computes real in-use memory by subtracting available from total.

#pct=$((used * 100 / total)): Calculates whole-number percentage so [ "$pct" -gt 80 ] works cleanly (-gt means "greater than").

