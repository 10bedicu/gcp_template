terraform {
  required_version = "~> 1.11"

  backend "gcs" {
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.33"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.33"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.7"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.0"
    }
  }
}

data "terraform_remote_state" "infra" {
  backend = "gcs"
  config = {
    bucket = var.backend_bucket
    prefix = "infra"
  }
}

data "terraform_remote_state" "keys" {
  backend = "gcs"
  config = {
    bucket = var.backend_bucket
    prefix = "keys"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host  = "https://${data.terraform_remote_state.infra.outputs.gke_dns_endpoint}"
  token = data.google_client_config.default.access_token
}

provider "helm" {
  kubernetes {
    host  = "https://${data.terraform_remote_state.infra.outputs.gke_dns_endpoint}"
    token = data.google_client_config.default.access_token
  }
}
