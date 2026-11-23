# Write a script that accepts CPU utilization as input and displays:
#Below 70%: NORMAL
#70% to 85%: WARNING
#Above 85%: CRITICAL
#!/bin/bash

read -p "Enter CPU utilization (%): " cpu

if [ "$cpu" -lt 70 ]; then
  echo "NORMAL"
elif [ "$cpu" -le 85 ]; then
  echo "WARNING"
else
  echo "CRITICAL"
fi

#!/bin/bash

idle=$(top -bn1 | grep "Cpu(s)" | awk -F',' '{print $4}' | awk '{print $1}')
cpu=$(awk "BEGIN {printf \"%.0f\", 100 - $idle}")

echo "Current CPU Utilization: ${cpu}%"

if [ "$cpu" -lt 70 ]; then
  echo "Status: NORMAL"
elif [ "$cpu" -le 85 ]; then
  echo "Status: WARNING"
else
  echo "Status: CRITICAL"
fi