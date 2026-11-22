# Write a script that accepts a directory path, 
# checks whether the directory exists, and creates it if it does not. 
# If it already exists, display a message without modifying it.
#!/bin/bash

read -p "Enter directory path: " dir

if [ -d "$dir" ]; then
  echo "Directory '$dir' already exists."
else
  mkdir -p "$dir"
  echo "Directory '$dir' created."
fi

# mkdir -p "$dir": Creates the directory and any missing parent folders in one step, without failing if intermediate directories are missing.