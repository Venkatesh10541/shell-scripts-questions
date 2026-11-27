#Write a script that identifies unattached EBS volumes, collects their
# sizes, volume types, regions, and creation dates, and estimates 
#monthly provisioned storage costs. Generate a 
#review report without deleting resources.
#ans) To find orphaned EBS storage across AWS regions without modifying or deleting anything, query aws ec2 describe-volumes --filters Name=status,Values=available per region, parse VolumeId, Size, VolumeType, and CreateTime cleanly with python3, multiply each volume's provisioned GB by its per-GB-month storage rate, and write a review report to both stdout and a report file.
#!/bin/bash

AWS_REGIONS="${AWS_REGIONS:-${1:-ap-south-1 us-east-1}}"
REPORT_FILE="${REPORT_FILE:-${2:-./unattached_ebs_report_$(date "+%Y%m%d_%H%M%S").txt}}"
ERROR_LOG="${ERROR_LOG:-./unattached_ebs_errors.log}"

# Configurable provisioned storage rates (USD per GB-month)
RATE_GP3="${RATE_GP3:-0.08}"
RATE_GP2="${RATE_GP2:-0.10}"
RATE_IO1="${RATE_IO1:-0.125}"
RATE_IO2="${RATE_IO2:-0.125}"
RATE_ST1="${RATE_ST1:-0.045}"
RATE_SC1="${RATE_SC1:-0.015}"
RATE_DEFAULT="${RATE_DEFAULT:-0.08}"

if ! command -v aws >/dev/null 2>&1; then
  echo "Error: 'aws' CLI is not installed or not in PATH." >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "Error: 'python3' is required to parse AWS volume JSON and calculate costs." >&2
  exit 1
fi

mkdir -p "$(dirname "$REPORT_FILE")"
mkdir -p "$(dirname "$ERROR_LOG")"

work_dir=$(mktemp -d)
trap 'rm -rf "$work_dir"' EXIT

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
queried_regions=0

for region in "${region_list[@]}"; do
  [ -z "$region" ] && continue

  raw_json="${work_dir}/vols_${region}.json"
  err_file="${work_dir}/err_${region}.log"

  # Read-only query: only lists available (unattached) EBS volumes; never deletes or modifies
  if ! aws ec2 describe-volumes \
    --region "$region" \
    --filters "Name=status,Values=available" \
    --output json > "$raw_json" 2>"$err_file"; then
    failed_regions=$((failed_regions + 1))
    err_msg=$(head -n 1 "$err_file" 2>/dev/null | tr '\n' ' ')
    log_err "Failed to query unattached EBS volumes in '$region': ${err_msg:-unknown AWS CLI error}"
    continue
  fi

  queried_regions=$((queried_regions + 1))
done

report_body="${work_dir}/report_body.txt"

python3 - "$work_dir" "$report_body" \
  "$RATE_GP3" "$RATE_GP2" "$RATE_IO1" "$RATE_IO2" "$RATE_ST1" "$RATE_SC1" "$RATE_DEFAULT" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

(
    work_dir,
    out_path,
    r_gp3,
    r_gp2,
    r_io1,
    r_io2,
    r_st1,
    r_sc1,
    r_def,
) = sys.argv[1:]

rates = {
    "gp3": float(r_gp3),
    "gp2": float(r_gp2),
    "io1": float(r_io1),
    "io2": float(r_io2),
    "st1": float(r_st1),
    "sc1": float(r_sc1),
}
default_rate = float(r_def)

now_utc = datetime.now(timezone.utc)
records = []
total_gb = 0
total_monthly_cost = 0.0
by_region_cost = {}

