resource "google_compute_address" "jumphost_ip" {
  count   = var.enable_jumphost ? 1 : 0
  name    = "jumphost-ip-${var.app}-${var.environment}"
  region  = var.region
  project = var.project_id
}

resource "google_compute_instance" "jumphost" {
  count        = var.enable_jumphost ? 1 : 0
  name         = "jumphost-${var.app}-${var.environment}"
  machine_type = "e2-medium"
  zone         = var.zone
  project      = var.project_id

  tags = ["jumphost-${var.app}-${var.environment}", "ssh"]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-13"
      size  = 30
      type  = "pd-balanced"
    }
  }

  network_interface {
    network    = module.vpc.network_name
    subnetwork = local.gke_subnet_name

    access_config {
      nat_ip = google_compute_address.jumphost_ip[0].address
    }
  }

  service_account {
    email  = var.service_account_email
    scopes = ["cloud-platform"]
  }

  metadata = {
    enable-oslogin = "FALSE"
    ssh-keys       = join("\n", [for entry in var.jumphost_ssh_keys : "${entry.user}:${entry.key}"])
    startup-script = <<-EOT
      #!/bin/bash
      set -e

      LOCK_FILE="/opt/.startup-script-done"
      if [ -f "$LOCK_FILE" ]; then
        echo "Startup script already ran. Skipping."
        exit 0
      fi

      # Install jq
      apt-get update -y
      apt-get install -y jq

      # Install Google Cloud CLI
      curl -sSL https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-linux-x86_64.tar.gz | tar xz -C /opt
      /opt/google-cloud-sdk/install.sh --quiet --path-update true
      ln -sf /opt/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud
      ln -sf /opt/google-cloud-sdk/bin/gsutil /usr/local/bin/gsutil
      ln -sf /opt/google-cloud-sdk/bin/bq /usr/local/bin/bq

      # Install hcledit
      curl -sSL https://github.com/minamijoyo/hcledit/releases/download/v0.2.17/hcledit_0.2.17_linux_amd64.tar.gz | tar xz
      mv hcledit /usr/local/bin/

      # Install OpenTofu v1.11.5
      curl -sSL https://github.com/opentofu/opentofu/releases/download/v1.11.5/tofu_1.11.5_linux_amd64.tar.gz | tar xz -C /tmp
      mv /tmp/tofu /usr/local/bin/

      touch "$LOCK_FILE"
    EOT
  }

  labels = local.common_labels

}

resource "google_compute_firewall" "jumphost_ssh" {
  count   = var.enable_jumphost ? 1 : 0
  name    = "jumphost-${var.app}-${var.environment}"
  network = module.vpc.network_name
  project = var.project_id

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["jumphost-${var.app}-${var.environment}"]

  log_config {
    metadata = "INCLUDE_ALL_METADATA"
  }
}
