resource "random_password" "database_master" {
  length  = 20
  special = false
  lifecycle {
    ignore_changes = [override_special]
  }
}

resource "random_password" "metabase_database_master" {
  length  = 20
  special = false
  lifecycle {
    ignore_changes = [override_special]
  }
}

resource "random_password" "dicom_database_password" {
  length  = 20
  special = false
  lifecycle {
    ignore_changes = [override_special]
  }
}

resource "google_compute_global_address" "cloudsql_private_ip" {
  name          = local.cloudsql_private_ip_name
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = module.vpc.network_self_link
}

resource "google_service_networking_connection" "cloudsql_psa" {
  network                 = module.vpc.network_self_link
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.cloudsql_private_ip.name]
  update_on_creation_fail = true
}

module "cloudsql" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version = "~> 26.1.0"

  # Core instance settings
  project_id = var.project_id
  name       = "care-${var.app}-${var.environment}"
  region     = var.region
  edition    = "ENTERPRISE"
  zone       = var.zones[0]

  # Database version and configuration
  database_version = "POSTGRES_17"
  tier             = var.cloudsql_tier

  # High availability and disk configuration
  availability_type = var.cloudsql_availability_type
  disk_type         = "PD_SSD"
  disk_size         = var.cloudsql_disk_size
  disk_autoresize   = true

  # Security and networking
  deletion_protection         = true
  deletion_protection_enabled = true
  retain_backups_on_delete    = true

  # User labels
  user_labels = merge(
    local.tags,
    {
      billing = "care-db"
    }
  )
  # Database flags for logging and monitoring
  database_flags = [
    {
      name  = "log_checkpoints"
      value = "on"
    },
    {
      name  = "log_connections"
      value = "on"
    },
    {
      name  = "log_disconnections"
      value = "on"
    },
    {
      name  = "log_lock_waits"
      value = "on"
    },
    {
      name  = "log_temp_files"
      value = "0"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      name  = "log_statement"
      value = "mod"
    }
  ]

  # IP configuration for private networking
  ip_configuration = {
    ipv4_enabled                                  = false
    private_network                               = module.vpc.network_self_link
    enable_private_path_for_google_cloud_services = true
    authorized_networks                           = []
  }

  # Backup configuration
  backup_configuration = {
    enabled                        = true
    start_time                     = "22:00"
    location                       = var.region
    point_in_time_recovery_enabled = true
    transaction_log_retention_days = 7
    retained_backups               = 7
    retention_unit                 = "COUNT"
  }

  # Insights configuration
  insights_config = {
    query_plans_per_minute  = 5
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
  }

  # Maintenance window
  maintenance_window_day          = 7
  maintenance_window_hour         = 3
  maintenance_window_update_track = "stable"

  # Database and user configuration
  db_name      = "${var.app}_${var.environment}"
  db_charset   = "UTF8"
  db_collation = "en_US.UTF8"

  user_name     = "${var.app}_${var.environment}_user"
  user_password = random_password.database_master.result

  additional_databases = [
    {
      name      = "${var.app}_${var.environment}_user"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
    {
      name      = "dicom_${var.environment}"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
  ]

  additional_users = [
    {
      name            = "dicom_${var.environment}_user"
      password        = random_password.dicom_database_password.result
      random_password = false
    },
  ]

  # Read replicas
  read_replicas = [
    for i in range(var.cloudsql_read_replica_count) : {
      name              = "-read-${i + 1}"
      tier              = coalesce(var.cloudsql_read_replica_tier, var.cloudsql_tier)
      zone              = element(var.zones, (i + 1) % length(var.zones))
      availability_type = "ZONAL"
      disk_type         = "PD_SSD"
      disk_autoresize   = true
      disk_size         = null
      user_labels = merge(
        local.tags,
        {
          billing = "read-replica-${i + 1}"
        }
      )
      database_flags = [
        {
          name  = "log_checkpoints"
          value = "on"
        },
        {
          name  = "log_connections"
          value = "on"
        },
        {
          name  = "log_disconnections"
          value = "on"
        },
        {
          name  = "log_lock_waits"
          value = "on"
        },
        {
          name  = "log_temp_files"
          value = "0"
        },
        {
          name  = "log_min_duration_statement"
          value = "1000"
        },
        {
          name  = "log_statement"
          value = "mod"
        }
      ]
      ip_configuration = {
        ipv4_enabled                                  = false
        private_network                               = module.vpc.network_self_link
        enable_private_path_for_google_cloud_services = true
        authorized_networks                           = []
      }
      insights_config = {
        query_plans_per_minute  = 5
        query_string_length     = 1024
        record_application_tags = true
        record_client_address   = true
      }
    }
  ]

  depends_on = [
    google_service_networking_connection.cloudsql_psa
  ]
}

module "metabase_cloudsql" {
  source  = "GoogleCloudPlatform/sql-db/google//modules/postgresql"
  version = "~> 26.1.0"

  # Core instance settings
  project_id = var.project_id
  name       = "metabase-${var.app}-${var.environment}"
  region     = var.region
  edition    = "ENTERPRISE"
  zone       = var.zones[0]

  # Database version and configuration
  database_version = "POSTGRES_17"
  tier             = var.metabase_cloudsql_tier

  # High availability and disk configuration
  availability_type = "ZONAL"
  disk_type         = "PD_SSD"
  disk_size         = var.metabase_cloudsql_disk_size
  disk_autoresize   = true

  # Security and networking
  deletion_protection         = true
  deletion_protection_enabled = true
  retain_backups_on_delete    = true

  # User labels
  user_labels = merge(
    local.tags,
    {
      billing = "metabase-db"
    }
  )
  # Database flags for logging and monitoring
  database_flags = [
    {
      name  = "log_checkpoints"
      value = "on"
    },
    {
      name  = "log_connections"
      value = "on"
    },
    {
      name  = "log_disconnections"
      value = "on"
    },
    {
      name  = "log_lock_waits"
      value = "on"
    },
    {
      name  = "log_temp_files"
      value = "0"
    },
    {
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      name  = "log_statement"
      value = "mod"
    },
    {
      name  = "cloudsql.enable_pg_cron"
      value = "on"
    }
  ]

  # IP configuration for private networking
  ip_configuration = {
    ipv4_enabled                                  = false
    private_network                               = module.vpc.network_self_link
    enable_private_path_for_google_cloud_services = true
    authorized_networks                           = []
  }

  # Backup configuration
  backup_configuration = {
    enabled                        = true
    start_time                     = "22:00"
    location                       = var.region
    point_in_time_recovery_enabled = true
    transaction_log_retention_days = 7
    retained_backups               = 7
    retention_unit                 = "COUNT"
  }

  # Insights configuration
  insights_config = {
    query_plans_per_minute  = 5
    query_string_length     = 1024
    record_application_tags = true
    record_client_address   = true
  }

  # Maintenance window
  maintenance_window_day          = 7
  maintenance_window_hour         = 3
  maintenance_window_update_track = "stable"

  # Database and user configuration
  db_name      = "metabase_${var.environment}"
  db_charset   = "UTF8"
  db_collation = "en_US.UTF8"

  user_name     = "metabase_${var.environment}_user"
  user_password = random_password.metabase_database_master.result

  additional_databases = [
    {
      name      = "metabase_warehouse"
      charset   = "UTF8"
      collation = "en_US.UTF8"
    },
  ]

  # No read replicas for metabase
  read_replicas = []

  depends_on = [
    google_service_networking_connection.cloudsql_psa
  ]
}
