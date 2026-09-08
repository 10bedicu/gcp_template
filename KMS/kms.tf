moved {
  from = module.kms.google_kms_crypto_key.key_ephemeral[0]
  to   = module.kms.google_kms_crypto_key.key[0]
}

moved {
  from = module.kms.google_kms_crypto_key.key_ephemeral[1]
  to   = module.kms.google_kms_crypto_key.key[1]
}

moved {
  from = module.kms.google_kms_crypto_key.key_ephemeral[2]
  to   = module.kms.google_kms_crypto_key.key[2]
}

module "kms" {
  source     = "terraform-google-modules/kms/google"
  version    = "~> 4.0"
  project_id = var.project_id
  keyring    = "${var.org}-${var.app}-${var.environment}-keyring"
  location   = var.region
  keys       = ["patient-key", "facility-key", "dicom-key", "logs-key"]

  set_owners_for = ["patient-key", "facility-key", "dicom-key", "logs-key"]
  owners = [
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:${var.service_account_email}",
    "serviceAccount:${var.service_account_email}",
  ]
  prevent_destroy = true
}
