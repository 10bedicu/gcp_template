resource "google_logging_project_bucket_config" "regional" {
  count = var.enable_log_export ? 1 : 0

  project        = var.project_id
  location       = var.region
  bucket_id      = local.logging_bucket_id
  retention_days = 365
  locked         = false

  cmek_settings {
    kms_key_name = local.logs_kms_key_id
  }

  depends_on = [google_kms_crypto_key_iam_member.logging_sa_logs]
}

resource "google_logging_project_bucket_config" "default" {
  count = var.enable_log_export ? 1 : 0

  project        = var.project_id
  location       = "global"
  bucket_id      = "_Default"
  retention_days = 1
  locked         = false
}

# Disable the built-in _Default sink so no logs are routed to the global _Default bucket.
# Note: must be imported on first apply: tofu import 'google_logging_project_sink.default_sink[0]' projects/e-govt-foundation/sinks/_Default
resource "google_logging_project_sink" "default_sink" {
  count = var.enable_log_export ? 1 : 0

  name     = "_Default"
  project  = var.project_id
  disabled = true

  destination            = "logging.googleapis.com/projects/${var.project_id}/locations/global/buckets/_Default"
  unique_writer_identity = false

  lifecycle {
    ignore_changes = [destination, unique_writer_identity, filter, description, exclusions]
  }
}

# Provision the Cloud Logging CMEK service account by reading project CMEK settings.
# This call to GetCmekSettings generates the SA if it doesn't already exist.
data "google_logging_project_cmek_settings" "default" {
  count   = var.enable_log_export ? 1 : 0
  project = var.project_id
}

# Grant KMS permissions to Cloud Logging CMEK service account
resource "google_kms_crypto_key_iam_member" "logging_sa_logs" {
  count         = var.enable_log_export ? 1 : 0
  crypto_key_id = local.logs_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${data.google_logging_project_cmek_settings.default[0].service_account_id}"
}

# Sink: ALL logs → GCS bucket (long-term archive)
resource "google_logging_project_sink" "all_logs_to_gcs" {
  count = var.enable_log_export ? 1 : 0

  name                   = "all-logs-to-gcs"
  project                = var.project_id
  destination            = "storage.googleapis.com/${module.logs_bucket[0].name}"
  unique_writer_identity = true

  # Empty filter = match ALL logs
}

# Sink: ALL logs → Regional Cloud Logging bucket (live querying in India)
# The writer_identity is unused because the destination is a same-project
# logging bucket — the default Cloud Logging service agent has implicit access.
resource "google_logging_project_sink" "all_logs_to_regional" {
  count = var.enable_log_export ? 1 : 0

  name                   = "all-logs-to-regional"
  project                = var.project_id
  destination            = "logging.googleapis.com/projects/${var.project_id}/locations/${var.region}/buckets/${local.logging_bucket_id}"
  unique_writer_identity = true

  # Empty filter = match ALL logs

  depends_on = [google_logging_project_bucket_config.regional]
}

resource "google_logging_project_exclusion" "exclude_all_from_default" {
  count = var.enable_log_export ? 1 : 0

  name        = "exclude-all-from-default"
  project     = var.project_id
  description = "Exclude all logs from _Default bucket to enforce data residency in ${var.region}"

  filter = "true"
}

resource "google_project_iam_audit_config" "all_services" {
  count   = var.enable_log_export ? 1 : 0
  project = var.project_id
  service = "allServices"

  audit_log_config {
    log_type = "DATA_READ"
  }
  audit_log_config {
    log_type = "DATA_WRITE"
  }
  audit_log_config {
    log_type = "ADMIN_READ"
  }
}

# GCS sink writer → storage.objectCreator on logs bucket
resource "google_storage_bucket_iam_member" "logs_sink_writer" {
  count  = var.enable_log_export ? 1 : 0
  bucket = module.logs_bucket[0].name
  role   = "roles/storage.objectCreator"
  member = google_logging_project_sink.all_logs_to_gcs[0].writer_identity
}


