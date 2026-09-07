locals {
  recaptcha_allowed_domains = distinct(concat(var.web_domain_name, var.api_domain_name, var.recaptcha_additional_domains))
}

resource "google_recaptcha_enterprise_key" "care" {
  project      = var.project_id
  display_name = "${var.org}-${var.app}-${var.environment}"
  labels       = local.common_labels

  web_settings {
    # CARE FE renders a v2 checkbox, so SCORE would break login.
    integration_type  = "CHECKBOX"
    allow_all_domains = length(local.recaptcha_allowed_domains) == 0
    allowed_domains   = local.recaptcha_allowed_domains
  }

  lifecycle {
    precondition {
      condition     = !var.enable_recaptcha || length(local.recaptcha_allowed_domains) > 0
      error_message = "enable_recaptcha requires at least one domain in web_domain_name, api_domain_name or recaptcha_additional_domains, otherwise the key would accept requests from any domain."
    }
  }
}

data "google_client_config" "default" {}

# The provider exposes no secret key attribute, so it is fetched over REST.
data "http" "recaptcha_legacy_secret" {
  count = var.enable_recaptcha ? 1 : 0

  url = "https://recaptchaenterprise.googleapis.com/v1/projects/${var.project_id}/keys/${google_recaptcha_enterprise_key.care.name}:retrieveLegacySecretKey"

  request_headers = {
    Authorization = join(" ", ["Bearer", data.google_client_config.default.access_token])
  }

  retry {
    attempts = 2
  }

  request_timeout_ms = 10000

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "retrieveLegacySecretKey returned HTTP ${self.status_code}. The principal applying this module needs recaptchaenterprise.keys.retrievelegacysecretkey. Response: ${self.response_body}"
    }
  }
}
