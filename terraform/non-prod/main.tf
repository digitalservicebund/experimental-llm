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
