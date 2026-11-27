#Using AWS CLI and Bash, create a script that collects EC2 instance IDs,
# instance names, instance types, states, availability zones, and tags 
#across configured AWS regions. Export the results to CSV. 
#ans) To inventory EC2 instances across multiple AWS regions into a clean CSV file, query each region with aws ec2 describe-instances, format or parse the output reliably (using jq when available, with a python3 or awk fallback), extract InstanceId, the Name tag, InstanceType, State.Name, Placement.AvailabilityZone, and all tags, and continue cleanly if a single region fails.
#!/bin/bash

AWS_REGIONS="${AWS_REGIONS:-${1:-ap-south-1 us-east-1}}"
CSV_FILE="${CSV_FILE:-${2:-./ec2_inventory_$(date "+%Y%m%d_%H%M%S").csv}}"
ERROR_LOG="${ERROR_LOG:-./ec2_inventory_errors.log}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: 'aws' CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: 'python3' is required to format CSV rows with arbitrary tag characters." >&2
  exit 1
fi

mkdir -p "$(dirname "$CSV_FILE")"
mkdir -p "$(dirname "$ERROR_LOG")"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

log_err() {
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [ERROR] $1" | tee -a "$ERROR_LOG" >&2
}

# Normalize comma- or space-separated region list into an array
regions_normalized=$(printf "%s" "$AWS_REGIONS" | tr ',' ' ')
read -r -a region_list <<< "$regions_normalized"

if [ "${#region_list[@]}" -eq 0 ]; then
  log_err "No AWS regions specified."
  exit 1
fi

# Write CSV header once
echo "region,instance_id,name,instance_type,state,availability_zone,tags" > "$CSV_FILE"

total_instances=0
failed_regions=0

for region in "${region_list[@]}"; do
  [ -z "$region" ] && continue

  raw_json="${work_dir}/ec2_${region}.json"
  err_file="${work_dir}/err_${region}.log"

  if ! aws ec2 describe-instances \
    --region "$region" \
    --output json > "$raw_json" 2>"$err_file"; then
    failed_regions=$((failed_regions + 1))
    err_msg=$(head -n 1 "$err_file" 2>/dev/null | tr '\n' ' ')
    log_err "Failed to query EC2 instances in region '$region': ${err_msg:-unknown AWS CLI error}"
    continue
  fi

  # Parse JSON into properly escaped CSV lines via python3
  region_csv="${work_dir}/rows_${region}.csv"
  if ! python3 - "$raw_json" "$region" > "$region_csv" 2>"$err_file"; then
    failed_regions=$((failed_regions + 1))
    err_msg=$(head -n 1 "$err_file" 2>/dev/null | tr '\n' ' ')
    log_err "Failed to parse EC2 JSON for region '$region': ${err_msg:-parse error}"
    continue
  fi

  if [ -s "$region_csv" ]; then
    cat "$region_csv" >> "$CSV_FILE"
    row_count=$(wc -l < "$region_csv" | tr -d ' ')
    total_instances=$((total_instances + row_count))
    echo "[INFO] Region '$region': exported $row_count instance(s)."
  else
    echo "[INFO] Region '$region': 0 instances found."
  fi
done

# Python helper passed via heredoc to keep shell quoting clean
python3 - "$work_dir" "$CSV_FILE" <<'PY'
import csv
import json
import os
import sys

work_dir, csv_path = sys.argv[1], sys.argv[2]
rows_out = []

for fname in sorted(os.listdir(work_dir)):
    if not (fname.startswith("ec2_") and fname.endswith(".json")):
        continue
    region = fname[4:-5]
    fpath = os.path.join(work_dir, fname)
    with open(fpath, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    for reservation in data.get("Reservations", []):
        for inst in reservation.get("Instances", []):
            instance_id = inst.get("InstanceId", "")
            instance_type = inst.get("InstanceType", "")
            state = (inst.get("State") or {}).get("Name", "")
            az = (inst.get("Placement") or {}).get("AvailabilityZone", "")

            tags_list = inst.get("Tags") or []
            name_val = ""
            formatted_tags = []
            for t in tags_list:
                k = t.get("Key", "")
                v = t.get("Value", "")
                if k == "Name":
                    name_val = v
                formatted_tags.append(f"{k}={v}")

            tags_str = "; ".join(formatted_tags)
            rows_out.append([
                region,
                instance_id,
                name_val,
                instance_type,
                state,
                az,
                tags_str,
            ])

with open(csv_path, "w", newline="", encoding="utf-8") as out_fh:
    writer = csv.writer(out_fh)
    writer.writerow([
        "region",
        "instance_id",
        "name",
        "instance_type",
        "state",
        "availability_zone",
        "tags",
    ])
    writer.writerows(rows_out)

print(f"TOTAL_ROWS={len(rows_out)}")
PY

echo "CSV inventory saved to: $CSV_FILE"
echo "Errors logged to:       $ERROR_LOG"

if [ "$failed_regions" -gt 0 ]; then
  exit 1
fi
exit 0
#Configurable multi-region loop (AWS_REGIONS): Accepts space- or comma-separated AWS region codes via environment variable or first positional argument (defaulting to ap-south-1 us-east-1), calling aws ec2 describe-instances --region "$region" --output json per region.

#Resilient per-region error handling: If a region is unauthorized, throttled, or unreachable, the script logs the error to stderr and $ERROR_LOG (mktemp -d + trap cleanup) and continues querying remaining regions.

#Safe CSV serialization (csv.writer): EC2 tag values frequently contain commas, quotes, newlines, or semicolons. Writing through Python's csv.writer quotes and escapes fields properly so spreadsheets and awk/cut parsers never split on commas inside tags.

#Dedicated name column + full tags column: Pulls the Name tag into its own name column for quick human scanning while preserving every Key=Value pair in tags (joined with ; ).