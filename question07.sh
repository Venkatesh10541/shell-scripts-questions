#Write a script that accepts a process name and
# checks whether the process is running. 
# If running, display its PID. Otherwise, display PROCESS NOT RUNNING.
#!/bin/bash

read -p "Enter process name: " proc

pids=$(pgrep -x "$proc")

if [ -n "$pids" ]; then
  echo "Process '$proc' is running."
  echo "PID(s): $pids"
else
  echo "PROCESS NOT RUNNING"
fi
#pgrep -x "$proc": Searches running processes for an exact match on the process name (-x avoids accidental matches like matching ssh when you meant sshd). If found, it prints the matching PIDs.

#[ -n "$pids" ]: Checks whether $pids is non-empty (-n means "non-empty string").

#If running: Prints a confirmation message along with the PID(s) (if multiple copies are running, it lists each PID).

#If not running: Prints PROCESS NOT RUNNING in uppercase just as requested.