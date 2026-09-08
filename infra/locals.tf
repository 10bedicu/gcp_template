locals {
  required_tags = {
    terraform   = "true"
    environment = var.environment
    app         = var.app
    project     = "care"
  }

  common_labels = {
    app         = var.app
    environment = var.environment
    project     = "care"
  }
  tags                 = local.required_tags
  database_subnets     = var.database_subnets
  gke_subnets          = var.gke_subnets
  gke_pods_range       = var.gke_pods_range
  gke_services_range   = var.gke_services_range
  patient_bucket_name  = "${var.org}-${var.environment}-${var.app}-patient"
  facility_bucket_name = "${var.org}-${var.environment}-${var.app}-facility"
  dicom_bucket_name    = "${var.org}-${var.environment}-${var.app}-dicom"
  writer_sa_email      = module.service_accounts.email
  #middleware_sa_email  = module.middleware_archive_service_accounts.email

  cluster_name = coalesce(var.cluster_name, "${var.org}-${var.app}-${var.environment}")

  # Network resource name resolution (legacy name support)
  vpc_network_name         = coalesce(var.vpc_network_name, "${var.org}-${var.environment}")
  database_subnet_name     = coalesce(var.database_subnet_name, "database-${var.app}-${var.environment}")
  gke_subnet_name          = coalesce(var.gke_subnet_name, "gke-${var.app}-${var.environment}")
  pods_range_name          = coalesce(var.pods_range_name, "gke-pods-range-${var.app}-${var.environment}")
  services_range_name      = coalesce(var.services_range_name, "gke-services-range-${var.app}-${var.environment}")
  gateway_ip_name          = coalesce(var.gateway_ip_name, "care-pip-${var.app}-${var.environment}")
  legacy_ingress_ip_name   = coalesce(var.legacy_ingress_ip_name, "care-pip")
  legacy_fe_ip_name        = coalesce(var.legacy_fe_ip_name, "care-fe")
  cloudsql_private_ip_name = coalesce(var.cloudsql_private_ip_name, "cloudsql-private-ip-${var.app}-${var.environment}")
  nat_ip_address_name      = coalesce(var.nat_ip_address_name, "nat-ip-${var.app}-${var.environment}")
  proxy_only_subnet_name   = coalesce(var.proxy_only_subnet_name, "proxy-only-subnet-${var.app}-${var.environment}")

  logs_bucket_name  = coalesce(var.logs_bucket, "${var.org}-${var.environment}-${var.app}-logs")
  logging_bucket_id = "${var.org}-${var.app}-${var.environment}-logging"

  # Single source of truth for the logs KMS key path (used by GCS archive and regional Cloud Logging bucket).
  logs_kms_key_id = "projects/${var.project_id}/locations/${var.region}/keyRings/${var.org}-${var.app}-${var.environment}-keyring/cryptoKeys/logs-key"

  enable_legacy_ingress = var.enable_legacy_ingress

  cors_origins = [for domain in var.web_domain_name : "https://${domain}"]
}
