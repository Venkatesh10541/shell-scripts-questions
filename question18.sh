#Write a script that checks whether a specified application service 
# is running. If the service is inactive, generate an alert message, 
# write the incident to a log file, and notify an administrator 
# through a configurable notification method.
# ans) To monitor a service cleanly in Bash, check its state (systemctl is-active --quiet with a pgrep fallback if needed), record any outage with a timestamp to a log file, and dispatch the alert through a case statement supporting multiple notification methods (stdout, email, or webhook).
#!/bin/bash

SERVICE_NAME="${1:-${SERVICE_NAME:-}}"
NOTIFY_METHOD="${NOTIFY_METHOD:-stdout}"
LOG_FILE="${LOG_FILE:-./service_alerts.log}"
ADMIN_EMAIL="${ADMIN_EMAIL:-ops@example.com}"
WEBHOOK_URL="${WEBHOOK_URL:-}"

if [ -z "$SERVICE_NAME" ]; then
  echo "Error: Service name is required."
  echo "Usage: $0 <service_name>"
  echo "Optional env vars: NOTIFY_METHOD (stdout|email|webhook), LOG_FILE, ADMIN_EMAIL, WEBHOOK_URL"
  exit 1
fi

mkdir -p "$(dirname "$LOG_FILE")"

log_incident() {
  local message="$1"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [ALERT] $message" >> "$LOG_FILE"
}

notify_admin() {
  local subject="$1"
  local body="$2"

  case "$NOTIFY_METHOD" in
    stdout)
      echo "=== ADMIN NOTIFICATION ==="
      echo "$subject"
      echo "$body"
      echo "=========================="
      ;;
    email)
      if command -v mail >/dev/null 2>&1; then
        printf "%s\n" "$body" | mail -s "$subject" "$ADMIN_EMAIL"
      elif command -v sendmail >/dev/null 2>&1; then
        {
          printf "To: %s\nSubject: %s\n\n%s\n" "$ADMIN_EMAIL" "$subject" "$body"
        } | sendmail -t
      else
        echo "Warning: No mail/sendmail utility found; falling back to stdout."
        echo "$subject - $body"
      fi
      ;;
    webhook)
      if [ -z "$WEBHOOK_URL" ]; then
        echo "Warning: WEBHOOK_URL is not set; falling back to stdout."
        echo "$subject - $body"
      elif command -v curl >/dev/null 2>&1; then
        curl -sS -X POST -H "Content-Type: application/json" \
          -d "{\"text\":\"$subject - $body\"}" \
          "$WEBHOOK_URL" >/dev/null 2>&1 || echo "Warning: Webhook delivery failed."
      else
        echo "Warning: curl not found; falling back to stdout."
        echo "$subject - $body"
      fi
      ;;
    *)
      echo "Error: Unsupported NOTIFY_METHOD '$NOTIFY_METHOD'. Use stdout, email, or webhook."
      exit 1
      ;;
  esac
}

is_service_running() {
  local svc="$1"

  if command -v systemctl >/dev/null 2>&1; then
    systemctl is-active --quiet "$svc" >/dev/null 2>&1
    return $?
  fi

  pgrep -x "$svc" >/dev/null 2>&1
}

if is_service_running "$SERVICE_NAME"; then
  echo "OK: Service '$SERVICE_NAME' is active and running."
  exit 0
fi

host_name=$(hostname)
alert_msg="Service '$SERVICE_NAME' is INACTIVE on host '$host_name'."
alert_detail="Detected at $(date "+%Y-%m-%d %H:%M:%S"). Immediate investigation recommended."

log_incident "$alert_msg"
notify_admin "ALERT: $SERVICE_NAME down on $host_name" "$alert_detail"

exit 1
#Flexible input ($1 or SERVICE_NAME): Lets you pass the service name as a positional argument (./check_service.sh nginx) or via environment variable (SERVICE_NAME=nginx ./check_service.sh), validating that it is not empty.

#is_service_running helper: Uses systemctl is-active --quiet when systemd is available, and falls back to pgrep -x on minimal containers or non-systemd environments, returning 0 if active and non-zero if inactive.

#log_incident with >>: Appends a timestamped [ALERT] entry to $LOG_FILE so you keep a chronological record of every outage without wiping earlier incidents.

#Configurable notify_admin via case: Routes notifications based on NOTIFY_METHOD (stdout, email, or webhook), checking whether tools like mail, sendmail, or curl exist before calling them.

#Exit codes (0 vs 1): Exits 0 when the service is healthy and 1 when inactive, making it easy to run from cron or pair with your all_ok flag pattern across multiple services.