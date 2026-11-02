variable "project_id" {
  type        = string
  description = "GCP project that serves the Vertex AI models."
  default     = "internal-llm-513109"
}

variable "kubernetes_issuer" {
  type        = string
  description = "ServiceAccount token issuer of the SKE cluster (.status.serviceAccountIssuer). Google fetches its public keys from the issuer's discovery document."
  default     = "https://discovery.ske.eu01.stackit.cloud/projects/b7c7d43cbe/shoots/08273043-b4eb-438e-b8db-6e9a432d63ee/issuer"
}

variable "kubernetes_namespace" {
  type        = string
  description = "Namespace of the LiteLLM deployment."
  default     = "llm-gateway-internal"
}

variable "kubernetes_service_account" {
  type        = string
  description = "Kubernetes ServiceAccount of LiteLLM. The only identity allowed to use the workload identity provider."
  default     = "litellm"
}
