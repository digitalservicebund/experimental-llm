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

variable "secrets_manager_name" {
  type        = string
  description = "Name of the STACKIT Secrets Manager instance for non-production LiteLLM secrets."
  default     = "experimental-llm-non-prod-secrets"
}

variable "kubernetes_namespace" {
  type        = string
  description = "Kubernetes namespace used in the External Secrets SecretStore and Secret manifest outputs."
  default     = "llm-gateway-internal"
}
