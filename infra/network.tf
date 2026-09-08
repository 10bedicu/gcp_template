resource "google_compute_address" "gateway_ip" {
  name   = local.gateway_ip_name
  region = var.region
}

resource "google_compute_address" "nat_ip" {
  name   = local.nat_ip_address_name
  region = var.region
}

resource "google_compute_global_address" "care_pip" {
  count = local.enable_legacy_ingress ? 1 : 0
  name  = local.legacy_ingress_ip_name
}

resource "google_compute_global_address" "care_fe" {
  count = local.enable_legacy_ingress ? 1 : 0
  name  = local.legacy_fe_ip_name
}

# moved {
#   from = google_compute_address.care_pip
#   to = google_compute_address.gateway_ip
# }

module "vpc" {
  source  = "terraform-google-modules/network/google"
  version = "~> 11.0"

  project_id   = var.project_id
  network_name = local.vpc_network_name

  subnets = [
    {
      subnet_name               = local.database_subnet_name
      subnet_ip                 = local.database_subnets
      subnet_region             = var.region
      subnet_flow_logs          = "true"
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      subnet_flow_logs_sampling = "0.5"
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
    },
    {
      subnet_name               = local.gke_subnet_name
      subnet_ip                 = var.gke_subnets
      subnet_region             = var.region
      subnet_flow_logs          = "true"
      subnet_flow_logs_metadata = "INCLUDE_ALL_METADATA"
      subnet_flow_logs_sampling = "0.5"
      subnet_flow_logs_interval = "INTERVAL_10_MIN"
    }
  ]

  secondary_ranges = {
    (local.gke_subnet_name) = [
      {
        range_name    = local.pods_range_name
        ip_cidr_range = var.gke_pods_range
      },
      {
        range_name    = local.services_range_name
        ip_cidr_range = var.gke_services_range
      }
    ]
  }
  routes = []
}

resource "google_compute_subnetwork" "proxy_only" {
  name          = local.proxy_only_subnet_name
  ip_cidr_range = var.proxy_only_subnet_cidr
  region        = var.region
  project       = var.project_id
  network       = module.vpc.network_id
  purpose       = "REGIONAL_MANAGED_PROXY"
  role          = "ACTIVE"
}

# GKE Pod and Service IP ranges for VPC-native cluster
resource "google_compute_global_address" "pods_range" {
  name          = local.pods_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.network_self_link
}

resource "google_compute_global_address" "services_range" {
  name          = local.services_range_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 20
  network       = module.vpc.network_self_link
}

resource "google_compute_router" "nat_router" {
  name    = "nat-router-${var.app}-${var.environment}"
  region  = var.region
  project = var.project_id
  network = module.vpc.network_id
}

resource "google_compute_router_nat" "cloud_nat" {
  name                               = "cloud-nat-${var.app}-${var.environment}"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  project                            = var.project_id
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.nat_ip.self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = module.vpc.subnets["${var.region}/${local.gke_subnet_name}"].id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

module "vpc_flow_logs_bucket" {
  source  = "terraform-google-modules/cloud-storage/google"
  version = "~> 10.0"

  project_id = var.project_id
  location   = var.region
  names      = [local.flow_logs_bucket]

  # Enforce uniform bucket-level access (no ACLs)
  bucket_policy_only = {
    (local.flow_logs_bucket) = true
  }
}
