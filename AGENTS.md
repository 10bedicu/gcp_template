# Project Guidelines

## Overview

This repository contains GCP infrastructure-as-code for [CARE](README.md), built with OpenTofu and Helm on Google Kubernetes Engine (GKE).

## Architecture

Modules must be applied in the following order:

| Order | Module | Purpose |
|-------|--------|---------|
| 1 | `pre-infra/` | Project bootstrap: API enablement, optional DNS zone |
| 2 | `KMS/` | Key ring, encryption keys, and application secrets (`django_secret_key`, `django_admin_password`, `metabase_encryption_secret_key` via `random_password`) |
| 3 | `infra/` | VPC, GKE, Cloud SQL, GCS buckets, Cloud Armor, GitHub WIF |
| 4 | `deploy/` | Kubernetes namespace, secrets, Helm releases |

The `infra/` module references KMS keys created by `KMS/`. The `deploy/` module reads remote state from `infra` (prefix `infra`) and `KMS` (prefix `keys`) via `terraform_remote_state` data sources in `deploy/init.tf`.

## Build and Deploy

Each module directory contains a Makefile with the following targets:

| Target | Description |
|--------|-------------|
| `make init` | Initialize OpenTofu with GCS backend |
| `make pull-tfvars` | Pull tfvars from Secret Manager (shows a diff, asks to confirm) |
| `make push-tfvars` | Push local tfvars to Secret Manager (shows a diff, asks to confirm) |
| `make plan` | Generate an execution plan |
| `make deploy` | Apply infrastructure changes |
| `make destroy` | Tear down resources |
| `make lint` | Format files recursively |

#### Tfvars Workflow

Always pull before making changes. The pull/push scripts fetch the remote secret, show a diff against your local file, and ask for confirmation before writing. The diff is hidden when `CI=true` (GitHub Actions sets this automatically) so secret values never land in CI logs.

- **Pull**: `make pull-tfvars` shows a diff (local → remote) and prompts before overwriting the local file (use `PULL_YES=true` to skip the prompt in CI).
- **Push**: `make push-tfvars` shows a diff (remote → local) and prompts before uploading a new version (use `PUSH_YES=true` to skip the prompt in CI). It refuses to push if `project_id` in the file does not match the target project.
- `plan`/`deploy`/`destroy` do NOT auto-pull. Run `make pull-tfvars` yourself first.

Typical edit flow:
```bash
make pull-tfvars          # review diff, confirm, pull latest from Secret Manager
# edit the local .tfvars file
make push-tfvars          # review diff, confirm, push
```

### Required Environment Variables

Set the following before running any target:

- `PROJECT_ID` (or `TF_VAR_project_id`)
- `ENV_NAME` (or `TF_VAR_environment` / `TF_VAR_env_name`)
- `BACKEND_BUCKET`

### State Backend Prefixes

| Module | Prefix |
|--------|--------|
| `pre-infra/` | `pre-infra` |
| `KMS/` | `keys` |
| `infra/` | `infra` |
| `deploy/` | `deploy-backend` |

> The `infra/` and `deploy/` modules run `tofu plan` with `-lock=false`. `pre-infra/` and `KMS/` use normal locking. This applies to `plan` only — `apply` and `destroy` lock in every module. The split looks unintentional rather than designed; it has been there since the initial refactor and the four Makefiles are otherwise identical.

## Configuration

All configuration is driven by tfvars files. See [environments/sample.tfvars](environments/sample.tfvars) for the complete variable shape.

- Real tfvars are stored in Secret Manager under the name `tofu-tfvars-<env>`.
- The `make pull-tfvars` target retrieves them to `../environments/<env>.tfvars`.
- Real tfvars must never be committed to the repository.

## Conventions

### Naming

Resource names follow the pattern `{org}-{app}-{environment}` with resource-specific suffixes. Any derived name can be overridden using the `coalesce(var.override, derived_default)` pattern.

### Shared Variables

The root `variables.tf` is symlinked into each module directory. Do not create separate copies. All variables, including deploy-specific ones (`helm_config`, `additional_secrets`, `additional_config_map_data`, `additional_plugs`, `enable_legacy_ingress`), are defined in this single file.

