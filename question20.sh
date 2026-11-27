#Write a script that reads an application log file and calculates the 
#number of ERROR, WARNING, and INFO entries. Identify the five most 
#frequently occurring error messages.
# ans) To summarize log levels and find the top repeated errors quickly in Bash, combine awk (to spot log levels and strip the message text) with sort, uniq -c, and sort -rn (to count and rank duplicates).
#!/bin/bash

LOG_FILE="${1:-${LOG_FILE:-./app.log}}"

if [ ! -f "$LOG_FILE" ]; then
  echo "Error: Log file '$LOG_FILE' not found."
  echo "Usage: $0 [log_file]"
  exit 1
fi

# 1. Count ERROR, WARNING, and INFO lines in a single awk pass
read -r info_count warn_count err_count < <(
  awk '
    {
      if ($0 ~ /(^|[^A-Za-z])INFO([^A-Za-z]|$)/) info++
      else if ($0 ~ /(^|[^A-Za-z])WARNING([^A-Za-z]|$)/ || $0 ~ /(^|[^A-Za-z])WARN([^A-Za-z]|$)/) warn++
      else if ($0 ~ /(^|[^A-Za-z])ERROR([^A-Za-z]|$)/ || $0 ~ /(^|[^A-Za-z])ERR([^A-Za-z]|$)/) err++
    }
    END {
      printf "%d %d %d\n", info + 0, warn + 0, err + 0
    }
  ' "$LOG_FILE"
)

echo "=== Log Level Summary ($LOG_FILE) ==="
echo "INFO:    $info_count"
echo "WARNING: $warn_count"
echo "ERROR:   $err_count"
echo ""
echo "=== Top 5 Most Frequent Error Messages ==="

# 2. Extract error messages, normalize leading/trailing spaces, count, and show top 5
top_errors=$(
  awk '
    $0 ~ /(^|[^A-Za-z])ERROR([^A-Za-z]|$)/ || $0 ~ /(^|[^A-Za-z])ERR([^A-Za-z]|$)/ {
      msg = $0
      # Strip common prefix like "[2026-11-27 14:26:00] [ERROR] " or "2026-11-27 ERROR: "
      sub(/^.*(ERROR|ERR)\]?:?[[:space:]]*/, "", msg)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", msg)
      if (length(msg) > 0) {
        print msg
      }
    }
  ' "$LOG_FILE" | sort | uniq -c | sort -rn | head -n 5
)

if [ -z "$top_errors" ]; then
  echo "No ERROR entries found."
else
  echo "$top_errors"
fi
#Single-pass awk counts: Scans $LOG_FILE once and increments counters for INFO, WARNING (also catching WARN), and ERROR (also catching ERR), using word boundaries /(^|[^A-Za-z])ERROR([^A-Za-z]|$)/ so words like ERROR_CODE or NONFATAL_ERROR don't confuse simple substring checks.

#Stripping timestamps and level tags: In the second awk block, sub(/^.*(ERROR|ERR)\]?:?[[:space:]]*/, "", msg) removes the date, time, and [ERROR] label so identical error messages match even if their timestamps differ.

#sort | uniq -c | sort -rn | head -n 5 pipeline:

#sort groups identical error messages next to each other (required before uniq -c).

#uniq -c counts how many times each message appears.

#sort -rn sorts numerically in reverse (highest count first).

# head -n 5 keeps only the top five.