#!/usr/bin/env bash

# Export Azure and GCP VM metadata to a CSV file using the cloud CLIs.
#
# Captures: cloud, subscription/project, resource group/project, VM name, power state,
# owner tag/label, cleardata tag/label, environment tag/label.
#
# Requirements: az, gcloud, jq

set -uo pipefail

output_path="vm_inventory.csv"
declare -a azure_subscriptions=()
declare -a gcp_projects=()

usage() {
  cat <<'USAGE'
Usage: vm_inventory.sh [--azure-subscription <id-or-name>] [--gcp-project <project>] [--output <path>]

Options:
  --azure-subscription   Azure subscription ID or display name to include (repeatable). Defaults to all accessible subscriptions.
  --gcp-project          GCP project ID to include (repeatable). Defaults to none (skip GCP collection).
  --output               Output CSV path (default: vm_inventory.csv)
  -h, --help             Show this help message
USAGE
}

log_error() {
  echo "[vm-inventory] $*" >&2
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    log_error "Missing required command: $1"
    exit 1
  fi
}

append_rows() {
  local rows="$1"
  if [[ -n "$rows" ]]; then
    printf '%s\n' "$rows" >>"$output_path"
  fi
}

collect_azure() {
  local account_json subscription_lines vm_json rows count=0

  require_cmd az

  if ! account_json=$(az account list --output json 2>/dev/null); then
    log_error "Failed to list Azure subscriptions; skipping Azure collection."
    return
  fi

  if [[ ${#azure_subscriptions[@]} -eq 0 ]]; then
    mapfile -t subscription_lines < <(printf '%s' "$account_json" | jq -r '.[] | "\(.id)||\(.name // "")"')
  else
    subscription_lines=()
    for sub in "${azure_subscriptions[@]}"; do
      local resolved
      resolved=$(printf '%s' "$account_json" | jq -r --arg v "$sub" '.[] | select(.id==$v or ((.name // "") | ascii_downcase)==($v|ascii_downcase)) | "\(.id)||\(.name // "")"' | head -n 1)
      if [[ -z "$resolved" ]]; then
        log_error "Azure subscription '$sub' not found in current context; skipping."
        continue
      fi
      subscription_lines+=("$resolved")
    done
  fi

  for entry in "${subscription_lines[@]}"; do
    local sub_id="${entry%%||*}"
    local sub_name="${entry#*||}"
    if ! vm_json=$(az vm list --subscription "$sub_id" --show-details --output json 2>/dev/null); then
      log_error "Failed to list VMs for Azure subscription '$sub_id'; skipping."
      continue
    fi

    rows=$(printf '%s' "$vm_json" | jq -r --arg sub "$sub_name" '.[] | ["azure", $sub, (.resourceGroup // ""), (.name // ""), (.powerState // .provisioningState // "unknown"), (.tags.owner // ""), (.tags.cleardata // ""), (.tags.environment // "")] | @csv')
    append_rows "$rows"
    if [[ -n "$rows" ]]; then
      count=$((count + $(printf '%s' "$rows" | grep -c '^')))
    fi
  done
}

collect_gcp() {
  local vm_json rows count=0

  if [[ ${#gcp_projects[@]} -eq 0 ]]; then
    local active
    if active=$(gcloud config list --format 'value(core.project)' 2>/dev/null) && [[ -n "$active" ]]; then
      gcp_projects=("$active")
    else
      log_error "No GCP projects specified and no active gcloud project detected; skipping GCP collection."
      return
    fi
  fi

  require_cmd gcloud

  for project in "${gcp_projects[@]}"; do
    if ! vm_json=$(gcloud compute instances list --project "$project" --format=json --quiet 2>/dev/null); then
      log_error "Failed to list VMs for GCP project '$project'; skipping."
      continue
    fi

    rows=$(printf '%s' "$vm_json" | jq -r --arg project "$project" '.[] | ["gcp", $project, $project, (.name // ""), (.status // "unknown"), (.labels.owner // ""), (.labels.cleardata // ""), (.labels.environment // "")] | @csv')
    append_rows "$rows"
    if [[ -n "$rows" ]]; then
      count=$((count + $(printf '%s' "$rows" | grep -c '^')))
    fi
  done
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --azure-subscription)
        azure_subscriptions+=("$2")
        shift 2
        ;;
      --gcp-project)
        gcp_projects+=("$2")
        shift 2
        ;;
      --output)
        output_path="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        log_error "Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"
  require_cmd jq

  : >"$output_path"
  echo "cloud,subscription_or_project,resource_group_or_project,vm_name,status,owner,cleardata,environment" >"$output_path"

  collect_azure
  collect_gcp

  if [[ ! -s "$output_path" || $(wc -l <"$output_path") -le 1 ]]; then
    log_error "No VM records written."
    return 1
  fi

  echo "Wrote $(($(wc -l <"$output_path") - 1)) records to $output_path"
}

main "$@"

