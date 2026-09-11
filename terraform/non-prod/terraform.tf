terraform {
  required_version = ">= 1.13.0"

  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "~> 0.114.0"
    }

    aws = {
      source  = "hashicorp/aws"
      version = ">=6.28.0"
    }
  }

  backend "s3" {
    bucket       = "self-hosted-llm-terraform-state"
    key          = "tfstate-backend"
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
