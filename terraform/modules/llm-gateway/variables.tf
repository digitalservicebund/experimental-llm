variable "project_id" {
  type        = string
  description = "STACKIT project ID that owns the gateway resources."
}

variable "existing_network_id" {
  type        = string
  description = "ID of the pre-existing STACKIT network to attach the VM to."
}

variable "availability_zone" {
  type        = string
  description = "STACKIT availability zone for the VM and boot volume."
  default     = "eu01-1"
}

variable "vm_enabled" {
  type        = bool
  description = "Whether the GPU VM, NIC, and public IP should exist."
  default     = true
}

variable "vm_name" {
  type        = string
  description = "Base name for the VM and related resources."
  default     = "llm-gateway"
}

variable "vm_machine_type_name" {
  type        = string
  description = "Exact STACKIT machine type name for the GPU instance."
  default     = ""
}

variable "bootstrap_ssh_user" {
  type        = string
  description = "Unix user that receives the bootstrap SSH key via cloud-init."
  default     = "ubuntu"
}

variable "bootstrap_ssh_public_key" {
  type        = string
  description = "Primary deployer SSH public key injected into the initial boot volume."
  sensitive   = true
  default     = ""
}

variable "boot_volume_size_gb" {
  type        = number
  description = "Size of the persistent boot volume in GiB."
  default     = 100
}

variable "boot_volume_performance_class" {
  type        = string
  description = "STACKIT block-storage performance class for the boot volume."
  default     = "storage_premium_perf6"
}

variable "ubuntu_image_name_regex" {
  type        = string
  description = "Regex used to pick the Ubuntu 26.04 base image."
  default     = "^Ubuntu 26\\.04"
}

