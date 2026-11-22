#Write a script that accepts a username and 
# checks whether the user exists on the Linux server. 
# If the user exists, display their UID and primary group.

#!/bin/bash

read -p "Enter username: " username

if id "$username" >/dev/null 2>&1; then
  echo "User '$username' exists."
  echo "UID: $(id -u "$username")"
  echo "Primary Group: $(id -gn "$username")"
else
  echo "User '$username' does not exist."
fi
#id "$username" >/dev/null 2>&1: Tests whether the user exists while sending both normal output and "no such user" error messages to /dev/null so the terminal stays clean.

#id -u "$username": Prints only the numeric User ID (UID).

#id -gn "$username": Prints the name of the user's primary group (-g gives the primary group ID, and -n converts it to the group name).