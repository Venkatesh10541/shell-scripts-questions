#Write a script that reads server IP addresses or hostnames from a text 
#file, attempts SSH connectivity to each server, and generates separate 
#lists of reachable and unreachable servers. 
#Implement connection timeouts.
# ans) To test SSH reachability across a list of hosts without a dead server hanging your script for minutes, pass ConnectTimeout to ssh and use BatchMode=yes so SSH fails fast instead of waiting for an interactive password prompt.
#!/bin/bash

SERVER_FILE="${1:-servers.txt}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_PORT="${SSH_PORT:-22}"
TIMEOUT_SEC="${TIMEOUT_SEC:-5}"

REACHABLE_FILE="reachable_servers.txt"
UNREACHABLE_FILE="unreachable_servers.txt"

if [ ! -f "$SERVER_FILE" ]; then
  echo "Error: Server list file '$SERVER_FILE' not found."
  echo "Usage: $0 [servers_file]"
  exit 1
fi

# Reset output files for a fresh run
: > "$REACHABLE_FILE"
: > "$UNREACHABLE_FILE"

while IFS= read -r host || [ -n "$host" ]; do
  # Trim leading/trailing whitespace and skip blank or comment lines
  host=$(echo "$host" | awk '{$1=$1; print}')
  if [ -z "$host" ] || [[ "$host" == \#* ]]; then
    continue
  fi

  if ssh -p "$SSH_PORT" \
         -o ConnectTimeout="$TIMEOUT_SEC" \
         -o BatchMode=yes \
         -o StrictHostKeyChecking=accept-new \
         "${SSH_USER}@${host}" "exit 0" >/dev/null 2>&1; then
    echo "REACHABLE:   $host"
    echo "$host" >> "$REACHABLE_FILE"
  else
    echo "UNREACHABLE: $host"
    echo "$host" >> "$UNREACHABLE_FILE"
  fi
done < "$SERVER_FILE"

echo "--- Summary ---"
echo "Reachable saved to:   $REACHABLE_FILE ($(wc -l < "$REACHABLE_FILE"))"
echo "Unreachable saved to: $UNREACHABLE_FILE ($(wc -l < "$UNREACHABLE_FILE"))"
#while IFS= read -r host || [ -n "$host" ] + < "$SERVER_FILE": Reads each line cleanly from the input file (IFS= prevents stripping leading spaces during read, and [ -n "$host" ] ensures a trailing line without a newline is still processed).

#-o ConnectTimeout="$TIMEOUT_SEC": Sets the network connection timeout in seconds (default 5s), preventing a dropped packet or firewalled host from stalling the loop.

#-o BatchMode=yes: Disables interactive password/passphrase prompts so unreachable or unkeyed hosts fail immediately instead of waiting for human input.

#-o StrictHostKeyChecking=accept-new: Automatically accepts new host keys on first connection while still rejecting changed keys, avoiding interactive (yes/no) prompts that block automation.

#>/dev/null 2>&1 and >> output files: Discards noisy SSH output on the terminal while appending each host to reachable_servers.txt or unreachable_servers.txt based on whether the SSH check succeeded (0) or failed (non-zero).