### Naming Overrides

The following optional variables override auto-derived resource names. All default to `null`:

`cluster_name`, `namespace_name`, `vpc_network_name`, `database_subnet_name`, `gke_subnet_name`, `pods_range_name`, `services_range_name`, `gateway_ip_name`, `legacy_ingress_ip_name`, `legacy_fe_ip_name`, `flow_logs_bucket`, `cloudsql_private_ip_name`, `nat_ip_address_name`, `wif_sa_name`

### Feature Flags

Boolean variables control optional infrastructure with `count` or `for_each`:

| Flag | Controls |
|------|----------|
| `enable_dicom` | DICOM stack (bucket, database, dcm4chee chart) |
| `enable_cloud_armor` | Cloud Armor security policies |
| `enable_github_wif` | GitHub Actions Workload Identity Federation |
| `enable_legacy_ingress` | Legacy GCE Ingress resources |
| `enable_dns_zone` | Cloud DNS managed zone |
| `enable_recaptcha` | Injection of reCAPTCHA keys into the CARE backend secret (the key itself is always provisioned) |

### reCAPTCHA

`infra/recaptcha.tf` provisions a `google_recaptcha_enterprise_key` for every environment.
`var.enable_recaptcha` only controls whether `GOOGLE_RECAPTCHA_SITE_KEY` and
`GOOGLE_RECAPTCHA_SECRET_KEY` are merged into `local.secret_data` in `deploy/locals.tf`, so turning
the flag off never destroys a provisioned key.

- The key's `integration_type` is hardcoded to `CHECKBOX` in `infra/recaptcha.tf`. CARE FE renders
  a v2 checkbox (`react-google-recaptcha`, `g-recaptcha-response`), so that is the only value that
  works today. When the frontend moves to v3, change it to `SCORE` there — note this **replaces
  the key and issues a new site key**.
- Allowed domains are `web_domain_name` + `api_domain_name` + `var.recaptcha_additional_domains`.
  All subdomains of a listed domain are allowed automatically. With no domains at all the key falls
  back to `allow_all_domains`, so a precondition blocks `enable_recaptcha` unless at least one
  domain is configured.
- The provider does not export a secret key. The legacy secret (used by CARE's backend against
  `https://www.google.com/recaptcha/api/siteverify`) is read with a `data "http"` call to
  `projects.keys.retrieveLegacySecretKey`, authenticated with the access token from
  `data.google_client_config`. It only runs when `enable_recaptcha` is set, and a `postcondition`
  surfaces the API error on failure.
- IAM: the principal applying `infra/` always needs reCAPTCHA key create/update permissions
  because the key is provisioned regardless of the flag, plus
  `recaptchaenterprise.keys.retrievelegacysecretkey` once `enable_recaptcha` is set.
  `roles/recaptchaenterprise.admin` covers both. The GitHub WIF deployer applies `deploy/` only and
  needs nothing extra.
- The retrieved secret is stored in `infra/` state like every other provisioned credential, so it
  is readable via `tofu show -json` and `TF_LOG` output even though the module output is marked
  sensitive. Treat state and debug artifacts as secret-bearing.
- The frontend bakes `REACT_RECAPTCHA_SITE_KEY` in at build time and cannot read the Kubernetes
  secret. Read the site key with `tofu output recaptcha_site_key` in `infra/` and set it in the FE
  build environment. The site key and secret key must come from the **same key pair** — `siteverify`
  validates the browser token against the secret — so the FE rebuild and the `infra/` apply have to
  land together, or every login submission fails validation.
- Only `GOOGLE_RECAPTCHA_SECRET_KEY` is actually read by the backend (`config/ratelimit.py`).
  `GOOGLE_RECAPTCHA_SITE_KEY` is loaded into Django settings and never referenced; it is injected
  for parity with CARE's `.env.example`.
