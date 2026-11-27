#Write a script that searches a specified directory for files older than 
#seven days. Display their names, sizes, and modification dates.
# Generate a report without deleting any files. 
#ans) To audit old files safely without touching or removing anything, pair find (-type f and -mtime +7) with stat (to read exact human-readable file size and last modification timestamp) and write the results to a report file while also displaying them on screen.
#!/bin/bash

TARGET_DIR="${1:-${TARGET_DIR:-}}"
DAYS_OLD="${DAYS_OLD:-7}"
REPORT_FILE="${REPORT_FILE:-./stale_files_report_$(date "+%Y%m%d_%H%M%S").txt}"

if [ -z "$TARGET_DIR" ]; then
  echo "Error: Target directory is required."
  echo "Usage: $0 <directory_path>"
  echo "Optional env vars: DAYS_OLD (default 7), REPORT_FILE"
  exit 1
fi

if [ ! -d "$TARGET_DIR" ]; then
  echo "Error: '$TARGET_DIR' is not a valid directory."
  exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"

{
  echo "=================================================================="
  echo "STALE FILES REPORT (Files older than ${DAYS_OLD} days - NO FILES DELETED)"
  echo "Generated on : $(date "+%Y-%m-%d %H:%M:%S")"
  echo "Target Folder: $TARGET_DIR"
  echo "=================================================================="
  printf "%-10s  %-19s  %s\n" "SIZE" "MODIFIED DATE" "FILE NAME"
  echo "------------------------------------------------------------------"

  count=0

  # -type f matches regular files only (not directories)
  # +N matches strictly older than N*24 hours
  while IFS= read -r -d '' filepath; do
    size_human=$(stat -c "%s" "$filepath" 2>/dev/null | awk '
      {
        bytes = $1 + 0
        if (bytes >= 1073741824) printf "%.2f GB", bytes / 1073741824
        else if (bytes >= 1048576) printf "%.2f MB", bytes / 1048576
        else if (bytes >= 1024) printf "%.2f KB", bytes / 1024
        else printf "%d B", bytes
      }
    ')
    mod_date=$(stat -c "%y" "$filepath" 2>/dev/null | cut -d'.' -f1)

    printf "%-10s  %-19s  %s\n" "$size_human" "$mod_date" "$filepath"
    count=$((count + 1))
  done < <(find "$TARGET_DIR" -type f -mtime +"$DAYS_OLD" -print0 2>/dev/null | sort -z)

  echo "------------------------------------------------------------------"
  echo "Total matching files: $count"
  echo "=================================================================="
} | tee "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"
#Strict read-only safety: There is no rm or -delete anywhere in the script—it only reads metadata (find and stat) and writes a report file.

#-type f -mtime +7: -type f targets regular files (skipping folders), and -mtime +7 selects files whose content was last modified more than 7 days ago (more than 7 * 24 hours).

#-print0 + read -r -d '': Handles file names containing spaces, newlines, or special characters safely without breaking columns.

#stat -c "%s" and stat -c "%y": Pulls exact byte size (formatted cleanly into B, KB, MB, or GB with awk) and last modification timestamp (trimmed to YYYY-MM-DD HH:MM:SS with cut -d'.' -f1).

#tee "$REPORT_FILE": Prints the formatted table to your terminal and saves the exact same report to $REPORT_FILE in one pass.