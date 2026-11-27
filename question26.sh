#Develop a menu-driven script using case statements that allows an 
#authorized user to check, start, stop, or restart an approved test 
#service. Validate user input and display operation results. 
# ans) To build a safe menu-driven service helper in Bash, lock down the target to an approved test service allowlist, verify that the caller is an authorized user (ALLOWED_USERS / id -un), validate every menu choice inside a case statement, and log or print clear operation results.
#!/bin/bash

# Configurable allowlist and authorization settings
ALLOWED_SERVICE="${ALLOWED_SERVICE:-nginx}"
ALLOWED_USERS="${ALLOWED_USERS:-$(id -un)}"
LOG_FILE="${LOG_FILE:-./test_service_actions.log}"

mkdir -p "$(dirname "$LOG_FILE")"

log_action() {
  local status="$1"
  local msg="$2"
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [$status] user=$(id -un) service=$ALLOWED_SERVICE - $msg" >> "$LOG_FILE"
}

is_authorized_user() {
  local current_user
  current_user=$(id -un)

  # Allow root if explicitly permitted or if listed in ALLOWED_USERS
  for u in $ALLOWED_USERS; do
    if [ "$current_user" = "$u" ]; then
      return 0
    fi
  done

  return 1
}

run_systemctl() {
  local action="$1"

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "Error: 'systemctl' is not available on this system."
    log_action "ERROR" "systemctl missing during '$action'"
    return 1
  fi

  # Use sudo only when not already running as root
  if [ "$(id -u)" -eq 0 ]; then
    systemctl "$action" "$ALLOWED_SERVICE"
  elif command -v sudo >/dev/null 2>&1; then
    sudo -n systemctl "$action" "$ALLOWED_SERVICE"
  else
    systemctl "$action" "$ALLOWED_SERVICE"
  fi
}

check_status() {
  echo "Checking status for approved test service '$ALLOWED_SERVICE'..."
  if run_systemctl "is-active" >/dev/null 2>&1; then
    echo "Result: Service '$ALLOWED_SERVICE' is ACTIVE (running)."
    log_action "INFO" "status check: ACTIVE"
    return 0
  else
    echo "Result: Service '$ALLOWED_SERVICE' is INACTIVE (stopped)."
    log_action "WARNING" "status check: INACTIVE"
    return 1
  fi
}

perform_action() {
  local action="$1"

  echo "Executing '$action' on '$ALLOWED_SERVICE'..."
  if run_systemctl "$action" >/dev/null 2>&1; then
    echo "Success: '$action' completed for '$ALLOWED_SERVICE'."
    log_action "SUCCESS" "$action succeeded"
    return 0
  else
    echo "Failure: '$action' failed for '$ALLOWED_SERVICE' (check permissions or service unit)."
    log_action "ERROR" "$action failed"
    return 1
  fi
}

show_menu() {
  echo ""
  echo "=========================================="
  echo " Approved Test Service Control: $ALLOWED_SERVICE"
  echo " Current User: $(id -un)"
  echo "=========================================="
  echo "  1) Check service status"
  echo "  2) Start service"
  echo "  3) Stop service"
  echo "  4) Restart service"
  echo "  5) Exit"
  echo "------------------------------------------"
}

# 1. Verify user authorization before showing actions
if ! is_authorized_user; then
  echo "Access Denied: User '$(id -un)' is not authorized to manage '$ALLOWED_SERVICE'." >&2
  echo "Authorized users: $ALLOWED_USERS" >&2
  log_action "DENIED" "unauthorized access attempt"
  exit 1
fi

# 2. Interactive menu loop with strict input validation via case
while true; do
  show_menu
  read -r -p "Enter your choice [1-5]: " choice

  # Trim accidental leading/trailing whitespace
  choice=$(echo "$choice" | awk '{$1=$1; print}')

  case "$choice" in
    1)
      check_status || true
      ;;
    2)
      perform_action "start" || true
      ;;
    3)
      perform_action "stop" || true
      ;;
    4)
      perform_action "restart" || true
      ;;
    5)
      echo "Exiting service controller."
      log_action "INFO" "exited menu"
      exit 0
      ;;
    "")
      echo "Invalid input: Choice cannot be empty. Please enter a number from 1 to 5."
      ;;
    *)
      echo "Invalid input: '$choice' is not a valid option. Please enter 1, 2, 3, 4, or 5."
      ;;
  esac
done
#Authorized user check (is_authorized_user): Compares id -un against ALLOWED_USERS (which defaults to the current user so you can test immediately, and can be locked down to specific usernames like ALLOWED_USERS="devuser qauser"). Unauthorized users are blocked immediately and logged.

#Pinned test service (ALLOWED_SERVICE): Hardcodes the target unit name in one variable rather than accepting arbitrary service names from the user, reducing accidental impact on unrelated system services.

#Input validation inside case: Handles empty input ("") and any unexpected keystrokes or words (*)) with clear instructions instead of crashing or running unintended commands.

#Operation feedback and audit trail: Each menu choice reports whether the check or start/stop/restart command succeeded or failed, and appends a timestamped record to $LOG_FILE.