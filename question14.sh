#Write a script that reads APP_ENV and APP_PORT from environment variables.
# Validate that APP_ENV is one of dev, qa, or prod, and use a default
# port if APP_PORT is not provided.
#To read environment variables cleanly in Bash, check whether APP_ENV matches one of the allowed values (dev, qa, or prod), and fall back to a default port when APP_PORT is missing or empty using parameter expansion (${APP_PORT:-...}).
#!/bin/bash

# Default port if APP_PORT is not set or empty
DEFAULT_PORT=8080

# Read from environment variables (or fall back to default port)
env_name="${APP_ENV}"
port="${APP_PORT:-$DEFAULT_PORT}"

# Validate APP_ENV against allowed values
case "$env_name" in
  dev|qa|prod)
    ;;
  *)
    echo "Error: Invalid or missing APP_ENV ('$env_name')."
    echo "Allowed values: dev, qa, prod"
    exit 1
    ;;
esac

echo "Starting app in '$env_name' environment on port '$port'..."
#${APP_PORT:-$DEFAULT_PORT}: If APP_PORT is unset or empty (""), it uses $DEFAULT_PORT (8080). If APP_PORT is already exported or passed in the command, it keeps that value.

#case "$env_name" in ... esac: Cleanly checks if APP_ENV equals dev, qa, or prod. Anything else—including an empty string when APP_ENV was not set—hits *), prints a clear error message, and exits with status 1.

#Empty body ;; on valid branch: Because nothing extra needs to happen inside the valid match before continuing, ;; ends that branch right away.