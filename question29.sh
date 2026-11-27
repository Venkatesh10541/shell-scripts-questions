#Write a script that reads multiple application URLs from a file, 
#checks HTTP response codes and response times, and 
#identifies unavailable or slow endpoints. 
#ans) To check multiple endpoints from a text file in Bash, use curl -w to capture both the HTTP status code and total response time in seconds, convert the timing into milliseconds with awk so integer comparisons work cleanly in Bash, and classify each URL as OK, SLOW, or UNAVAILABLE against configurable thresholds.
#!/bin/bash

URL_FILE="${1:-${URL_FILE:-./urls.txt}}"
SLOW_MS="${SLOW_MS:-1500}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-10}"
REPORT_FILE="${REPORT_FILE:-./endpoint_check_report_$(date "+%Y%m%d_%H%M%S").txt}"

if [ ! -f "$URL_FILE" ] || [ ! -r "$URL_FILE" ]; then
  echo "Error: URL file '$URL_FILE' is missing or not readable." >&2
  echo "Usage: $0 [urls_file]" >&2
  echo "Optional env vars: SLOW_MS (default 1500), CONNECT_TIMEOUT (default 5), MAX_TIME (default 10), REPORT_FILE" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Error: 'curl' is not installed." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"

unhealthy_count=0

{
  echo "=========================================================================================="
  echo "APPLICATION ENDPOINT HEALTH & LATENCY REPORT"
  echo "Generated on   : $(date "+%Y-%m-%d %H:%M:%S")"
  echo "URL List       : $URL_FILE"
  echo "Slow Threshold : ${SLOW_MS} ms | Max Time: ${MAX_TIME}s"
  echo "=========================================================================================="
  printf "%-12s  %-8s  %-11s  %s\n" "STATUS" "HTTP" "TIME (ms)" "URL"
  echo "------------------------------------------------------------------------------------------"

  while IFS= read -r url || [ -n "$url" ]; do
    # Trim whitespace and skip blank lines or comments
    url=$(echo "$url" | awk '{$1=$1; print}')
    if [ -z "$url" ] || [[ "$url" == \#* ]]; then
      continue
    fi

    # Format: "<http_code> <time_total_seconds>"
    probe_out=$(curl -sS -L \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -o /dev/null \
      -w "%{http_code} %{time_total}" \
      "$url")
    curl_exit=$?

    http_code=$(echo "$probe_out" | awk '{print $1}')
    time_sec=$(echo "$probe_out" | awk '{print $2}')

    # Convert seconds (float) to milliseconds (integer)
    time_ms=$(awk -v t="${time_sec:-0}" 'BEGIN {
      if (t ~ /^[0-9]+(\.[0-9]+)?$/) {
        printf "%d", (t * 1000) + 0.5
      } else {
        print 0
      }
    }')

    # Determine availability and latency status
    if [ "$curl_exit" -ne 0 ] || ! [[ "$http_code" =~ ^[0-9]+$ ]] || [ "$http_code" -eq 0 ] || [ "$http_code" -ge 500 ]; then
      status="UNAVAILABLE"
      unhealthy_count=$((unhealthy_count + 1))
    elif [ "$http_code" -ge 400 ]; then
      status="UNAVAILABLE"
      unhealthy_count=$((unhealthy_count + 1))
    elif [ "$time_ms" -ge "$SLOW_MS" ]; then
      status="SLOW"
      unhealthy_count=$((unhealthy_count + 1))
    else
      status="OK"
    fi

    display_code="${http_code:-ERR}"
    [ "$display_code" = "000" ] && display_code="ERR"

    printf "%-12s  %-8s  %-11s  %s\n" "$status" "$display_code" "${time_ms} ms" "$url"
  done < "$URL_FILE"

  echo "------------------------------------------------------------------------------------------"
  echo "Flagged endpoints (SLOW or UNAVAILABLE): $unhealthy_count"
  echo "=========================================================================================="
} | tee "$REPORT_FILE"

echo "Report saved to: $REPORT_FILE"

if [ "$unhealthy_count" -gt 0 ]; then
  exit 1
fi
exit 0
#Single-pass timing and status (-o /dev/null -w "%{http_code} %{time_total}"): Discards the response body while capturing the HTTP status code and total transfer duration in seconds from curl.

#Seconds-to-milliseconds conversion in awk: Turns floating-point seconds (such as 0.428) into rounded integer milliseconds (428) so [ "$time_ms" -ge "$SLOW_MS" ] works cleanly in Bash.

#Clear classification rules:

#UNAVAILABLE: curl failed (connection refused, DNS error, timeout), returned status 000, or returned 4xx/5xx HTTP status codes.

#SLOW: Responded with a healthy status code, but time_ms met or exceeded SLOW_MS (default 1500 ms).

#OK: Responded cleanly within the latency limit.

#Dual output and exit status: Prints the summary table to stdout, saves a timestamped report to $REPORT_FILE, and exits with 1 if any slow or unavailable endpoint is detected.