- The captcha only triggers through the rate limiter, which counts through the Django cache backed
  by `REDIS_URL`. Without Redis, or with `DISABLE_RATELIMIT=True`, the challenge never fires.
  Conversely, when rate limiting is active but `enable_recaptcha` is off, a throttled user is locked
  out for the whole window with no solvable challenge, because `validatecaptcha` always fails
  against an empty secret.

### Provider Versions

All modules pin: `google`/`google-beta` `~> 6.33`, `random ~> 3.7`, OpenTofu `~> 1.11`.

The `infra/` module additionally requires `http ~> 3.4` (reCAPTCHA legacy secret retrieval).

The `deploy/` module additionally requires: `kubernetes ~> 2.0`, `helm ~> 2.0`, `tls ~> 4.0`, `local ~> 2.0`.

### Helm Value Injection

Helm values are defined as locals in `deploy/helm-values.tf` and passed directly to `helm_release` resources in `deploy/helm.tf` via `yamlencode()`. Chart-specific values are merged with `common_helm_values` (defined in `deploy/locals.tf`) at release time. File-based value generation under `deploy/generated_values/` is currently disabled.

Local charts: `gateway`, `redis`, `metabase`, `care_be`, `care_fe`, `dcm4chee`.

Additionally, `cert-manager` (`v1.19.4` from `https://charts.jetstack.io`) is installed as a hard dependency for TLS and Gateway API integration. The Gateway Helm release depends on cert-manager being ready.

### External TLS Certificates

Optional variables allow injecting a wildcard TLS certificate instead of relying entirely on cert-manager:

- `external_tls_cert` / `external_tls_key` — PEM-encoded cert and key (both required or both null)
- `external_tls_base_domains` — list of base domains covered by the wildcard (required when cert is provided)

When provided, cert-manager only issues certificates for domains NOT covered by the wildcard.

### Helm Config Variable Shape

`var.helm_config` is a strictly typed `object({...})`, not a `map(map(string))`. Unknown keys are
rejected and numeric/boolean attributes must be real numbers and booleans, not quoted strings.
`care_backend` and `care_frontend` are required; `metabase` and `redis` are optional and default to
pinned upstream images.

Every `*_resources` field is a complete Kubernetes resource block. Only `requests.cpu`,
`requests.memory`, `limits.cpu` and `limits.memory` are accepted. Use `limits.cpu = null` to
deliberately remove a CPU limit.

```hcl
helm_config = {
  deployment_strategy = "RollingUpdate" # or "Recreate"

  care_backend = {
    repository = "..." # required
    tag        = "..." # required
    # Everything below is optional, shown with its default.
    api_replica_count                      = 2
    api_resources                          = null
    api_autoscaling_enabled                = false
    api_autoscaling_min_replicas           = 2
    api_autoscaling_max_replicas           = 6
    api_autoscaling_target_cpu             = 80
    celery_worker_replica_count            = 1
    celery_worker_resources                = null
    celery_worker_autoscaling_enabled      = false
    celery_worker_autoscaling_min_replicas = 2
    celery_worker_autoscaling_max_replicas = 6
    celery_worker_autoscaling_target_cpu   = 80
    celery_beat_replica_count              = 1
    celery_beat_resources                  = null
  }

  care_frontend = {
    repository    = "..." # required
    tag           = "..." # required
    replica_count = 2
    resources     = null
  }

  # Optional. Omit entirely to take the defaults.
  metabase = { repository = "metabase/metabase", tag = "v0.63.13", replica_count = 1 }
  redis    = { repository = "redis", tag = "8-alpine", replica_count = 1 }
}
```

Validation blocks enforce non-negative integer replica counts, a `deployment_strategy` of
`RollingUpdate` or `Recreate`, well-formed resource quantities, and for both the API and the Celery
worker: `min_replicas >= 1`, `min_replicas <= max_replicas`, and `1 <= target_cpu <= 100`.

### Checksum-Based Pod Restarts

Pod annotations include checksums computed from secret and config data (`sha256(jsonencode(...))`). When secret or config map values change, the checksum changes, triggering a rolling restart without manual intervention.

### Helm Charts

