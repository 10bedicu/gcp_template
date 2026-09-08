resource "kubernetes_secret" "care_backend" {
  metadata {
    name      = "care-backend-secret"
    namespace = local.namespace_name
    labels    = local.common_labels
  }
  type       = "Opaque"
  data       = { for k, v in local.secret_data : k => v }
  depends_on = [kubernetes_namespace.care_namespace]
}

resource "kubernetes_secret" "metabase" {
  metadata {
    name      = "metabase-secret"
    namespace = local.namespace_name
    labels    = local.common_labels
  }
  type       = "Opaque"
  data       = { for k, v in local.metabase_secret_data : k => v }
  depends_on = [kubernetes_namespace.care_namespace]
}

resource "kubernetes_secret" "dcm4chee" {
  count = var.enable_dicom ? 1 : 0
  metadata {
    name      = "dcm4chee-secret"
    namespace = local.namespace_name
    labels    = local.common_labels
  }
  type       = "Opaque"
  data       = { for k, v in local.dicom_secret_data : k => v }
  depends_on = [kubernetes_namespace.care_namespace]
}

resource "kubernetes_secret" "external_tls" {
  count = var.external_tls_cert != null ? 1 : 0

  metadata {
    name      = local.external_tls_secret_name
    namespace = local.namespace_name
    labels    = local.common_labels
  }

  type = "kubernetes.io/tls"

  data = {
    "tls.crt" = var.external_tls_cert
    "tls.key" = var.external_tls_key
  }

  depends_on = [kubernetes_namespace.care_namespace]
}

# Resolves the latest commit SHA of metabase_etl_branch on every plan/apply so
# that the provision Job's checksum annotation (helm_charts/metabase/templates/
# provision-job.yaml) changes whenever the upstream SQL repo changes, forcing
# Helm to create a new Job run even if no other chart values changed.
data "http" "metabase_etl_latest_commit" {
  count = var.metabase_etl_repo != null ? 1 : 0

  url = "https://api.github.com/repos/${var.metabase_etl_repo}/commits/${var.metabase_etl_branch}"

  request_headers = {
    Accept = "application/vnd.github+json"
  }
}

resource "kubernetes_secret" "metabase_etl" {
  count = var.metabase_etl_repo != null ? 1 : 0

  metadata {
    name      = "metabase-etl-secret"
    namespace = local.namespace_name
    labels    = local.common_labels
  }
  type = "Opaque"
  data = {
    WAREHOUSE_URL            = "postgresql://${data.terraform_remote_state.infra.outputs.metabase_database_user}:${data.terraform_remote_state.infra.outputs.metabase_database_password}@${data.terraform_remote_state.infra.outputs.metabase_instance_address}:5432/metabase_warehouse"
    POSTGRES_URL             = "postgresql://${data.terraform_remote_state.infra.outputs.metabase_database_user}:${data.terraform_remote_state.infra.outputs.metabase_database_password}@${data.terraform_remote_state.infra.outputs.metabase_instance_address}:5432/postgres"
    CARE_SOURCE_URL          = "postgresql://${data.terraform_remote_state.infra.outputs.database_user}:${data.terraform_remote_state.infra.outputs.database_password}@${data.terraform_remote_state.infra.outputs.instance_address}:5432/${var.app}_${var.environment}"
    WAREHOUSE_DB             = "metabase_warehouse"
    SOURCE_REPLICA_HOST      = data.terraform_remote_state.infra.outputs.read_replica_address
    SOURCE_DBNAME            = "${var.app}_${var.environment}"
    WAREHOUSE_ETL_PASSWORD   = data.terraform_remote_state.keys.outputs.warehouse_etl_password
    FDW_READER_PASSWORD      = data.terraform_remote_state.keys.outputs.warehouse_fdw_reader_password
    METABASE_READER_PASSWORD = data.terraform_remote_state.keys.outputs.metabase_reader_password
  }
  depends_on = [kubernetes_namespace.care_namespace]

  lifecycle {
    precondition {
      condition     = data.terraform_remote_state.infra.outputs.read_replica_address != null
      error_message = "Metabase ETL provisioning (metabase_etl_repo) requires the infra module's cloudsql_read_replica_count to be > 0."
    }
  }
}

resource "random_password" "dicom_webhook_secret" {
  count   = var.enable_dicom ? 1 : 0
  length  = 64
  special = false
}

resource "random_password" "ldap_admin_password" {
  length  = 32
  special = false
}
