#Write a script that creates the following directories using a for loop:
# development, testing, staging, production
# Verify that all directories were created successfully.
#!/bin/bash

envs="development testing staging production"
all_ok=true

for dir in $envs; do
  mkdir -p "$dir"

  if [ -d "$dir" ]; then
    echo "OK: '$dir' exists."
  else
    echo "FAILED: '$dir' was not created."
    all_ok=false
  fi
done

echo "--- Summary ---"
if [ "$all_ok" = true ]; then
  echo "All directories created successfully."
  ls -ld $envs
else
  echo "One or more directories failed."
fi
#for dir in $envs: Loops through development, testing, staging, and production one by one, storing each name in dir.

#mkdir -p "$dir": Creates the directory if it does not exist, and avoids throwing an error if you run the script a second time when the folder is already there.

#if [ -d "$dir" ]: Confirms that each directory actually exists after mkdir runs, and flips all_ok to false if any check fails.

#ls -ld $envs: Shows the created directories as directory entries (-d prevents ls from listing inside them) in long format (-l) as a quick visual check.