Charts are located under `helm_charts/`. Refer to [.github/instructions/helm.instructions.md](.github/instructions/helm.instructions.md) for detailed conventions. All charts share an identical `_helpers.tpl` pattern for naming, labels, and service account helpers.

## Infrastructure Components

| Component | Description |
|-----------|-------------|
| **GKE** | Regional cluster with Gateway API, Workload Identity (`terraform-google-modules/kubernetes-engine/google` ~> 36.3) |
| **Cloud SQL** | Two PostgreSQL 17 Enterprise instances (primary + Metabase), private IP, optional read replicas |
| **GCS Buckets** | Three CMEK-encrypted buckets (patient, facility, DICOM) with HMAC access |
| **Cloud Armor** | Regional security policy with OWASP rules and geo-blocking |
| **Jumphost** | Debian 13 VM with OpenTofu pre-installed (`infra/jumphost.tf`) |
| **GitHub WIF** | Workload Identity Federation for GitHub Actions CI/CD |

## Secrets Flow

```
infra/ (DB passwords, HMAC keys, reCAPTCHA keys) ──┐
                                                    ├──→ deploy/locals.tf (secret maps) ──→ kubernetes_secret ──→ Pods
KMS/ (Django secrets, Metabase key) ────────────────┘
```

Three secret maps in `deploy/locals.tf`:
- `secret_data` — CARE backend (DB creds, GCS keys, Redis URL, Django secrets, JWKS) + `var.additional_secrets` + reCAPTCHA keys when `enable_recaptcha`
- `metabase_secret_data` — Metabase DB connection + encryption key
- `dicom_secret_data` — DICOM DB + LDAP + GCS (conditional on `enable_dicom`)

The deploy module also generates `random_password.ldap_admin_password` for the dcm4chee LDAP stack.

## Provider Authentication (deploy module)

The `deploy/` module authenticates to GKE using:
- `gke_dns_endpoint` (DNS-based control plane endpoint) from `infra` remote state
- Access token from `data.google_client_config`

Valid GCP credentials with cluster access are required.

## Pitfalls

- Module apply order is strict. Applying out of order will fail.
- Never commit real tfvars files. Store them in Secret Manager.
- Ensure correct value types in tfvars: numbers as numbers, booleans as booleans.
- The `variables.tf` files in module directories are symlinks. Edit only the root copy.
- To add new secrets, update `local.secret_data` in `deploy/locals.tf`. The `kubernetes_secret` in `deploy/secrets.tf` reads from that map automatically.
- `additional_config_map_data` injects entries into the backend ConfigMap. `additional_secrets` injects entries into the Kubernetes Secret.
- `additional_plugs` is a top-level string tfvar (JSON-encoded array) that is overwritten by the deploy pipeline from each env's `build/care/care.env` `ADDITIONAL_PLUGS` line on every run. It is injected into the backend ConfigMap as `ADDITIONAL_PLUGS`. Edit it in the deploy-states repo, not in the tfvars secret. Do not also set `ADDITIONAL_PLUGS` inside `additional_config_map_data` — that would override the top-level value. Do not nest it under `additional_config_map_data` either; `hcledit` cannot patch nested keys.
- `external_tls_cert` and `external_tls_key` must both be set or both null.
- `enable_dicom` requires `dicom_domain_name` to be non-empty.
- `service_account_email` must match `*.gserviceaccount.com`.
- Changing the hardcoded `integration_type` in `infra/recaptcha.tf` replaces the key, so the site key changes and the frontend build must be updated.
- `data.http.recaptcha_legacy_secret` only runs when `enable_recaptcha` is set. It needs `roles/recaptchaenterprise.admin` on the applying principal, and re-runs on every `infra/` plan.
- `enable_recaptcha` is read by both `infra/` and `deploy/`. Apply `infra/` first after enabling it, otherwise the `kubernetes_secret.care_backend` precondition fails because the outputs are still null.
- Existing environments must re-apply `pre-infra/` before the next `infra/` apply. The key is provisioned unconditionally, so `infra/` fails if `recaptchaenterprise.googleapis.com` has not been enabled.
