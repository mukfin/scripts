# Multi-cloud Patch Reporting (Read-only)

Bash scripts to gather read-only patch and package information for Azure and GCP virtual machines. The scripts query existing telemetry and do **not** install updates, trigger patch jobs, or reboot VMs.

## Prerequisites
- **Azure**: VMs report update data to a Log Analytics workspace via Azure Monitor Agent / Update Manager.
- **GCP**: OS Config / VM Manager enabled in the target projects and the OS Config agent installed on VMs.
- Azure CLI (`az`) and Google Cloud CLI (`gcloud`) available in the environment.

## Outputs
Generated CSV reports are saved under `./reports/output/`:
- `azure_needed_patches.csv`: Azure VMs with missing updates from Log Analytics.
- `gcp_packages.csv`: GCP VM OS details and installed packages from OS Config inventory.

## Azure: collect_azure_patches.sh
```
cd azure
./collect_azure_patches.sh <workspace-id>
```
Environment variables:
- `AZURE_PATCH_OUTPUT` (optional): custom output path. Default: `./reports/output/azure_needed_patches.csv`.
- `AZURE_PATCH_TIMESPAN_DAYS` (optional): number of days to look back. Default: `7`.

## GCP: collect_gcp_packages.sh
```
export GCP_PROJECTS="proj1 proj2"
cd gcp
./collect_gcp_packages.sh
```
Environment variables:
- `GCP_PROJECTS` (optional): space separated list of project IDs. Defaults to sample placeholders in the script.
- `GCP_PACKAGES_OUTPUT` (optional): custom output path. Default: `./reports/output/gcp_packages.csv`.

Both scripts are read-only and rely solely on CLI queries; they never deploy patches or reboot machines.
