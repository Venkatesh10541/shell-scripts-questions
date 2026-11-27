#Write a script that accepts a username and environment name through
# command-line arguments. Validate that both arguments are provided and
# display usage instructions otherwise. 
# ans) To pass values right when running a script instead of using read, Bash uses positional parameters ($1, $2, and so on). Here is a clear, beginner-friendly script that checks that both arguments are present and prints usage instructions if either is missing.
#!/bin/bash

username="$1"
env_name="$2"

if [ -z "$username" ] || [ -z "$env_name" ]; then
  echo "Error: Both username and environment name are required."
  echo "Usage: $0 <username> <environment>"
  echo "Example: $0 rohan staging"
  exit 1
fi

echo "Username:    $username"
echo "Environment: $env_name"
#$1 and $2: Hold the first and second command-line arguments passed when you run the script ($0 is the script's own name).

#[ -z "$username" ] || [ -z "$env_name" ]: Checks whether username is empty (-z means "zero length / empty string") or (||) env_name is empty. If either is missing, validation fails.

#Usage: $0 <username> <environment>: Prints the exact expected format using $0 so it automatically shows whatever filename you used to run the script.

#exit 1: Stops the script immediately with a non-zero exit status so the rest of the script does not run with incomplete inputs.
