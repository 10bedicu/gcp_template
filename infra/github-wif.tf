locals {
  enable_github_wif = var.enable_github_wif

  wif_github_repo      = var.github_repo
  wif_environment_name = var.project_id
  wif_sa_name          = coalesce(var.wif_sa_name, "${var.org}-${var.environment}-${var.app}-gh-deployer")

  # ---------------------------------------------------------------------------
  # Predefined roles — minimum required to run `tofu apply` on deploy/ and
  # push container images to Artifact Registry.
  #
  # WIF/SA/IAM resources are managed here in infra/, so deploy/ SA does NOT
  # need iam.serviceAccountAdmin, workloadIdentityPoolAdmin, or projectIamAdmin.
  # Cloud Build is phased out, so cloudbuild.editor is not needed.
  # ---------------------------------------------------------------------------
  wif_sa_roles = concat(
    [
      "roles/container.admin",                    # GKE: create namespaces, manage all K8s resources + Helm
      "roles/secretmanager.secretAccessor",       # Read tofu-tfvars-<env> secrets from Secret Manager
      "roles/secretmanager.secretVersionManager", # Write new secret versions (CI image tag updates)
      "roles/storage.admin",                      # GCS state backend read/write (can scope to state bucket)
      "roles/artifactregistry.writer",            # Push/pull container images
    ],
    # Conditional: only when legacy ingress is enabled
    var.enable_legacy_ingress ? [
      "roles/compute.securityAdmin", # SSL policies + Cloud Armor
    ] : [],
  )
}

# -----------------------------------------------------------------------------
# IAM roles on the project for the service account
# -----------------------------------------------------------------------------
resource "google_project_iam_member" "github_deployer_roles" {
  for_each = local.enable_github_wif ? toset(local.wif_sa_roles) : toset([])

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.github_deployer[0].email}"
}

# -----------------------------------------------------------------------------
# Workload Identity Pool
# APIs (iam, iamcredentials) are managed in pre-infra/enable-apis.tf
# -----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool" "github" {
  count = local.enable_github_wif ? 1 : 0

  project                   = var.project_id
  workload_identity_pool_id = "github-actions"
  display_name              = "GitHub Actions"
  description               = "Workload Identity Pool for GitHub Actions OIDC"
}

# -----------------------------------------------------------------------------
# Workload Identity Provider (OIDC)
# -----------------------------------------------------------------------------
resource "google_iam_workload_identity_pool_provider" "github" {
  count = local.enable_github_wif ? 1 : 0

  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github[0].workload_identity_pool_id
  workload_identity_pool_provider_id = "github"
  display_name                       = "GitHub OIDC"
  description                        = "GitHub Actions OIDC provider for ${local.wif_github_repo}"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.environment"      = "assertion.environment"
  }

  attribute_condition = "assertion.repository == '${local.wif_github_repo}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# -----------------------------------------------------------------------------
# Service Account for GitHub Actions
# -----------------------------------------------------------------------------
resource "google_service_account" "github_deployer" {
  count = local.enable_github_wif ? 1 : 0

  project      = var.project_id
  account_id   = local.wif_sa_name
  display_name = "GitHub Actions Deployer (${local.wif_environment_name})"
  description  = "SA for GitHub Actions WIF from ${local.wif_github_repo} env:${local.wif_environment_name}"
}

# -----------------------------------------------------------------------------
# Workload Identity User binding — restricted to repo
# Uses principalSet with attribute.repository to match any workflow from the repo
# -----------------------------------------------------------------------------
resource "google_service_account_iam_member" "github_wif_binding" {
  count = local.enable_github_wif ? 1 : 0

  service_account_id = google_service_account.github_deployer[0].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github[0].name}/attribute.repository/${local.wif_github_repo}"
}
