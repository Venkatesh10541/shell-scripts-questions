#Write a script that calls an HTTP API using curl. If the API returns a
# temporary error or connection failure, retry the request up to five 
# times with a delay between attempts. Stop retrying immediately after success. 
#ans) To make curl reliable against flaky networks or overloaded APIs, capture both curl's exit code (connection/timeout errors) and the HTTP status code, treat 2xx responses as success, retry only on temporary failures (429 rate limit and 5xx server errors), and stop immediately as soon as a request succeeds.
#!/bin/bash

API_URL="${1:-${API_URL:-}}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-5}"
RETRY_DELAY="${RETRY_DELAY:-2}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"
MAX_TIME="${MAX_TIME:-10}"

if [ -z "$API_URL" ]; then
  echo "Error: API URL is required."
  echo "Usage: $0 <api_url>"
  echo "Optional env vars: MAX_ATTEMPTS (default 5), RETRY_DELAY (default 2), CONNECT_TIMEOUT, MAX_TIME"
  exit 1
fi

is_retryable_http_code() {
  local code="$1"

  case "$code" in
    429|500|502|503|504)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

attempt=1
response_file=$(mktemp)
trap 'rm -f "$response_file"' EXIT

while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  : > "$response_file"

  # Write HTTP status code to stdout, response body to $response_file
  http_code=$(curl -sS \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$MAX_TIME" \
    -o "$response_file" \
    -w "%{http_code}" \
    "$API_URL")
  curl_exit=$?

  # 1. Connection or curl-level failure (network drop, DNS issue, timeout)
  if [ "$curl_exit" -ne 0 ]; then
    echo "Attempt $attempt/$MAX_ATTEMPTS failed: curl error (exit code $curl_exit)."
  # 2. Successful 2xx HTTP response -> stop immediately
  elif [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
    echo "Attempt $attempt/$MAX_ATTEMPTS succeeded (HTTP $http_code)."
    cat "$response_file"
    exit 0
  # 3. Temporary/transient HTTP error -> eligible for retry
  elif is_retryable_http_code "$http_code"; then
    echo "Attempt $attempt/$MAX_ATTEMPTS received transient HTTP $http_code."
  # 4. Permanent client/other error (e.g., 400, 401, 403, 404) -> do not retry
  else
    echo "Attempt $attempt/$MAX_ATTEMPTS failed with non-retryable HTTP $http_code."
    cat "$response_file"
    exit 1
  fi

  if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
    echo "Waiting ${RETRY_DELAY}s before retry..."
    sleep "$RETRY_DELAY"
  fi

  attempt=$((attempt + 1))
done

echo "All $MAX_ATTEMPTS attempts failed for '$API_URL'." >&2
exit 1
#-o "$response_file" and -w "%{http_code}": Saves the actual API response body to a temporary file while printing just the 3-digit HTTP status code so you can inspect it in Bash. (trap 'rm -f "$response_file"' EXIT automatically cleans up the temp file when the script finishes.)

#--connect-timeout and --max-time: Prevents curl from hanging indefinitely on a stalled TCP connection or slow response before a retry happens.

#Separating transient vs. permanent failures:

#curl_exit -ne 0 catches network/connection failures (timeouts, refused connections, unreachable hosts) and retries.

#200–299 prints the response body and exits 0 right away—no extra retries.

#429 (Too Many Requests) and 500/502/503/504 (server/gateway errors) are treated as temporary and retried.

#Non-retryable client errors like 400, 401, or 404 exit immediately instead of wasting attempts.

#Bounded loop ([ "$attempt" -le "$MAX_ATTEMPTS" ]): Runs up to 5 attempts by default, sleeping $RETRY_DELAY seconds (2s) only between attempts ([ "$attempt" -lt "$MAX_ATTEMPTS" ]) so it does not sleep after the final failed try.