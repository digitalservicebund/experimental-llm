variable "region" {
  type        = string
  description = "STACKIT region used for IAM resources."
  default     = "eu01"
}

variable "project_id" {
  type        = string
  description = "STACKIT project ID that should trust this GitHub repository."
}

variable "name" {
  type        = string
  description = "Name of the STACKIT service account created for GitHub Actions Terraform runs."
  default     = "gh-terraform"
}

variable "github_repository" {
  type        = string
  description = "GitHub repository claim prefix accepted by STACKIT. This repository was created after 2026-07-15, so the immutable owner/repo ID format is used by default."
  default     = "digitalservicebund@72971514/experimental-llm@1361178104"
}

variable "github_subjects" {
  type        = list(string)
  description = "Allowed GitHub Actions OIDC subject suffixes. The default permits runs from the main branch only."
  default = [
    "ref:refs/heads/main",
  ]
}

variable "additional_assertions" {
  type = list(object({
    item     = string
    operator = string
    value    = string
  }))
  description = "Optional extra OIDC assertions to further restrict which workflows may assume the service account."
  default = [
    {
      item     = "job_workflow_ref"
      operator = "equals"
      value    = "digitalservicebund/experimental-llm/.github/workflows/terraform-apply.yml@refs/heads/main"
    },
  ]
}

variable "roles" {
  type        = list(string)
  description = "Existing STACKIT roles to assign. Leave empty by default so access is granted via the generated least-privilege custom role from var.permissions."
  default     = []
}

variable "permissions" {
  type        = list(string)
  description = "Least-privilege permissions for the generated custom role used by this repository's Terraform workflow. Covers the current llm-gateway module in both non-prod and prod."
  default = [
    "iaas.image.get",
    "iaas.image.list",
    "iaas.machine-type.get",
    "iaas.machine-type.list",
    "iaas.network.get",
    "iaas.nic.create",
    "iaas.nic.delete",
    "iaas.nic.get",
    "iaas.nic.list",
    "iaas.nic.update",
    "iaas.public-ip.create",
    "iaas.public-ip.delete",
    "iaas.public-ip.get",
    "iaas.public-ip.list",
    "iaas.public-ip.update",
    "iaas.security-group.create",
    "iaas.security-group.delete",
    "iaas.security-group.get",
    "iaas.security-group.list",
    "iaas.security-group.rule.create",
    "iaas.security-group.rule.delete",
    "iaas.security-group.rule.get",
    "iaas.security-group.rule.list",
    "iaas.security-group.rule.update",
    "iaas.security-group.update",
    "iaas.server.create",
    "iaas.server.delete",
    "iaas.server.get",
    "iaas.server.list",
    "iaas.server.update",
    "iaas.volume.create",
    "iaas.volume.delete",
    "iaas.volume.get",
    "iaas.volume.list",
    "iaas.volume.update",
  ]
}

