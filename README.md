# CARE GCP Infrastructure

Infrastructure-as-code for the CARE application on Google Cloud Platform, using OpenTofu and Helm.

## Repository Layout

| Directory | Purpose |
|-----------|---------|
| `pre-infra/` | Project-level bootstrap (API enablement, optional DNS zone) |
| `KMS/` | KMS key ring and encryption keys |
| `infra/` | Core platform (VPC, GKE, Cloud SQL, GCS, Cloud Armor, GitHub WIF) |
| `deploy/` | Kubernetes namespace, secrets, Helm releases |
| `helm_charts/` | Application Helm charts (`care_be`, `care_fe`, `gateway`, `metabase`, `redis`, `dcm4chee`) |
| `environments/` | Sample tfvars template and variable documentation |
| `scripts/` | Helper scripts for tfvars synchronisation with Secret Manager |

## Deployment Order

Modules must be applied sequentially:

1. `pre-infra/`
2. `KMS/`
3. `infra/`
4. `deploy/`

The `infra/` module references KMS keys created by `KMS/`. The `deploy/` module depends on remote state outputs from both `infra/` and `KMS/`.

## Configuration

- All configuration is tfvars-based.
- Each module reads `../environments/<env>.tfvars`, pulled from Secret Manager by Makefile targets.
- Secret Manager naming convention: `tofu-tfvars-<env>`.
- The canonical template is [environments/sample.tfvars](environments/sample.tfvars).

## Required Environment Variables

Set the following before running any Makefile target:

| Variable | Description |
|----------|-------------|
| `PROJECT_ID` | GCP project ID (or `TF_VAR_project_id`) |
| `ENV_NAME` | Environment name (or `TF_VAR_environment` / `TF_VAR_env_name`) |
| `BACKEND_BUCKET` | GCS bucket for OpenTofu state |

```bash
export BACKEND_BUCKET="<your-state-bucket>"
export PROJECT_ID="<your-gcp-project-id>"
export ENV_NAME="<environment-name>"
```

## Common Commands

Run from any module directory (`pre-infra/`, `infra/`, `KMS/`, `deploy/`):

```bash
make init BACKEND_BUCKET=<state-bucket>
make pull-tfvars PROJECT_ID=<gcp-project> ENV_NAME=<env>
make plan PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>
make deploy PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>
```

To push local tfvars to Secret Manager:

```bash
make push-tfvars PROJECT_ID=<gcp-project> ENV_NAME=<env>
```

Override the default file path with `LOCAL_TFVARS_FILE=<path>` if needed.

## Workload Sizing

Node capacity, replicas, and pod resources are independent tfvars inputs. There is no separate single-node application mode: an environment becomes single-node by configuring an exact one-node pool and resources that fit that node.

Configure an exact one-node pool with pool-wide totals. GKE may temporarily create a surge node during node upgrades:

```hcl
node_pools = [
  {
    name            = "default"
    machine_type    = "e2-standard-2"
    total_min_count = 1
    total_max_count = 1
    preemptible     = false
    disk_size_gb    = 100
    node_locations  = "asia-south1-a"
  },
]
```

Set both totals to `2` for an exact two-node pool. Do not combine `total_min_count` or `total_max_count` with the per-location `min_count` or `max_count` fields.

All application replica counts and resources can be configured independently in `helm_config`. Resource overrides must provide complete `requests` and `limits` maps. Set `limits.cpu = null` to remove the chart's CPU limit while retaining a memory limit. Omit a workload's resource block to use its existing default.

Use `deployment_strategy = "Recreate"` for tightly packed single-node environments so a rollout does not require the old and replacement pods to fit simultaneously. This introduces brief workload downtime during updates. The default remains `RollingUpdate` for environments with rollout headroom.

Replica counts accept non-negative integers. Increasing a replica count also multiplies that workload's requests; verify the new total against node allocatable capacity before applying. These controls do not configure DICOM workloads.

## Security

- Do not commit real environment tfvars to the repository.
- Only sanitised samples should be checked in.
- All real configuration must reside in Secret Manager.
