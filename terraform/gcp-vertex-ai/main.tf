locals {
  # Vertex AI itself, plus the APIs Workload Identity Federation needs.
  services = toset([
    "aiplatform.googleapis.com",
    "iam.googleapis.com",
    "cloudresourcemanager.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
  ])

  kubernetes_subject = "system:serviceaccount:${var.kubernetes_namespace}:${var.kubernetes_service_account}"
}

resource "google_project_service" "services" {
  for_each = local.services

  service            = each.key
  disable_on_destroy = false
}

resource "google_service_account" "litellm" {
  account_id   = "litellm"
  display_name = "LiteLLM (STACKIT SKE)"
  description  = "LiteLLM in ${var.kubernetes_namespace}, via Workload Identity Federation"
}

resource "google_project_iam_member" "litellm_vertex_ai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = google_service_account.litellm.member
}

resource "google_iam_workload_identity_pool" "stackit_ske" {
  workload_identity_pool_id = "stackit-ske"
  display_name              = "STACKIT SKE"

  depends_on = [google_project_service.services]
}

resource "google_iam_workload_identity_pool_provider" "llm_gateway" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.stackit_ske.workload_identity_pool_id
  workload_identity_pool_provider_id = "llm-gateway"

  attribute_mapping = {
    "google.subject" = "assertion.sub"
  }
  attribute_condition = "assertion.sub == '${local.kubernetes_subject}'"

  # Without allowed_audiences, the token audience must be this provider's
  # resource name, as set in manifests/base/litellm-chart-values.yaml.
  oidc {
    issuer_uri = var.kubernetes_issuer
  }
}

resource "google_service_account_iam_member" "litellm_workload_identity_user" {
  service_account_id = google_service_account.litellm.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principal://iam.googleapis.com/${google_iam_workload_identity_pool.stackit_ske.name}/subject/${local.kubernetes_subject}"
}

# Created manually with gcloud before this configuration existed.
import {
  for_each = local.services

  to = google_project_service.services[each.key]
  id = "${var.project_id}/${each.key}"
}

import {
  to = google_service_account.litellm
  id = "projects/${var.project_id}/serviceAccounts/litellm@${var.project_id}.iam.gserviceaccount.com"
}

import {
  to = google_project_iam_member.litellm_vertex_ai_user
  id = "${var.project_id} roles/aiplatform.user serviceAccount:litellm@${var.project_id}.iam.gserviceaccount.com"
}
