module "project_services" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 18.0"

  project_id = var.project_id

  activate_apis = concat(
    [
      # --- Core (always required) ---
      "compute.googleapis.com",
      "storage.googleapis.com",
      "cloudkms.googleapis.com",
      "sqladmin.googleapis.com",
      "container.googleapis.com",
      "cloudresourcemanager.googleapis.com",
      "servicenetworking.googleapis.com",
      "serviceusage.googleapis.com",
      "iam.googleapis.com",
      "secretmanager.googleapis.com",
      "artifactregistry.googleapis.com",
      "recaptchaenterprise.googleapis.com",
    ],
    # --- Conditional ---
    var.enable_dns_zone ? [
      "dns.googleapis.com",
    ] : [],
    var.enable_github_wif ? [
      "iamcredentials.googleapis.com",
    ] : [],
    var.enable_scribe ? [
      "aiplatform.googleapis.com",
    ] : [],
  )

  enable_apis                 = true
  disable_services_on_destroy = false
}
