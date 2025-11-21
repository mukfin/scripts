#!/usr/bin/env bash
# Collect needed patch information for Azure VMs from Log Analytics in a read-only manner.
# Usage: ./collect_azure_patches.sh <workspace-id>
# Optional environment variables:
#   AZURE_PATCH_OUTPUT - output CSV path (default: ./reports/output/azure_needed_patches.csv)
#   AZURE_PATCH_TIMESPAN_DAYS - days of history to query (default: 7)

set -euo pipefail

WORKSPACE_ID=${1:-}
if [[ -z "$WORKSPACE_ID" ]]; then
  echo "Usage: $0 <log-analytics-workspace-id>" >&2
  exit 1
fi

OUTPUT=${AZURE_PATCH_OUTPUT:-"./reports/output/azure_needed_patches.csv"}
TIMESPAN_DAYS=${AZURE_PATCH_TIMESPAN_DAYS:-7}

mkdir -p "$(dirname "$OUTPUT")"

echo "cloud,vm_name,os_type,classification,kb,title,product,time_generated" > "$OUTPUT"

read -r -d '' QUERY <<'KQL'
Update
| where UpdateState == "Needed"
| project
    TimeGenerated,
    Computer,
    OSType,
    Classification,
    KB = tostring(AdditionalFields.KbId),
    Title = tostring(AdditionalFields.Title),
    Product = tostring(AdditionalFields.Product)
KQL

escape_csv() {
  local s=${1//\"/\"\"}
  printf '"%s"' "$s"
}

QUERY_OUTPUT=$(az monitor log-analytics query \
  --workspace "$WORKSPACE_ID" \
  --analytics-query "$QUERY" \
  --timespan "P${TIMESPAN_DAYS}D" \
  --query "tables[0].rows[]" \
  --output tsv || true)

if [[ -z "$QUERY_OUTPUT" ]]; then
  echo "No missing updates found for Azure in the last ${TIMESPAN_DAYS} days"
  exit 0
fi

while IFS=$'\t' read -r TimeGenerated Computer OSType Classification KB Title Product; do
  echo "$(escape_csv "azure"),$(escape_csv "$Computer"),$(escape_csv "$OSType"),$(escape_csv "$Classification"),$(escape_csv "$KB"),$(escape_csv "$Title"),$(escape_csv "$Product"),$(escape_csv "$TimeGenerated")" >> "$OUTPUT"
done <<< "$QUERY_OUTPUT"

# If the query returned rows but the loop did not append anything, the output will still contain only the header.
if [[ $(wc -l < "$OUTPUT") -le 1 ]]; then
  echo "No missing updates found for Azure in the last ${TIMESPAN_DAYS} days"
fi
