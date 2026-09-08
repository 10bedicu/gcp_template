module "dns_zone_tofu" {
  count       = var.enable_dns_zone ? 1 : 0
  source      = "terraform-google-modules/cloud-dns/google"
  version     = "~> 6.0"
  project_id  = var.project_id
  name        = "${var.org}-${var.app}-${var.environment}"
  domain      = "${var.dns_zone_domain}."
  description = "Managed zone for ${var.dns_zone_domain}"
  labels = {
    billing     = "cloud-cdn"
    environment = var.environment
    app         = var.app
  }
  type           = "public"
  enable_logging = true

  depends_on = [module.project_services]
}
