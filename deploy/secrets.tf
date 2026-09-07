resource "kubernetes_secret" "care_backend" {
  metadata {
    name      = "care-backend-secret"
    namespace = local.namespace_name
    labels    = local.common_labels
  }
  type       = "Opaque"
  data       = { for k, v in local.secret_data : k => v }
  depends_on = [kubernetes_namespace.care_namespace]

  lifecycle {
    precondition {
      condition     = !var.enable_recaptcha || (local.recaptcha_site_key != null && local.recaptcha_secret_key != null)
      error_message = "enable_recaptcha is set but the infra module has not published the reCAPTCHA outputs. Apply infra/ with the same tfvars first."
    }
  }
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

resource "random_password" "dicom_webhook_secret" {
  count   = var.enable_dicom ? 1 : 0
  length  = 64
  special = false
}

resource "random_password" "ldap_admin_password" {
  length  = 32
  special = false
}
