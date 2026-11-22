# Write a shell script that accepts a filename from the user, 
# checks whether the file exists, and displays an appropriate message.
# If the file exists, display its size and permissions

#!/bin/bash

read -p "Enter filename: " file

if [ -f "$file" ]; then
  echo "File exists!"
  echo "Size: $(stat -c %s "$file") bytes"
  echo "Permissions: $(stat -c %A "$file")"
else
  echo "File does not exist."
fi

#!/bin/bash

read -p "Enter filename: " file

if [ -f "$file" ]; then
  echo "File exists!"
  echo "Size: $(ls -lh "$file" | awk '{print $5}')"
  echo "Permissions: $(ls -lh "$file" | awk '{print $1}')"
else
  echo "File does not exist."
fi