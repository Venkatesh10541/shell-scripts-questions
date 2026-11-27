#Write a script that validates mandatory environment variables, configuration
# files, application ports, and directory permissions before deployment.
# Stop the deployment process if any mandatory validation fails. 
# ans) To build a safe pre-deployment gate in Bash, group your checks into small functions (validate_env, validate_files, validate_ports, validate_dirs), collect any failures using a state flag (validation_failed=true) so you report every problem clearly, and stop immediately (exit 1) before touching live deployment steps if anything is invalid.
#!/bin/bash

# Configurable defaults for config paths, ports, and directories
CONFIG_FILE="${CONFIG_FILE:-./config/app.env}"
SECRETS_FILE="${SECRETS_FILE:-./config/secrets.env}"
APP_PORT="${APP_PORT:-8080}"
METRICS_PORT="${METRICS_PORT:-9090}"
DEPLOY_DIR="${DEPLOY_DIR:-/opt/myapp/current}"
LOG_DIR="${LOG_DIR:-/var/log/myapp}"

validation_failed=false

log_info() {
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] [INFO]  $1"
}

log_error() {
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] [ERROR] $1" >&2
  validation_failed=true
}

# 1. Validate mandatory environment variables
validate_env() {
  local var_name val
  local required_vars=("APP_NAME" "APP_ENV" "DB_HOST" "APP_PORT")

  for var_name in "${required_vars[@]}"; do
    val="${!var_name}"
    if [ -z "$val" ]; then
      log_error "Missing mandatory environment variable: $var_name"
    fi
  done

  if [ -n "${APP_ENV:-}" ]; then
    case "$APP_ENV" in
      dev|qa|staging|prod) ;;
      *) log_error "Invalid APP_ENV '$APP_ENV' (expected dev, qa, staging, or prod)." ;;
    esac
  fi
}

# 2. Validate mandatory configuration files exist and are readable/non-empty
validate_files() {
  local cfg
  local required_files=("$CONFIG_FILE" "$SECRETS_FILE")

  for cfg in "${required_files[@]}"; do
    if [ ! -f "$cfg" ]; then
      log_error "Mandatory config file missing: $cfg"
    elif [ ! -r "$cfg" ]; then
      log_error "Mandatory config file is not readable: $cfg"
    elif [ ! -s "$cfg" ]; then
      log_error "Mandatory config file is empty: $cfg"
    fi
  done
}

# 3. Validate port numbers (1..65535) and check if already bound
is_port_in_use() {
  local port="$1"

  if command -v ss >/dev/null 2>&1; then
    ss -tlnH "sport = :$port" 2>/dev/null | grep -q .
    return $?
  elif command -v netstat >/dev/null 2>&1; then
    netstat -tln 2>/dev/null | awk '{print $4}' | grep -Eq "[:.]$port$"
    return $?
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1
    return $?
  fi

  return 1
}

validate_ports() {
  local port_label port
  local ports_to_check=("APP_PORT:$APP_PORT" "METRICS_PORT:$METRICS_PORT")

  for entry in "${ports_to_check[@]}"; do
    port_label="${entry%%:*}"
    port="${entry#*:}"

    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
      log_error "Invalid port value for $port_label: '$port' (must be 1-65535)."
      continue
    fi

    if is_port_in_use "$port"; then
      log_error "Port $port ($port_label) is already in use by another listening process."
    fi
  done
}

# 4. Validate mandatory directories and permissions
validate_dirs() {
  # DEPLOY_DIR needs read + execute (traverse); LOG_DIR needs read + write + execute
  if [ ! -d "$DEPLOY_DIR" ]; then
    log_error "Deployment directory missing: $DEPLOY_DIR"
  elif [ ! -r "$DEPLOY_DIR" ] || [ ! -x "$DEPLOY_DIR" ]; then
    log_error "Insufficient permissions on deployment directory '$DEPLOY_DIR' (need read and execute)."
  fi

  if [ ! -d "$LOG_DIR" ]; then
    log_error "Log directory missing: $LOG_DIR"
  elif [ ! -r "$LOG_DIR" ] || [ ! -w "$LOG_DIR" ] || [ ! -x "$LOG_DIR" ]; then
    log_error "Insufficient permissions on log directory '$LOG_DIR' (need read, write, and execute)."
  fi
}

log_info "Starting pre-deployment checks..."
validate_env
validate_files
validate_ports
validate_dirs

if [ "$validation_failed" = true ]; then
  log_error "Pre-deployment validation failed. Stopping deployment."
  exit 1
fi

log_info "All pre-deployment validations passed. Proceeding with deployment..."
# --- Deployment steps go here ---
#Indirect variable lookup (${!var_name}): Lets you store variable names in an array (required_vars) and read each variable's value dynamically without repeating if [ -z "$APP_NAME" ] for every single one.

#Three-step file checks (-f, -r, -s): Verifies each required configuration file exists as a regular file (-f), can be read by the current user (-r), and is not a zero-byte empty file (-s).

#Port range and listener checks: First confirms each port is digits in 1..65535, then checks active TCP listening sockets using ss (with netstat and lsof fallbacks) so you catch port conflicts before starting the app.

#Directory permission checks (-d, -r, -w, -x): Checks that directories exist and have the exact permissions needed (r read, w write for logs, and x execute/traverse to enter directories and access files inside them).

#Hard stop on failure: log_error flips validation_failed=true, and the gate check exits with status 1 before any deployment command runs.