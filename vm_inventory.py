"""
Collect VM metadata from Azure and Google Cloud using the CLI tools, then write a CSV report.

The report includes:
- Cloud environment (azure or gcp)
- Subscription name or project ID
- Resource group (Azure) or project name (GCP)
- VM name
- Power state / status
- owner tag/label
- cleardata tag/label
- environment tag/label

Authentication:
- Azure: relies on the Azure CLI context (e.g. `az login`).
- GCP: relies on the gcloud CLI context (e.g. `gcloud auth login`).

Usage examples:
- python vm_inventory.py --output vm_report.csv
- python vm_inventory.py --azure-subscription <subscription-id> --gcp-project <project-id>
"""
from __future__ import annotations

import argparse
import csv
import json
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, List, Optional, Sequence

@dataclass
class VmRecord:
    cloud: str
    subscription_or_project: str
    resource_group_or_project: str
    name: str
    status: str
    owner: str | None
    cleardata: str | None
    environment: str | None

    def to_row(self) -> List[str]:
        return [
            self.cloud,
            self.subscription_or_project,
            self.resource_group_or_project,
            self.name,
            self.status,
            self.owner or "",
            self.cleardata or "",
            self.environment or "",
        ]


CSV_HEADERS = [
    "cloud",
    "subscription_or_project",
    "resource_group_or_project",
    "vm_name",
    "status",
    "owner",
    "cleardata",
    "environment",
]


def run_json_command(command: Sequence[str]) -> list | dict:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        raise RuntimeError(
            f"Command failed ({completed.returncode}): {' '.join(command)}\n{completed.stderr.strip()}"
        )
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError as exc:
        raise RuntimeError(
            f"Failed to parse JSON output from: {' '.join(command)}\n{completed.stdout.strip()}"
        ) from exc


def fetch_azure_subscriptions() -> dict[str, str]:
    accounts = run_json_command(["az", "account", "list", "--output", "json"])
    return {account["id"]: account.get("name", account["id"]) for account in accounts}


def resolve_requested_subscriptions(
    requested: Optional[Sequence[str]],
    all_subscriptions: dict[str, str],
) -> Iterable[tuple[str, str]]:
    if not requested:
        return all_subscriptions.items()

    id_by_name = {name.lower(): sub_id for sub_id, name in all_subscriptions.items()}
    resolved = {}
    for value in requested:
        value_lower = value.lower()
        if value in all_subscriptions:
            resolved[value] = all_subscriptions[value]
        elif value_lower in id_by_name:
            sub_id = id_by_name[value_lower]
            resolved[sub_id] = all_subscriptions[sub_id]
        else:
            raise ValueError(f"Azure subscription '{value}' is not available in the current context")
    return resolved.items()


def fetch_azure_vms(subscription_filters: Optional[Sequence[str]]) -> List[VmRecord]:
    subscriptions = fetch_azure_subscriptions()
    records: List[VmRecord] = []
    for subscription_id, subscription_name in resolve_requested_subscriptions(subscription_filters, subscriptions):
        vm_list = run_json_command(
            [
                "az",
                "vm",
                "list",
                "--subscription",
                subscription_id,
                "--show-details",
                "--output",
                "json",
            ]
        )
        for vm in vm_list:
            tags = vm.get("tags", {}) or {}
            records.append(
                VmRecord(
                    cloud="azure",
                    subscription_or_project=subscription_name or subscription_id,
                    resource_group_or_project=vm.get("resourceGroup", ""),
                    name=vm.get("name", ""),
                    status=vm.get("powerState") or vm.get("provisioningState", "unknown"),
                    owner=tags.get("owner"),
                    cleardata=tags.get("cleardata"),
                    environment=tags.get("environment"),
                )
            )
    return records


def fetch_gcp_vms(projects: Sequence[str]) -> List[VmRecord]:
    if not projects:
        return []

    records: List[VmRecord] = []
    for project in projects:
        vm_list = run_json_command(
            ["gcloud", "compute", "instances", "list", "--project", project, "--format", "json"]
        )
        for instance in vm_list:
            labels = instance.get("labels", {}) or {}
            records.append(
                VmRecord(
                    cloud="gcp",
                    subscription_or_project=project,
                    resource_group_or_project=project,
                    name=instance.get("name", ""),
                    status=instance.get("status", "unknown"),
                    owner=labels.get("owner"),
                    cleardata=labels.get("cleardata"),
                    environment=labels.get("environment"),
                )
            )
    return records


def write_csv(path: str, records: Iterable[VmRecord]) -> None:
    with open(path, "w", newline="", encoding="utf-8") as csv_file:
        writer = csv.writer(csv_file)
        writer.writerow(CSV_HEADERS)
        for record in records:
            writer.writerow(record.to_row())


def parse_args(argv: Optional[Sequence[str]] = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Export Azure and GCP VM metadata to CSV.")
    parser.add_argument(
        "--azure-subscription",
        action="append",
        help="Azure subscription ID or display name to include (repeatable). Defaults to all accessible subscriptions.",
    )
    parser.add_argument(
        "--gcp-project",
        action="append",
        help="GCP project ID to include (repeatable).",
    )
    parser.add_argument(
        "--output",
        default="vm_inventory.csv",
        help="Output CSV path (default: vm_inventory.csv)",
    )
    return parser.parse_args(argv)


def main(argv: Optional[Sequence[str]] = None) -> int:
    args = parse_args(argv)
    records: List[VmRecord] = []
    try:
        records.extend(fetch_azure_vms(args.azure_subscription))
    except Exception as exc:  # noqa: BLE001 - Surface authentication and API issues
        print(f"Failed to retrieve Azure VMs: {exc}", file=sys.stderr)

    try:
        records.extend(fetch_gcp_vms(args.gcp_project or []))
    except Exception as exc:  # noqa: BLE001 - Surface authentication and API issues
        print(f"Failed to retrieve GCP VMs: {exc}", file=sys.stderr)

    if not records:
        print("No VMs found or all queries failed; no CSV written.", file=sys.stderr)
        return 1

    write_csv(args.output, records)
    print(f"Wrote {len(records)} records to {args.output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
