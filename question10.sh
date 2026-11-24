#Create an array containing five server names. 
# Write a script that iterates through 
# the array and displays each server name with its index number.
# ans) To store multiple values in a list and loop through them with index numbers in Bash, use an indexed array (servers=(...)) and iterate over ${!servers[@]} (the exclamation mark gives the array indices).
#!/bin/bash

# Create an array of five server names
servers=("web-01" "web-02" "db-01" "cache-01" "lb-01")

# Loop through each index in the array
for i in "${!servers[@]}"; do
  echo "Index $i: ${servers[$i]}"
done
#servers=(...): Creates a Bash array holding five server names. Notice there are spaces between items, no commas.

#${!servers[@]}: Returns all valid index numbers of the servers array (0, 1, 2, 3, 4—Bash arrays start at 0).

#${servers[$i]}: Fetches the server name at index $i. Double-quoting "${servers[$i]}" is good practice so names with spaces or special characters stay safe.

#If you prefer 1-based numbering (1 to 5) for display purposes, you can print $((i + 1)) instead of $i:
echo "Server $((i + 1)): ${servers[$i]}"