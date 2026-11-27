#Write a script that compares two application configuration files and
# generates a report showing added, removed, and modified lines
# ans) To compare two configuration files (OLD_FILE and NEW_FILE) and separate lines into added, removed, and modified, pair diff -u with an awk parser that turns raw unified-diff hunks into clear change categories (+ ADDED, - REMOVED, ~ MODIFIED) and writes a readable report to stdout and a file.
#!/bin/bash

OLD_FILE="${1:-${OLD_FILE:-}}"
NEW_FILE="${2:-${NEW_FILE:-}}"
REPORT_FILE="${REPORT_FILE:-./config_diff_report_$(date "+%Y%m%d_%H%M%S").txt}"

if [ -z "$OLD_FILE" ] || [ -z "$NEW_FILE" ]; then
  echo "Error: Both old and new configuration file paths are required." >&2
  echo "Usage: $0 <old_config_file> <new_config_file>" >&2
  echo "Optional env vars: REPORT_FILE" >&2
  exit 1
fi

if [ ! -f "$OLD_FILE" ] || [ ! -r "$OLD_FILE" ]; then
  echo "Error: Old config file '$OLD_FILE' does not exist or is not readable." >&2
  exit 1
fi

if [ ! -f "$NEW_FILE" ] || [ ! -r "$NEW_FILE" ]; then
  echo "Error: New config file '$NEW_FILE' does not exist or is not readable." >&2
  exit 1
fi

if ! command -v diff >/dev/null 2>&1; then
  echo "Error: 'diff' command is not installed." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"

{
  echo "=========================================================================="
  echo "CONFIGURATION COMPARISON REPORT"
  echo "Generated on : $(date "+%Y-%m-%d %H:%M:%S")"
  echo "Old Config   : $OLD_FILE"
  echo "New Config   : $NEW_FILE"
  echo "=========================================================================="

  # Parse unified diff (-U0 = zero context lines) so every change sits cleanly in hunks
  diff -U0 "$OLD_FILE" "$NEW_FILE" | awk '
    function flush_hunk(   i, max_pairs) {
      max_pairs = (rem_len < add_len) ? rem_len : add_len

      # Pair up equal counts of removed + added lines inside a hunk as MODIFIED
      for (i = 1; i <= max_pairs; i++) {
        mod_list[++mod_cnt] = sprintf("  ~ Line %d: \"%s\" -> \"%s\"", rem_line[i], rem_text[i], add_text[i])
      }

      # Any remaining removed lines with no paired addition are REMOVED
      for (i = max_pairs + 1; i <= rem_len; i++) {
        rem_list[++rem_cnt] = sprintf("  - Line %d: %s", rem_line[i], rem_text[i])
      }

      # Any remaining added lines with no paired removal are ADDED
      for (i = max_pairs + 1; i <= add_len; i++) {
        add_list[++add_cnt] = sprintf("  + Line %d: %s", add_line[i], add_text[i])
      }

      rem_len = 0
      add_len = 0
    }

    /^--- / || /^\+\+\+ / { next }

    /^@@ / {
      flush_hunk()
      # Parse hunk header: @@ -old_start[,old_count] +new_start[,new_count] @@
      hunk = $0
      match(hunk, /^\@\@ -([0-9]+)(,[0-9]+)? \+([0-9]+)(,[0-9]+)? \@\@/, m)
      cur_old = m[1] + 0
      cur_new = m[3] + 0
      next
    }

    /^-/ {
      line = substr($0, 2)
      rem_len++
      rem_line[rem_len] = cur_old
      rem_text[rem_len] = line
      cur_old++
      next
    }

    /^\+/ {
      line = substr($0, 2)
      add_len++
      add_line[add_len] = cur_new
      add_text[add_len] = line
      cur_new++
      next
    }

    END {
      flush_hunk()

      print ""
      print "--- ADDED LINES (" add_cnt + 0 ") ---"
      if (add_cnt == 0) {
        print "  (None)"
      } else {
        for (i = 1; i <= add_cnt; i++) print add_list[i]
      }

      print ""
      print "--- REMOVED LINES (" rem_cnt + 0 ") ---"
      if (rem_cnt == 0) {
        print "  (None)"
      } else {
        for (i = 1; i <= rem_cnt; i++) print rem_list[i]
      }

      print ""
      print "--- MODIFIED LINES (" mod_cnt + 0 ") ---"
      if (mod_cnt == 0) {
        print "  (None)"
      } else {
        for (i = 1; i <= mod_cnt; i++) print mod_list[i]
      }

      print ""
      print "=========================================================================="
      printf "Summary -> Added: %d | Removed: %d | Modified: %d\n", add_cnt + 0, rem_cnt + 0, mod_cnt + 0
      print "=========================================================================="
    }
  '
} | tee "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"
#Zero-context unified diff (diff -U0): Outputs only changed lines grouped by @@ -old_start +new_start @@ headers, keeping exact line numbers from both the old and new files without surrounding unchanged lines.

#Grouping removed + added lines into MODIFIED: When a line changes in place (for example, PORT=8080 becomes PORT=9090), diff emits a - line followed by a + line in the same hunk. Pairing matching counts as MODIFIED shows "old_value" -> "new_value" clearly, while extra - lines count as REMOVED and extra + lines count as ADDED.

#Exact line numbers: Tracks cur_old and cur_new across each hunk so every entry shows which line number changed in the old or new config file.

#Dual output with tee: Prints the full categorized report on screen and saves a timestamped copy to $REPORT_FILE.