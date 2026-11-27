#Write a function named check_cpu that accepts a 
# CPU utilization percentage and returns an appropriate success 
# or failure exit status based on a configurable threshold. 
#!/bin/bash

# Configurable threshold (default is 80 if not set earlier)
CPU_THRESHOLD="${CPU_THRESHOLD:-80}"

check_cpu() {
  local cpu_usage="$1"
  local threshold="${2:-$CPU_THRESHOLD}"

  if [ -z "$cpu_usage" ]; then
    echo "Error: CPU usage value is required."
    return 1
  fi

  if [ "$cpu_usage" -gt "$threshold" ]; then
    echo "ALERT: CPU usage is ${cpu_usage}% (above threshold of ${threshold}%)."
    return 1
  else
    echo "OK: CPU usage is ${cpu_usage}% (within threshold of ${threshold}%)."
    return 0
  fi
}

# --- Example Usage ---
if check_cpu 45; then
  echo "Action: Normal operation."
else
  echo "Action: Investigate high CPU!"
fi

if check_cpu 92 85; then
  echo "Action: Normal operation."
else
  echo "Action: Trigger high-CPU warning!"
fi
#CPU_THRESHOLD="${CPU_THRESHOLD:-80}": Sets a default threshold of 80 percent, while letting you override it from the environment (for example, CPU_THRESHOLD=75 ./script.sh).

#local cpu_usage="$1": Reads the first argument passed to the check_cpu function ($1 inside a function is the function's own argument, not the script's command-line argument). Keeping it local avoids clashing with variables outside the function.

#local threshold="${2:-$CPU_THRESHOLD}": Uses a second argument if you pass one (like check_cpu 92 85), or falls back to $CPU_THRESHOLD if you only pass one argument.

#-gt ("greater than"): Compares integer percentages cleanly. If $cpu_usage is greater than $threshold, the function prints an alert and runs return 1 (failure/alert); otherwise it prints OK and runs return 0 (success).

#if check_cpu ...: Because 0 means true/success in Bash, if check_cpu 45 enters the then block, while if check_cpu 92 85 enters the else block.

#Note: [ "$cpu_usage" -gt "$threshold" ] works best with whole numbers (integers). If your CPU metric produces decimals like 45.6, you can round or strip decimals first before comparing with -gt.