terraform {
  required_version = ">= 1.13.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }
}

provider "google" {
  project = var.project_id

  # Local Application Default Credentials need a quota project for the IAM APIs.
  billing_project       = var.project_id
  user_project_override = true
}
