variable "region" {
  type        = string
  description = "STACKIT region for non-production infrastructure."
  default     = "eu01"
}

variable "project_id" {
  type        = string
  description = "STACKIT project ID that owns the non-production resources."
  default     = "8f43ea04-9012-4cd7-8d14-d4e202c9ddc0"
}

variable "backend_access_key_id" {
  type        = string
  sensitive   = true
  description = "Access key for the backend object bucket."
}

variable "backend_secret_access_key" {
  type        = string
  sensitive   = true
  description = "Secret key for the backend object bucket."
}

variable "dns_name" {
  type        = string
  description = "Name of the STACKIT DNS zone."
  default     = "experimental-llm.digitalservice.dev"
}

variable "dns_zone_display_name" {
  type        = string
  description = "Human-readable STACKIT DNS zone name."
  default     = "Experimental LLM Zone"
}

variable "dns_contact_email" {
  type        = string
  description = "Contact email for the STACKIT DNS zone."
  default     = "platform@digitalservice.bund.de"
}

variable "dns_default_ttl" {
  type        = number
  description = "Default TTL for records in the STACKIT DNS zone."
  default     = 1230
}
