module "service_accounts" {
  source       = "terraform-google-modules/service-accounts/google"
  version      = "~> 4.5.3"
  project_id   = var.project_id
  names        = ["${var.org}-${var.environment}-${var.app}-writer"]
  display_name = "Bucket Writer Service Account"
  descriptions = ["Service Account for writing to buckets"]
}

resource "google_kms_crypto_key_iam_member" "writer_sa_patient" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/patient-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.writer_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "writer_sa_facility" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/facility-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.writer_sa_email}"
}

# Grant Storage service account permission to use the KMS keys
resource "google_kms_crypto_key_iam_member" "storage_sa_patient" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/patient-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

resource "google_kms_crypto_key_iam_member" "storage_sa_facility" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/facility-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}



# Generate HMAC key for the service account
resource "google_storage_hmac_key" "writer_sa_hmac" {
  service_account_email = local.writer_sa_email
  project               = var.project_id
}

# DICOM Bucket KMS permissions
resource "google_kms_crypto_key_iam_member" "writer_sa_dicom" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/dicom-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:${local.writer_sa_email}"
}

resource "google_kms_crypto_key_iam_member" "storage_sa_dicom" {
  crypto_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/dicom-key"
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}

# DICOM Bucket for storing DICOM files
module "dicom_bucket" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 10.0"
  project_id = var.project_id
  location   = var.region
  names      = [local.dicom_bucket_name]

  depends_on = [
    google_kms_crypto_key_iam_member.storage_sa_dicom,
    google_kms_crypto_key_iam_member.writer_sa_dicom,
  ]
  labels = merge(
    local.tags,
    {
      billing = "dicom-bucket"
    }
  )
  bucket_policy_only = {
    (local.dicom_bucket_name) = true
  }
  force_destroy = {
    (local.dicom_bucket_name) = false
  }
  cors = [
    {
      origin          = local.cors_origins
      method          = ["GET", "PUT", "POST", "DELETE"]
      response_header = ["*"]
      max_age_seconds = 3000
    }
  ]
  encryption_key_names = {
    (local.dicom_bucket_name) = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/dicom-key"
  }
}

resource "google_storage_bucket_iam_member" "dicom_bucket_admin" {
  bucket = module.dicom_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${local.writer_sa_email}"
}

module "patient_bucket" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 10.0"
  project_id = var.project_id
  location   = var.region
  names      = [local.patient_bucket_name]

  depends_on = [
    google_kms_crypto_key_iam_member.storage_sa_patient,
    google_kms_crypto_key_iam_member.writer_sa_patient,
  ]
  labels = merge(
    local.tags,
    {
      billing = "patient-bucket"
    }
  )


  bucket_policy_only = {
    (local.patient_bucket_name) = true
  }
  force_destroy = {
    (local.patient_bucket_name) = false
  }
  cors = [
    {
      origin          = local.cors_origins
      method          = ["GET", "PUT", "POST"]
      response_header = ["*"]
      max_age_seconds = 3000
    }
  ]
  encryption_key_names = {
    (local.patient_bucket_name) = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/patient-key"
  }
}

module "facility_bucket" {
  source     = "terraform-google-modules/cloud-storage/google"
  version    = "~> 10.0"
  project_id = var.project_id
  location   = var.region
  names      = [local.facility_bucket_name]

  depends_on = [
    google_kms_crypto_key_iam_member.storage_sa_facility,
    google_kms_crypto_key_iam_member.writer_sa_facility,
  ]
  labels = merge(
    local.tags,
    {
      billing = "facility-bucket"
    }
  )
  bucket_policy_only = {
    (local.facility_bucket_name) = true
  }
  force_destroy = {
    (local.facility_bucket_name) = false
  }
  cors = [
    {
      origin          = local.cors_origins
      method          = ["GET"]
      response_header = ["*"]
      max_age_seconds = 3000
    }
  ]
  encryption_key_names = {
    (local.facility_bucket_name) = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/facility-key"
  }
}

resource "google_storage_bucket_iam_member" "patient_bucket_admin" {
  bucket = module.patient_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${local.writer_sa_email}"
}

resource "google_storage_bucket_iam_member" "facility_bucket_admin" {
  bucket = module.facility_bucket.name
  role   = "roles/storage.admin"
  member = "serviceAccount:${local.writer_sa_email}"
}

resource "google_storage_bucket_iam_member" "public_facility" {
  bucket = module.facility_bucket.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Logs Bucket for long-term log archival
module "logs_bucket" {
  source  = "terraform-google-modules/cloud-storage/google"
  version = "~> 10.0"
  count   = var.enable_log_export ? 1 : 0

  project_id = var.project_id
  location   = var.region
  names      = [local.logs_bucket_name]
  labels = merge(
    local.tags,
    {
      billing = "logs-bucket"
    }
  )

  bucket_policy_only = {
    (local.logs_bucket_name) = true
  }

  force_destroy = {
    (local.logs_bucket_name) = false
  }

  versioning = {
    (local.logs_bucket_name) = true
  }

  # 7-year retention. `is_locked = false`
  # retention_policy = {
  #   (local.logs_bucket_name) = {
  #     retention_period = 220752000 # 7 years in seconds (2555 × 86400)
  #     is_locked        = false
  #   }
  # }

  lifecycle_rules = [{
    action = {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
    condition = {
      age = 90
    }
    }, {
    action = {
      type          = "SetStorageClass"
      storage_class = "ARCHIVE"
    }
    condition = {
      age = 365
    }
  }]

  encryption_key_names = {
    (local.logs_bucket_name) = local.logs_kms_key_id
  }

  depends_on = [google_kms_crypto_key_iam_member.storage_sa_logs]
}

# Grant KMS permissions to Storage service account for logs bucket
resource "google_kms_crypto_key_iam_member" "storage_sa_logs" {
  count         = var.enable_log_export ? 1 : 0
  crypto_key_id = local.logs_kms_key_id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${var.project_number}@gs-project-accounts.iam.gserviceaccount.com"
}
