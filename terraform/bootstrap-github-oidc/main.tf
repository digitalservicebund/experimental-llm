terraform {
  required_version = ">= 1.13.0"

  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "~> 0.114.0"
    }
  }

  # Same bucket as terraform/non-prod. Credentials come from AWS_ACCESS_KEY_ID
  # and AWS_SECRET_ACCESS_KEY (see README).
  backend "s3" {
    bucket       = "self-hosted-llm-terraform-state"
    key          = "bootstrap-github-oidc"
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

provider "stackit" {
  default_region = var.region
  experiments    = ["iam"]
}

module "github_actions_identity_federation" {
  source = "github.com/digitalservicebund/terraform-modules?ref=stackit-identity-federation/v1.1.2"

  project_id = var.project_id
  name       = var.name

  github_repository = var.github_repository
  github_subjects   = var.github_subjects

  roles       = var.roles
  permissions = var.permissions
}
