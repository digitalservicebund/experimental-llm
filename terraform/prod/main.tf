terraform {
  required_version = ">= 1.13.0"

  backend "s3" {}

  required_providers {
    stackit = {
      source  = "stackitcloud/stackit"
      version = "~> 0.114.0"
    }
  }
}

provider "stackit" {
  default_region        = var.region
  experiments           = ["iam"]
  enable_beta_resources = true # needed for stackit_image_v2 and stackit_machine_type
}

module "llm_gateway" {
  source = "../modules/llm-gateway"

  project_id                    = var.project_id
  existing_network_id           = var.existing_network_id
  availability_zone             = var.availability_zone
  vm_enabled                    = var.vm_enabled
  vm_name                       = var.vm_name
  vm_machine_type_name          = var.vm_machine_type_name
  bootstrap_ssh_user            = var.bootstrap_ssh_user
  bootstrap_ssh_public_key      = var.bootstrap_ssh_public_key
  boot_volume_size_gb           = var.boot_volume_size_gb
  boot_volume_performance_class = var.boot_volume_performance_class
  ubuntu_image_name_regex       = var.ubuntu_image_name_regex
}

