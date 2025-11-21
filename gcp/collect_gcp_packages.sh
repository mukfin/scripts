#!/usr/bin/env bash
# Collect OS inventory and installed package details for GCP VMs in a read-only manner.
# Optional environment variables:
#   GCP_PROJECTS - space separated list of project IDs to scan
#   GCP_PACKAGES_OUTPUT - output CSV path (default: ./reports/output/gcp_packages.csv)

set -euo pipefail

if [[ -n "${GCP_PROJECTS:-}" ]]; then
  read -r -a PROJECTS <<< "$GCP_PROJECTS"
else
  PROJECTS=("my-project-1" "my-project-2")
fi

OUTPUT=${GCP_PACKAGES_OUTPUT:-"./reports/output/gcp_packages.csv"}
mkdir -p "$(dirname "$OUTPUT")"

echo "cloud,project,zone,vm_name,os_long_name,os_version,package_manager,package_name,package_version" > "$OUTPUT"

for PROJECT in "${PROJECTS[@]}"; do
  echo "Processing project: $PROJECT" >&2
  INSTANCE_LIST=$(gcloud compute instances list \
    --project="$PROJECT" \
    --format="value(name,zone)" || true)

  if [[ -z "$INSTANCE_LIST" ]]; then
    echo "No instances found or unable to list instances for project $PROJECT" >&2
    continue
  fi

  while IFS=$'\t' read -r INSTANCE ZONE; do
    if [[ -z "$INSTANCE" || -z "$ZONE" ]]; then
      continue
    fi

    if ! INVENTORY_OUTPUT=$(gcloud compute os-config os-inventory describe "$INSTANCE" \
      --zone="$ZONE" \
      --project="$PROJECT" \
      --format="csv[no-heading]('$PROJECT', '$ZONE', name, osInfo.longName, osInfo.version, installedPackages.packageManager, installedPackages.packageName, installedPackages.version)" 2>/dev/null); then
      echo "Warning: Unable to retrieve OS inventory for $INSTANCE in $ZONE (project $PROJECT)" >&2
      continue
    fi

    if [[ -n "$INVENTORY_OUTPUT" ]]; then
      while IFS= read -r LINE; do
        echo "gcp,$LINE" >> "$OUTPUT"
      done <<< "$INVENTORY_OUTPUT"
    fi
  done <<< "$INSTANCE_LIST"
done
