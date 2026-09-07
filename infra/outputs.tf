# --- GKE Outputs ---

output "gke_dns_endpoint" {
  description = "The DNS-based endpoint of the GKE cluster"
  value       = module.gke_cluster.endpoint_dns
}

# --- Cloud SQL Outputs ---

output "instance_address" {
  description = "IP address of the primary instance"
  value       = module.cloudsql.private_ip_address
}

output "primary_connection_string" {
  description = "Connection string for the primary instance"
  value       = "postgresql://${var.app}_${var.environment}_user:${random_password.database_master.result}@${module.cloudsql.private_ip_address}:5432/${var.app}_${var.environment}"
  sensitive   = true
}

output "database_name" {
  description = "Name of the database created in the Cloud SQL instance"
  value       = "${var.app}_${var.environment}"
}

output "database_user" {
  description = "Username for the database"
  value       = "${var.app}_${var.environment}_user"
}

output "database_password" {
  description = "Password for the database user"
  value       = random_password.database_master.result
  sensitive   = true
}

# Metabase database

output "metabase_instance_address" {
  description = "IP address of the metabase instance"
  value       = module.metabase_cloudsql.private_ip_address
}

output "metabase_database_name" {
  description = "Name of the database created in the Metabase Cloud SQL instance"
  value       = "metabase_${var.environment}"
}

output "metabase_database_user" {
  description = "Username for the metabase database"
  value       = "metabase_${var.environment}_user"
}

output "metabase_database_password" {
  description = "Password for the metabase database user"
  value       = random_password.metabase_database_master.result
  sensitive   = true
}

# DICOM database

output "dicom_connection_string" {
  description = "Connection string for the DICOM database"
  value       = "postgresql://dicom_${var.environment}_user:${random_password.dicom_database_password.result}@${module.cloudsql.private_ip_address}:5432/dicom_${var.environment}"
  sensitive   = true
}

output "dicom_database_name" {
  description = "Name of the DICOM database"
  value       = "dicom_${var.environment}"
}

output "dicom_database_user" {
  description = "Username for the DICOM database"
  value       = "dicom_${var.environment}_user"
}

output "dicom_database_password" {
  description = "Password for the DICOM database user"
  value       = random_password.dicom_database_password.result
  sensitive   = true
}

# --- GCS Outputs ---

output "writer_service_account_email" {
  description = "The email of the service account used for bucket operations"
  value       = local.writer_sa_email
}

output "patient_bucket_name" {
  description = "The name of the patient bucket"
  value       = module.patient_bucket.name
}

output "facility_bucket_name" {
  description = "The name of the facility bucket"
  value       = module.facility_bucket.name
}

output "dicom_bucket_name" {
  description = "The name of the DICOM bucket"
  value       = module.dicom_bucket.name
}

output "gcs_access_key" {
  description = "The HMAC access ID for the writer service account"
  value       = google_storage_hmac_key.writer_sa_hmac.access_id
  sensitive   = true
}

output "gcs_secret_key" {
  description = "The HMAC secret for the writer service account"
  value       = google_storage_hmac_key.writer_sa_hmac.secret
  sensitive   = true
}

# --- Network Outputs ---

output "gateway_ip_name" {
  description = "Regional IP name for Gateway API"
  value       = google_compute_address.gateway_ip.name
}

# --- Cloud Armor Outputs ---

output "security_policy_name" {
  description = "The name of the Cloud Armor security policy"
  value       = try(google_compute_region_security_policy.care[0].name, "")
}

output "ssl_policy_name" {
  description = "The name of the regional SSL policy"
  value       = try(google_compute_region_ssl_policy.care_ssl_policy[0].name, "")
}

# --- GitHub WIF Outputs ---

output "github_deployer_sa_email" {
  description = "Email of the GitHub Actions deployer service account"
  value       = try(google_service_account.github_deployer[0].email, "")
}

output "github_wif_provider_name" {
  description = "Full resource name of the GitHub WIF provider (for GitHub Actions auth)"
  value       = try(google_iam_workload_identity_pool_provider.github[0].name, "")
}

# --- Scribe Outputs ---

output "scribe_sa_key_b64" {
  description = "Base64-encoded service account JSON key for Scribe (only has aiplatform.user)"
  value       = try(google_service_account_key.scribe[0].private_key, "")
  sensitive   = true
}

# --- reCAPTCHA Outputs ---

output "recaptcha_site_key" {
  description = "reCAPTCHA site key (public, safe to embed in the frontend build)"
  value       = google_recaptcha_enterprise_key.care.name
}

output "recaptcha_secret_key" {
  description = "Legacy reCAPTCHA secret key used with https://www.google.com/recaptcha/api/siteverify. Null unless enable_recaptcha is set."
  value       = var.enable_recaptcha ? jsondecode(data.http.recaptcha_legacy_secret[0].response_body).legacySecretKey : null
  sensitive   = true
}
