---
applyTo: "**/*.tf"
description: "Terraform/OpenTofu conventions for this GCP infrastructure project"
---

# Terraform Conventions

## Module Structure

Modules are applied in the following order:

| Module | Purpose |
|--------|---------|
| `pre-infra/` | Bootstrap (APIs, optional DNS zone) |
| `KMS/` | Key ring and encryption keys |
| `infra/` | VPC, GKE, Cloud SQL, GCS, Cloud Armor, GitHub WIF |
| `deploy/` | Namespace, secrets, Helm releases |

Each module typically contains:

| File | Purpose |
|------|---------|
| `init.tf` | Providers, backend, remote state data sources |
| `variables.tf` | Symlink to root shared variable contract (edit root only) |
| `locals.tf` | Derived values, naming, secret composition |
| `outputs.tf` | Exported values for downstream modules |
| Resource files | Grouped by domain (`network.tf`, `cloud-sql.tf`, `helm.tf`, etc.) |

## Provider Versions

All modules pin: `google`/`google-beta` `~> 6.33`, `random ~> 3.7`, OpenTofu `~> 1.11`.

The `deploy/` module additionally requires: `kubernetes ~> 2.0`, `helm ~> 2.0`, `tls ~> 4.0`, `local ~> 2.0`.

## Configuration Pattern

- Modules consume tfvars values directly via `var.*`.
- Runtime tfvars file path: `../environments/<env>.tfvars`.
- Secret Manager naming convention: `tofu-tfvars-<env>`.
- Do not introduce `local.cfg` or JSON decode flows for configuration.

## Naming Overrides

Use the coalesce pattern for optional naming overrides:

```hcl
name = coalesce(var.cluster_name, "${var.org}-${var.app}-${var.environment}")
```

## Feature Flags

Gate resources using boolean variables with `count` or `for_each`:

```hcl
count = var.enable_dicom ? 1 : 0
```

Current flags: `enable_dicom`, `enable_cloud_armor`, `enable_github_wif`, `enable_legacy_ingress`, `enable_dns_zone`.

## Cross-Module References

The `deploy/init.tf` file reads remote state from:

| Source | Prefix | Contents |
|--------|--------|----------|
| `infra` | `infra` | Network, cluster, database, platform outputs |
| `keys` | `keys` | KMS key outputs |

Access pattern: `data.terraform_remote_state.infra.outputs.<key>`.

## State Backend

GCS backend with the following prefixes:

| Module | Prefix |
|--------|--------|
| `pre-infra/` | `pre-infra` |
| `KMS/` | `keys` |
| `infra/` | `infra` |
| `deploy/` | `deploy-backend` |

The `deploy/` module runs `tofu plan` with `-lock=false`. All other modules lock normally.

## Adding Secrets

1. Add the key-value pair to `local.secret_data` (or `local.metabase_secret_data` / `local.dicom_secret_data`) in `deploy/locals.tf`.
2. The corresponding `kubernetes_secret` in `deploy/secrets.tf` reads from that map automatically.
3. If the secret value originates from infrastructure, ensure the upstream module exports it in `outputs.tf`.

## Adding Helm Charts

1. Create a chart under `helm_charts/<name>/` following existing chart patterns.
2. Define chart-specific values as a local in `deploy/helm-values.tf`.
3. Add a `helm_release` resource in `deploy/helm.tf`, merging `common_helm_values` with chart-specific values via `yamlencode()`.
4. Image configuration comes from `var.helm_config.<chart_key>` (add to `helm_config` variable and `sample.tfvars`).

## Deploy-Specific Variables

All variables — including deploy-focused ones such as `helm_config`, `additional_secrets`, `additional_config_map_data`, `additional_plugs`, `enable_legacy_ingress`, `jwks_base64`, `namespace_name`, and resource name overrides — are defined in the root `variables.tf` (symlinked into every module). Refer to `environments/sample.tfvars` for the complete shape.

## tfvars Workflow

All modules support Makefile targets: `pull-tfvars`, `push-tfvars`, `plan`, `deploy`.

Helper scripts:
- `scripts/tfvars-pull.sh` — Pulls tfvars from Secret Manager.
- `scripts/tfvars-push.sh` — Pushes tfvars and verifies SHA256 integrity.
