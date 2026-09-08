# Environment Configuration

This directory contains the sanitised tfvars template for environment configuration.

## Contents

| File | Purpose |
|------|---------|
| `sample.tfvars` | Canonical template with safe placeholder values |
| `README.md` | Usage instructions and variable reference |

Do not commit real environment payloads to this directory.

## Secret Management

Real environment tfvars are stored in GCP Secret Manager and retrieved at runtime by module Makefiles.

| Item | Value |
|------|-------|
| Secret name pattern | `tofu-tfvars-<env>` |
| Pull script | `scripts/tfvars-pull.sh` |
| Push script | `scripts/tfvars-push.sh` |

## Usage

### Prerequisites

Set the following environment variables:

```bash
export BACKEND_BUCKET="<your-state-bucket>"
export PROJECT_ID="<your-gcp-project-id>"
export ENV_NAME="<environment-name>"
```

### Steps

1. Copy the sample template:

   ```bash
   cp environments/sample.tfvars environments/<env>.tfvars
   ```

2. Edit values as required.

3. Push to Secret Manager:

   ```bash
   cd pre-infra
   make push-tfvars PROJECT_ID=<gcp-project> ENV_NAME=<env>
   ```

   Override the default file path with `LOCAL_TFVARS_FILE=<path>` if needed.

4. Apply each module in order:

   ```bash
   cd pre-infra
   make init BACKEND_BUCKET=<state-bucket>
   make plan PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>

   cd ../KMS
   make init BACKEND_BUCKET=<state-bucket>
   make plan PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>

   cd ../infra
   make init BACKEND_BUCKET=<state-bucket>
   make plan PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>

   cd ../deploy
   make init BACKEND_BUCKET=<state-bucket>
   make plan PROJECT_ID=<gcp-project> ENV_NAME=<env> BACKEND_BUCKET=<state-bucket>
   ```

## Variable Reference

The source of truth for all variables is the root `variables.tf`.

### Core

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `project_id` | `string` | — | `"example-project-id"` |
| `project_number` | `string` | `null` | `"123456789012"` |
| `region` | `string` | `"us-central1"` | `"asia-south1"` |
| `org` | `string` | `"ohn"` | `"example-org"` |
| `app` | `string` | — | `"example-app"` |
| `environment` | `string` | `"prod"` | `"staging"` |

### Networking and Cluster

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `zones` | `list(string)` | `[]` | `["asia-south1-a", "asia-south1-b"]` |
| `zone` | `string` | `null` | `"asia-south1-a"` |
| `node_pools` | `any` | `[]` | List of node pool objects |
| `database_subnets` | `string` | `null` | `"10.0.21.0/24"` |
| `gke_subnets` | `string` | `null` | `"10.20.0.0/16"` |
| `gke_pods_range` | `string` | `null` | `"10.21.0.0/16"` |
| `gke_services_range` | `string` | `null` | `"10.22.0.0/20"` |
| `proxy_only_subnet_cidr` | `string` | `null` | `"10.129.0.0/23"` |
| `service_account_email` | `string` | **required** | `"iac-tofu@example.iam.gserviceaccount.com"` |
| `jumphost_ssh_keys` | `any` | `[]` | List of `{ user, key }` objects |

### DNS and Domains

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `enable_dns_zone` | `bool` | `false` | `true` |
| `dns_zone_domain` | `string` | `""` | `"example.org"` |
| `web_domain_name` | `list(string)` | `[]` | `["app.example.org"]` |
| `api_domain_name` | `list(string)` | `[]` | `["api.example.org"]` |
| `metabase_domain_name` | `list(string)` | `[]` | `["metabase.example.org"]` |
| `dicom_domain_name` | `list(string)` | `[]` | `["dicom.example.org"]` |

### Database

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `cloudsql_tier` | `string` | `null` | `"db-custom-2-3840"` |
| `cloudsql_disk_size` | `any` | `null` | `10` |
| `cloudsql_read_replica_count` | `any` | `0` | `1` |
| `cloudsql_read_replica_tier` | `string` | `null` | `"db-custom-1-3840"` |
| `metabase_cloudsql_tier` | `string` | `null` | `"db-f1-micro"` |
| `metabase_cloudsql_disk_size` | `any` | `null` | `10` |

### Feature Flags

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `enable_cloud_armor` | `bool` | `false` | `true` |
| `enable_dicom` | `bool` | `false` | `false` |
| `enable_legacy_ingress` | `bool` | `false` | `false` |
| `enable_github_wif` | `bool` | `false` | `true` |
| `github_repo` | `string` | `""` | `"example-org/example-repo"` |

### Application Configuration

| Variable | Type | Default | Example |
|----------|------|---------|---------|
| `jwks_base64` | `string` | `""` | `"CHANGE_ME_BASE64_JWKS"` |
| `helm_config` | `object` | n/a | Helm images, replicas, validated complete per-workload resource overrides, and non-DICOM deployment strategy. Set `limits.cpu = null` to remove CPU limits. |
| `additional_secrets` | `map(string)` | `{}` | Non-sensitive placeholders only |
| `additional_config_map_data` | `map(string)` | `{}` | Application config overrides |
| `additional_plugs` | `string` | `"[]"` | JSON-encoded plugin manifest; overwritten by the deploy pipeline from `build/care/care.env` on every run (edit it there, not in tfvars) |
| `snowstorm_deployment_url` | `string` | `"https://terminology.10bedicu.in/fhir"` | `"https://terminology.example.org/fhir"` |
| `metabase_encryption_secret_key_override` | `string` | `null` | `null` |

### Naming Overrides

All default to `null`, allowing auto-derived names.

| Variable | Type |
|----------|------|
| `namespace_name` | `string` |
| `cluster_name` | `string` |
| `vpc_network_name` | `string` |
| `database_subnet_name` | `string` |
| `gke_subnet_name` | `string` |
| `pods_range_name` | `string` |
| `services_range_name` | `string` |
| `gateway_ip_name` | `string` |
| `legacy_ingress_ip_name` | `string` |
| `legacy_fe_ip_name` | `string` |
| `flow_logs_bucket` | `string` |
| `cloudsql_private_ip_name` | `string` |
| `nat_ip_address_name` | `string` |
