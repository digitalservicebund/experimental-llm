variable "region" {
  type        = string
  description = "STACKIT region for non-production infrastructure."
  default     = "eu01"
}

variable "project_id" {
  type        = string
  description = "STACKIT project ID that owns the non-production resources."
}

variable "existing_network_id" {
  type        = string
  description = "ID of the existing STACKIT network named llm."
}

variable "availability_zone" {
  type        = string
  description = "STACKIT availability zone for the VM and boot volume."
  default     = "eu01-1"
}

variable "vm_enabled" {
  type        = bool
  description = "Whether the GPU VM should be created."
  default     = true
}

variable "vm_name" {
  type        = string
  description = "Logical name for the non-production VM."
  default     = "llm-gateway-non-prod"
}

variable "vm_machine_type_name" {
  type        = string
  description = "Exact STACKIT machine type name for the GPU instance."
  # default     = "n2.14d.g1" do NOT create servers as long as the remote state issue is NOT fixed
}

variable "bootstrap_ssh_user" {
  type        = string
  description = "Unix user that receives the bootstrap SSH key via cloud-init."
  default     = "ubuntu"
}

variable "bootstrap_ssh_public_key" {
  type        = string
  description = "Primary deployer SSH public key injected into cloud-init."
  sensitive   = true
  default     = ""
}

variable "boot_volume_size_gb" {
  type        = number
  description = "Persistent boot volume size in GiB."
  default     = 100
}

variable "boot_volume_performance_class" {
  type        = string
  description = "STACKIT block-storage performance class for the boot volume."
  default     = "storage_premium_perf6"
}

variable "ubuntu_image_name_regex" {
  type        = string
  description = "Regex used to select the Ubuntu 26.04 base image."
  default     = "^Ubuntu 26\\.04"
}
