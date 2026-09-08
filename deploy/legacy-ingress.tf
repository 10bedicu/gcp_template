# Legacy GCE Ingress resources for parallel operation during migration.
# All resources are gated by enable_legacy_ingress (default: false).
# This allows running legacy global LB alongside the new Gateway API regional LB.

# --- Cloud Armor (Global, required for GCE Ingress) ---

module "cloud_armor" {
  count   = local.enable_legacy_ingress ? 1 : 0
  source  = "GoogleCloudPlatform/cloud-armor/google"
  version = "5.1.0"

  project_id          = var.project_id
  name                = "care-security-policy"
  description         = "Global Cloud Armor security policy for legacy CARE ingress"
  default_rule_action = "allow"

  custom_rules = {
    block_non_india = {
      action      = "deny(403)"
      priority    = 900
      description = "Block requests from outside India"
      expression  = "origin.region_code != 'IN'"
    }
  }

  pre_configured_rules = {
    block_sqli = {
      action          = "deny(403)"
      priority        = 1000
      description     = "Block SQL injection attacks"
      target_rule_set = "sqli-stable"
    }
    block_xss = {
      action          = "deny(403)"
      priority        = 1001
      description     = "Block XSS attacks"
      target_rule_set = "xss-stable"
    }
    block_rce = {
      action          = "deny(403)"
      priority        = 1002
      description     = "Block remote code execution attempts"
      target_rule_set = "rce-stable"
    }
    block_lfi = {
      action          = "deny(403)"
      priority        = 1003
      description     = "Block local file inclusion attempts"
      target_rule_set = "lfi-stable"
    }
    block_scanners = {
      action          = "deny(403)"
      priority        = 1004
      description     = "Block scanners and known malicious requests"
      target_rule_set = "scannerdetection-stable"
    }
  }
}

# --- SSL Policy (Global) ---

resource "google_compute_ssl_policy" "care_ssl_policy" {
  count           = local.enable_legacy_ingress ? 1 : 0
  name            = "care-ssl-policy"
  min_tls_version = "TLS_1_2"
  profile         = "MODERN"
}

# --- BackendConfig resources ---

resource "kubernetes_manifest" "backend_config" {
  count = local.enable_legacy_ingress ? 1 : 0
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "care-backend-config"
      namespace = local.namespace_name
    }
    spec = {
      timeoutSec = 60
      connectionDraining = {
        drainingTimeoutSec = 60
      }
      healthCheck = {
        checkIntervalSec   = 10
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 3
        port               = 9000
        type               = "HTTP"
        requestPath        = "/ping/"
      }
    }
  }
}

resource "kubernetes_manifest" "metabase_backend_config" {
  count = local.enable_legacy_ingress ? 1 : 0
  manifest = {
    apiVersion = "cloud.google.com/v1"
    kind       = "BackendConfig"
    metadata = {
      name      = "metabase-backend-config"
      namespace = local.namespace_name
    }
    spec = {
      timeoutSec = 60
      connectionDraining = {
        drainingTimeoutSec = 60
      }
      healthCheck = {
        checkIntervalSec   = 10
        timeoutSec         = 5
        healthyThreshold   = 1
        unhealthyThreshold = 3
        port               = 3000
        type               = "HTTP"
        requestPath        = "/api/health"
      }
    }
  }
}

# --- NodePort Services for Legacy Ingress (separate from Helm-managed services) ---

resource "kubernetes_service" "care_service_legacy" {
  count = local.enable_legacy_ingress ? 1 : 0
  metadata {
    name      = "care-backend-legacy"
    namespace = local.namespace_name
    labels = {
      "app"          = "care-backend-legacy"
      "ingress-type" = "legacy"
    }
    annotations = {
      "cloud.google.com/neg"            = jsonencode({ ingress = true })
      "cloud.google.com/backend-config" = jsonencode({ default = "care-backend-config" })
    }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"      = "care-be"
      "app.kubernetes.io/instance"  = "care-backend"
      "app.kubernetes.io/component" = "api"
    }
    port {
      name        = "http"
      port        = 80
      target_port = 9000
      protocol    = "TCP"
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations["cloud.google.com/neg-status"]]
  }
  depends_on = [kubernetes_manifest.backend_config]
}

