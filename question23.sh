#Write a script that accepts a domain name, retrieves its TLS certificate
# expiry date, calculates the remaining validity period, and displays
# a warning if the certificate expires within 30 days. 
# ans) To check a domain's TLS certificate in Bash, connect to port 443 with openssl s_client, parse the notAfter expiry date using openssl x509 -enddate, convert both the expiry date and current time into Unix epoch seconds via date -d, and compute the remaining days.
#!/bin/bash

DOMAIN="${1:-${DOMAIN:-}}"
PORT="${PORT:-443}"
WARN_DAYS="${WARN_DAYS:-30}"
CONNECT_TIMEOUT="${CONNECT_TIMEOUT:-5}"

if [ -z "$DOMAIN" ]; then
  echo "Error: Domain name is required."
  echo "Usage: $0 <domain_name>"
  echo "Optional env vars: PORT (default 443), WARN_DAYS (default 30), CONNECT_TIMEOUT (default 5)"
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "Error: 'openssl' is not installed."
  exit 1
fi

# Fetch leaf certificate over TLS (-servername enables SNI for virtual-hosted domains)
cert_pem=$(
  timeout "$CONNECT_TIMEOUT" openssl s_client \
    -connect "${DOMAIN}:${PORT}" \
    -servername "$DOMAIN" \
    </dev/null 2>/dev/null |
    awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/{ if(/BEGIN CERTIFICATE/){a++}; out="/tmp/cert_"a".pem"; print >out }' &&
    cat /tmp/cert_1.pem 2>/dev/null
)
rm -f /tmp/cert_*.pem 2>/dev/null

if [ -z "$cert_pem" ]; then
  echo "Error: Could not retrieve TLS certificate from '${DOMAIN}:${PORT}'."
  exit 1
fi

enddate_raw=$(printf "%s\n" "$cert_pem" | openssl x509 -noout -enddate 2>/dev/null | cut -d'=' -f2-)
if [ -z "$enddate_raw" ]; then
  echo "Error: Failed to parse certificate expiry date for '$DOMAIN'."
  exit 1
fi

expiry_epoch=$(date -d "$enddate_raw" +%s 2>/dev/null)
now_epoch=$(date +%s)

if [ -z "$expiry_epoch" ]; then
  echo "Error: Could not convert expiry date '$enddate_raw' to timestamp."
  exit 1
fi

seconds_left=$((expiry_epoch - now_epoch))
days_left=$((seconds_left / 86400))
expiry_formatted=$(date -d "$enddate_raw" "+%Y-%m-%d %H:%M:%S %Z")

echo "Domain:          $DOMAIN:$PORT"
echo "Expiry Date:     $expiry_formatted"
echo "Remaining Days:  $days_left day(s)"

if [ "$seconds_left" -le 0 ]; then
  echo "WARNING: TLS certificate for '$DOMAIN' HAS EXPIRED!"
  exit 2
elif [ "$days_left" -le "$WARN_DAYS" ]; then
  echo "WARNING: TLS certificate for '$DOMAIN' expires within ${WARN_DAYS} days (${days_left} day(s) left)."
  exit 1
else
  echo "OK: TLS certificate is valid for more than ${WARN_DAYS} days."
  exit 0
fi
#openssl s_client -connect "${DOMAIN}:${PORT}" -servername "$DOMAIN": Opens a TLS connection to the target domain and sends the Server Name Indication (-servername) header so multi-domain servers return the right certificate.

#openssl x509 -noout -enddate: Extracts the notAfter=... expiration field from the certificate without printing the full certificate dump.

#Epoch math (date +%s and 86400): Converting both the certificate's expiry date and the current system clock to Unix seconds lets you subtract them cleanly (86400 seconds = 1 day) without manual calendar or month-length math.

#Expiry and WARN_DAYS thresholds: Flags an immediate warning if the certificate is already expired (seconds_left less than or equal to 0) or expires within 30 days (days_left less than or equal to 30), returning distinct exit codes (0 healthy, 1 warning within window, 2 expired).