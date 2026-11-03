terraform {
  required_version = ">= 1.13.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  # Same bucket as terraform/non-prod. Credentials come from AWS_ACCESS_KEY_ID
  # and AWS_SECRET_ACCESS_KEY (see README).
  backend "s3" {
    bucket       = "self-hosted-llm-terraform-state"
    key          = "gcp-vertex-ai"
    use_lockfile = true
    endpoints = {
      s3 = "https://object.storage.eu01.onstackit.cloud"
    }
    region                      = "eu01"
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_s3_checksum            = true
    skip_requesting_account_id  = true
  }
}

provider "google" {
  project = var.project_id

  # Local Application Default Credentials need a quota project for the IAM APIs.
  billing_project       = var.project_id
  user_project_override = true
}
