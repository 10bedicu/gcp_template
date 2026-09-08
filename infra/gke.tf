module "gke_cluster" {
  source  = "terraform-google-modules/kubernetes-engine/google"
  version = "~> 38.0"

  project_id          = var.project_id
  name                = local.cluster_name
  regional            = false
  region              = var.region
  zones               = [var.zone]
  network             = module.vpc.network_name
  subnetwork          = local.gke_subnet_name
  deletion_protection = true
  ip_range_pods       = google_compute_global_address.pods_range.name
  cluster_resource_labels = {
    billing = "gke-cluster"
  }
  ip_range_services        = google_compute_global_address.services_range.name
  remove_default_node_pool = true

  # Maintenance window: Wed, Thu, Sat, Sun 12 AM – 4 AM IST (18:30 – 22:30 UTC)
  maintenance_start_time = "2024-01-03T18:30:00Z"
  maintenance_end_time   = "2024-01-03T22:30:00Z"
  maintenance_recurrence = "FREQ=WEEKLY;BYDAY=WE,TH,SA,SU"

  # Enable Gateway API for regional external Application Load Balancer
  gateway_api_channel = "CHANNEL_STANDARD"

  # Explicit logging configuration
  logging_service = "logging.googleapis.com/kubernetes"

  # release channel
  release_channel = "STABLE"

  # → enable GKE Metadata Server for Workload Identity
  node_metadata = "GKE_METADATA_SERVER"

  # → run every node under your writer SA
  service_account = local.writer_sa_email

  # → give all node-pools full cloud-platform scope
  node_pools_oauth_scopes = {
    all = ["https://www.googleapis.com/auth/cloud-platform"]
  }

  # Enable DNS-based control plane endpoint (IAM-secured access)
  dns_allow_external_traffic = true

  # Disable public IP endpoint — control plane is now private
  ip_endpoints_enabled = false

  # → leave pools definition unchanged
  node_pools = var.node_pools
  node_pools_labels = {
    "default" : {
      "billing" : "gke-node-pools"
    }
  }
}


#################################################################
# 3. IAM binding: allow the KSA to impersonate the GSA
#################################################################
resource "google_service_account_iam_member" "gcloud_debugger_wi" {
  service_account_id = "projects/${var.project_id}/serviceAccounts/${local.writer_sa_email}"
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[default/gcloud-debugger-sa]"
}

#################################################################
# Allow GKE nodes to pull images from Artifact Registry
#################################################################
resource "google_project_iam_member" "node_sa_ar_reader" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${local.writer_sa_email}"
}
