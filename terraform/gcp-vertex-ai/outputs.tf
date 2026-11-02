output "service_account_email" {
  description = "GCP service account LiteLLM impersonates. Must match service_account_impersonation_url in manifests/base/gcp-workload-identity.yaml."
  value       = google_service_account.litellm.email
}

output "workload_identity_provider" {
  description = "Resource name of the provider. Must match the audience in manifests/base/gcp-workload-identity.yaml and manifests/base/litellm-chart-values.yaml."
  value       = google_iam_workload_identity_pool_provider.llm_gateway.name
}
