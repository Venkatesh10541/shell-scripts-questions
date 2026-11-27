#Write a script that iterates through numbers 1–30, skips 
# numbers divisible by 3 using continue, and
# stops execution when the number reaches 25 using break.
#!/bin/bash

for ((i = 1; i <= 30; i++)); do
  # Stop the loop completely when i reaches 25
  if [ "$i" -eq 25 ]; then
    echo "Reached 25 — stopping loop."
    break
  fi

  # Skip numbers divisible by 3 (remainder after dividing by 3 is 0)
  if [ $((i % 3)) -eq 0 ]; then
    continue
  fi

  echo "$i"
done
#for ((i = 1; i <= 30; i++)): Arithmetic for loop in Bash that starts i at 1, runs while i is less than or equal to 30, and increases i by 1 each pass.

#[ "$i" -eq 25 ] + break: Checks if i equals 25 (-eq means "equal to"). break exits the loop immediately, so 25 is not printed and numbers 26 through 30 are never reached.

#$((i % 3)) + continue: % is the modulo (remainder) operator. When a number is divisible by 3, i % 3 is 0. continue skips the rest of the current loop pass (so echo "$i" does not run for 3, 6, 9, 12, 15, 18, 21, 24) and jumps straight to the next number (i + 1).
