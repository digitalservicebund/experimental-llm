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
  default_region        = var.region
}

provider "vault" {
  address          = "https://prod.sm.eu01.stackit.cloud"
  skip_child_token = true

  auth_login_userpass {
    username = module.secrets_manager.terraform_username
    password = module.secrets_manager.terraform_password
  }
}
