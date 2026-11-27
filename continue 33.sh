#Wait—let's clean up the redundant block in the script above so there isn't a duplicate python3 pass over ec2_*.json. Here is the clean, single-pass version ready to run:
#!/bin/bash

AWS_REGIONS="${AWS_REGIONS:-${1:-ap-south-1 us-east-1}}"
CSV_FILE="${CSV_FILE:-${2:-./ec2_inventory_$(date "+%Y%m%d_%H%M%S").csv}}"
ERROR_LOG="${ERROR_LOG:-./ec2_inventory_errors.log}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: 'aws' CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: 'python3' is required to write RFC-4180 compliant CSV rows." >&2
  exit 1
fi

mkdir -p "$(dirname "$CSV_FILE")"
mkdir -p "$(dirname "$ERROR_LOG")"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

log_info() {
  echo "[$(date "+%Y-%m-%d %H:%M:%S")] [INFO]  $1"
}

log_err() {
  local ts
  ts=$(date "+%Y-%m-%d %H:%M:%S")
  echo "[$ts] [ERROR] $1" | tee -a "$ERROR_LOG" >&2
}

regions_normalized=$(printf "%s" "$AWS_REGIONS" | tr ',' ' ')
read -r -a region_list <<< "$regions_normalized"

if [ "${#region_list[@]}" -eq 0 ]; then
  log_err "No AWS regions specified."
  exit 1
fi

failed_regions=0
fetched_regions=0

for region in "${region_list[@]}"; do
  [ -z "$region" ] && continue

  raw_json="${work_dir}/ec2_${region}.json"
  err_file="${work_dir}/err_${region}.log"

  if ! aws ec2 describe-instances \
    --region "$region" \
    --output json > "$raw_json" 2>"$err_file"; then
    failed_regions=$((failed_regions + 1))
    err_msg=$(head -n 1 "$err_file" 2>/dev/null | tr '\n' ' ')
    log_err "Failed to describe EC2 instances in '$region': ${err_msg:-unknown AWS CLI error}"
    continue
  fi

  fetched_regions=$((fetched_regions + 1))
  log_info "Fetched EC2 metadata from '$region'."
done

python3 - "$work_dir" "$CSV_FILE" <<'PY'
import csv
import json
import os
import sys

work_dir, csv_path = sys.argv[1], sys.argv[2]
rows = []

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

            name_val = ""
            tag_pairs = []
            for tag in inst.get("Tags") or []:
                k = tag.get("Key", "")
                v = tag.get("Value", "")
                if k == "Name":
                    name_val = v
                tag_pairs.append(f"{k}={v}")

            rows.append([
                region,
                instance_id,
                name_val,
                instance_type,
                state,
                az,
                "; ".join(tag_pairs),
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
    writer.writerows(rows)

print(f"Exported {len(rows)} EC2 instance row(s) to {csv_path}")
PY

log_info "Completed sweep across ${#region_list[@]} region(s) (succeeded: $fetched_regions, failed: $failed_regions)."

if [ "$failed_regions" -gt 0 ]; then
  exit 1
fi
exit 0