for fname in sorted(os.listdir(work_dir)):
    if not (fname.startswith("vols_") and fname.endswith(".json")):
        continue
    region = fname[5:-5]
    fpath = os.path.join(work_dir, fname)
    with open(fpath, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    for vol in data.get("Volumes", []):
        vol_id = vol.get("VolumeId", "N/A")
        size_gb = int(vol.get("Size", 0) or 0)
        vol_type = vol.get("VolumeType", "unknown")
        create_raw = vol.get("CreateTime", "")

        name_tag = ""
        for tag in vol.get("Tags") or []:
            if tag.get("Key") == "Name":
                name_tag = tag.get("Value", "")
                break

        age_days = 0
        created_display = create_raw
        if create_raw:
            try:
                norm = create_raw.replace("Z", "+00:00")
                dt = datetime.fromisoformat(norm)
                if dt.tzinfo is None:
                    dt = dt.replace(tzinfo=timezone.utc)
                age_days = max(0, (now_utc - dt).days)
                created_display = dt.astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
            except ValueError:
                created_display = create_raw

        rate = rates.get(vol_type, default_rate)
        est_cost = size_gb * rate

        total_gb += size_gb
        total_monthly_cost += est_cost
        by_region_cost[region] = by_region_cost.get(region, 0.0) + est_cost

        records.append({
            "region": region,
            "volume_id": vol_id,
            "name": name_tag or "-",
            "volume_type": vol_type,
            "size_gb": size_gb,
            "created": created_display,
            "age_days": age_days,
            "rate": rate,
            "est_cost": est_cost,
        })

# Sort highest monthly cost first for review triage
records.sort(key=lambda r: (-r["est_cost"], r["region"], r["volume_id"]))

lines = []
lines.append(
    f"{'REGION':<14}  {'VOLUME ID':<21}  {'TYPE':<6}  {'SIZE (GB)':>9}  {'AGE (D)':>7}  {'EST $/MO':>9}  {'CREATED AT (UTC)':<16}  NAME"
)
lines.append("-" * 116)

if not records:
    lines.append("(No unattached [available] EBS volumes found across queried regions.)")
else:
    for r in records:
        lines.append(
            f"{r['region']:<14}  {r['volume_id']:<21}  {r['volume_type']:<6}  "
            f"{r['size_gb']:>9}  {r['age_days']:>7}  ${r['est_cost']:>8.2f}  "
            f"{r['created']:<16}  {r['name']}"
        )

lines.append("-" * 116)
lines.append(f"Total Unattached Volumes : {len(records)}")
lines.append(f"Total Provisioned Size   : {total_gb} GB")
lines.append(f"Estimated Monthly Cost   : ${total_monthly_cost:.2f} / month (provisioned storage estimate)")

if by_region_cost:
    breakdown = ", ".join(
        f"{reg}: ${by_region_cost[reg]:.2f}/mo" for reg in sorted(by_region_cost.keys())
    )
    lines.append(f"Cost by Region           : {breakdown}")

with open(out_path, "w", encoding="utf-8") as out_fh:
    out_fh.write("\n".join(lines) + "\n")
PY

{
  echo "===================================================================================================="
  echo "UNATTACHED EBS VOLUMES REVIEW REPORT (READ-ONLY AUDIT - NO RESOURCES DELETED)"
  echo "Generated At : $(date "+%Y-%m-%d %H:%M:%S %Z")"
  echo "Regions      : ${region_list[*]}"
  echo "Rates ($/GB) : gp3=\$$RATE_GP3, gp2=\$$RATE_GP2, io1=\$$RATE_IO1, io2=\$$RATE_IO2, st1=\$$RATE_ST1, sc1=\$$RATE_SC1 (default=\$$RATE_DEFAULT)"
  echo "===================================================================================================="
  cat "$report_body"
  echo "===================================================================================================="
  echo "Regions Queried Successfully: $queried_regions | Failed Regions: $failed_regions"
  echo "===================================================================================================="
} | tee "$REPORT_FILE"

echo "Review report saved to: $REPORT_FILE"
echo "Error log path        : $ERROR_LOG"

if [ "$failed_regions" -gt 0 ]; then
  exit 1
fi
exit 0
#Strict read-only discovery: Uses only aws ec2 describe-volumes --filters "Name=status,Values=available" and contains no delete-volume or modification calls, making it safe to run in production or scheduled audits.
#Metadata and age calculation: Extracts VolumeId, Size (GB), VolumeType, CreateTime (formatted in UTC along with calculated age in days), and the Name tag if present.
#Configurable storage cost estimation: Multiplies provisioned GB by each volume type's monthly per-GB rate (gp3 at $0.08/GB, gp2 at $0.10/GB, io1/io2 at $0.125/GB, st1 at $0.045/GB, sc1 at $0.015/GB by default), and ranks volumes from highest to lowest monthly cost so reviewers see the biggest spend items first. (Note: Provisioned IOPS, throughput above baseline on gp3, or multi-AZ/snapshot charges are excluded unless factored into your custom rates.) 
 # Fault-tolerant region sweep and dual output: Logs per-region AWS CLI errors to $ERROR_LOG without aborting other regions, prints the full review report to stdout, and saves a copy to $REPORT_FILE.