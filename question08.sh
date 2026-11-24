#Write a script that accepts a service name and 
#checks whether the service is active using systemctl. 
#Display the service status and handle invalid service names.
#!/bin/bash

read -p "Enter service name: " service

# Check if systemd knows this service unit (catches invalid/non-existent names)
if ! systemctl cat "$service" >/dev/null 2>&1; then
  echo "Invalid service name: '$service' does not exist."
  exit 1
fi

# Check whether the service is currently active
if systemctl is-active --quiet "$service"; then
  echo "Service '$service' is ACTIVE."
else
  echo "Service '$service' is INACTIVE (state: $(systemctl is-active "$service"))."
fi

#echo "--- Status Summary ---"
#systemctl status --no-pager --lines=5 "$service"
#systemctl cat "$service" >/dev/null 2>&1: Checks if systemd has a unit file for $service. If you type a made-up name like fakething123, this fails cleanly so the script prints Invalid service name instead of confusing it with a stopped service.

#systemctl is-active --quiet "$service": Returns 0 (true) when the service is running/active (--quiet suppresses printing active or inactive on its own).

#systemctl status --no-pager --lines=5 "$service": Shows a short status view without opening an interactive pager that waits for you to press q.

#Note: You can type either ssh or ssh.service—systemctl treats both the same for service units.