resource "kubernetes_service" "metabase_service_legacy" {
  count = local.enable_legacy_ingress ? 1 : 0
  metadata {
    name      = "metabase-legacy"
    namespace = local.namespace_name
    labels = {
      "app"          = "metabase-legacy"
      "ingress-type" = "legacy"
    }
    annotations = {
      "cloud.google.com/neg"            = jsonencode({ ingress = true })
      "cloud.google.com/backend-config" = jsonencode({ default = "metabase-backend-config" })
    }
  }
  spec {
    type = "NodePort"
    selector = {
      "app.kubernetes.io/name"     = "metabase"
      "app.kubernetes.io/instance" = "metabase"
    }
    port {
      name        = "metabase"
      port        = 3000
      target_port = 3000
      protocol    = "TCP"
    }
  }
  lifecycle {
    ignore_changes = [metadata[0].annotations["cloud.google.com/neg-status"]]
  }
  depends_on = [kubernetes_manifest.metabase_backend_config]
}

# --- FrontendConfig (HTTPS redirect) ---

resource "kubernetes_manifest" "frontend_config" {
  count = local.enable_legacy_ingress ? 1 : 0
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "FrontendConfig"
    metadata = {
      name      = "nginx-frontend-config"
      namespace = local.namespace_name
    }
    spec = {
      redirectToHttps = { enabled = true }
    }
  }
}

# --- ManagedCertificates (one per domain — GKE limit: 1 domain per cert) ---

resource "kubernetes_manifest" "managed_cert_api" {
  for_each = local.enable_legacy_ingress ? toset(var.api_domain_name) : toset([])
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "legacy-cert-api-${replace(each.value, ".", "-")}"
      namespace = local.namespace_name
    }
    spec = {
      domains = [each.value]
    }
  }
}

resource "kubernetes_manifest" "managed_cert_metabase" {
  for_each = local.enable_legacy_ingress ? toset(var.metabase_domain_name) : toset([])
  manifest = {
    apiVersion = "networking.gke.io/v1beta1"
    kind       = "ManagedCertificate"
    metadata = {
      name      = "legacy-cert-metabase-${replace(each.value, ".", "-")}"
      namespace = local.namespace_name
    }
    spec = {
      domains = [each.value]
    }
  }
}

# --- GCE Ingress ---

resource "kubernetes_ingress_v1" "nginx_ingress" {
  count = local.enable_legacy_ingress ? 1 : 0
  metadata {
    name      = "nginx-ingress"
    namespace = local.namespace_name
    annotations = {
      "kubernetes.io/ingress.class"                 = "gce"
      "kubernetes.io/ingress.global-static-ip-name" = local.legacy_ingress_ip_name
      "networking.gke.io/managed-certificates"      = join(",", concat([for cert in kubernetes_manifest.managed_cert_api : cert.manifest.metadata.name], [for cert in kubernetes_manifest.managed_cert_metabase : cert.manifest.metadata.name]))
      "networking.gke.io/v1beta1.FrontendConfig"    = kubernetes_manifest.frontend_config[0].manifest.metadata.name
      "kubernetes.io/ingress.allow-http"            = "false"
      "cloud.google.com/security-policy"            = module.cloud_armor[0].policy.name
    }
  }

  spec {
    dynamic "rule" {
      for_each = var.api_domain_name
      content {
        host = rule.value
        http {
          path {
            path      = "/*"
            path_type = "ImplementationSpecific"
            backend {
              service {
                name = kubernetes_service.care_service_legacy[0].metadata[0].name
                port {
                  number = 80
                }
              }
            }
          }
        }
      }
    }
    dynamic "rule" {
      for_each = var.metabase_domain_name
      content {
        host = rule.value
        http {
          path {
            path      = "/*"
            path_type = "ImplementationSpecific"
            backend {
              service {
                name = kubernetes_service.metabase_service_legacy[0].metadata[0].name
                port {
                  number = 3000
                }
              }
            }
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_manifest.managed_cert_api,
    kubernetes_manifest.managed_cert_metabase,
    kubernetes_service.care_service_legacy,
    kubernetes_service.metabase_service_legacy,
    kubernetes_manifest.frontend_config,
    module.cloud_armor
  ]
}
