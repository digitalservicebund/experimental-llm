terraform {
  required_version = ">= 1.13.0"

  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "~> 0.114.0"
    }
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

  github_repository     = var.github_repository
  github_subjects       = var.github_subjects
  additional_assertions = var.additional_assertions

  roles       = var.roles
  permissions = var.permissions
}
