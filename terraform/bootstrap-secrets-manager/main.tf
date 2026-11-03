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
    key          = "bootstrap-secrets-manager"
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
}

provider "vault" {
  address          = "https://prod.sm.eu01.stackit.cloud"
  skip_child_token = true

  auth_login_userpass {
    username = module.secrets_manager.terraform_username
    password = module.secrets_manager.terraform_password
  }
}
