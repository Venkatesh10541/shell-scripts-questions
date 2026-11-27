#Write a script that creates an application log file and writes five 
#events with timestamps and log levels such as INFO, WARNING, and ERROR.
# ans) To write structured application logs in Bash, generate a timestamp with date and append formatted lines (>>) to a log file using a small helper function so every entry stays consistent.
#!/bin/bash

LOG_FILE="./app.log"

# Ensure the parent directory exists and start/append to the log file
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"

log_event() {
  local level="$1"
  local message="$2"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")

  echo "[$ts] [$level] $message" >> "$LOG_FILE"
}

# Write five sample application events
log_event "INFO" "Application startup initiated."
log_event "INFO" "Loaded configuration for environment 'staging'."
log_event "WARNING" "Response latency exceeded 500ms on /healthz."
log_event "ERROR" "Failed to connect to database replica db-02."
log_event "INFO" "Retrying database connection in 5 seconds."

echo "Wrote 5 events to '$LOG_FILE':"
cat "$LOG_FILE"
#date "+%Y-%m-%d %H:%M:%S": Formats the current date and time cleanly (for example, 2026-11-27 13:39:00) so events are easy to read and sort chronologically.

#log_event helper function: Takes two arguments—log level (INFO, WARNING, ERROR) and message—so you do not repeat date and >> "$LOG_FILE" on every line.

#>> "$LOG_FILE": Appends each new event to the log file rather than overwriting earlier lines. (: > "$LOG_FILE" at the top resets the file when you re-run this demo script; remove that line if you want runs to accumulate.)

#Consistent [LEVEL] tags: Putting levels like INFO, WARNING, and ERROR in brackets makes filtering later with grep or awk straightforward.