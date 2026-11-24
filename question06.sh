#Write a script that checks filesystem utilization.
 # If any monitored filesystem exceeds 80%, 
# display a warning containing its mount point and usage percentage.
#!/bin/bash

threshold=80

df -P | awk 'NR>1 {print $5, $6}' | while read -r use_pct mount; do
  # Strip the trailing '%' sign to get a plain number
  pct="${use_pct%%%}"

  if [ "$pct" -gt "$threshold" ]; then
    echo "WARNING: Filesystem '$mount' is at ${pct}% usage!"
  fi
done
#df -P: Lists disk space per filesystem in clean, single-line columns (Filesystem, 1024-blocks, Used, Available, Capacity, Mounted on).

#awk 'NR>1 {print $5, $6}': Skips the header line (NR>1) and prints only Capacity ($5, like 42%) and Mounted on ($6, like /).

#"${use_pct%%%}": Removes the % character from 42% so [ "$pct" -gt "$threshold" ] can compare it numerically.

#Why while read? It checks every filesystem one by one and prints a warning for each mount point above 80%, rather than stopping at just one.

#If you want to ignore virtual or special filesystems (like tmpfs or overlay) and check only real disks/mounts, you can pass df -P -x tmpfs -x devtmpfs -x overlay instead.