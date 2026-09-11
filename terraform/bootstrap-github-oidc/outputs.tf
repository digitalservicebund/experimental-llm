locals {
  normalized_github_repository = trimprefix(var.github_repository, "repo:")
}

output "service_account_email" {
  description = "Email address to store in the GitHub repository variable STACKIT_SERVICE_ACCOUNT_EMAIL."
  value       = module.github_actions_identity_federation.service_account_email
}

output "expected_oidc_subjects" {
  description = "Expected GitHub OIDC sub claims for this repository. Compare these values with Settings -> Actions -> General -> OIDC in GitHub."
  value = [
    for subject in var.github_subjects : "repo:${local.normalized_github_repository}:${subject}"
  ]
}

output "configured_workflow_assertions" {
  description = "Additional OIDC assertions configured for every federated identity provider."
  value       = var.additional_assertions
}

