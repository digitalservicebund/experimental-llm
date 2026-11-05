# Google Vertex AI setup

How LiteLLM gets access to Vertex AI through Workload Identity Federation. For
an overview, see the [README](../README.md#google-vertex-ai).

## Setup

1. Install the gcloud CLI and log in. Terraform uses your Application Default
   Credentials.

   ```bash
   brew install --cask gcloud-cli
   gcloud auth login
   gcloud auth application-default login
   ```

2. Apply `terraform/gcp-vertex-ai/`. It enables the APIs, creates the service
   account `litellm` with the role Vertex AI User, creates the workload
   identity pool `stackit-ske` with the provider `llm-gateway` for the SKE
   cluster's issuer, and lets the Kubernetes ServiceAccount `litellm`
   impersonate the service account. Billing must be enabled on the project.

   ```bash
   terraform -chdir=terraform/gcp-vertex-ai init
   terraform -chdir=terraform/gcp-vertex-ai apply
   ```

   If the cluster's issuer changes, update `kubernetes_issuer` in
   `variables.tf` and apply again. The issuer is in the cluster status:
   `stackit ske cluster describe -p <stackit-project-id> <cluster-name> -o json | jq -r .status.serviceAccountIssuer`.

3. LiteLLM is configured in this repository:

   - `manifests/base/litellm-chart-values.yaml`: model list, the
     ServiceAccount `litellm`, the projected token volume, and
     `GOOGLE_APPLICATION_CREDENTIALS`
   - `manifests/base/gcp-workload-identity.yaml`: the credential configuration
     (ConfigMap). It contains no secret.
   - `manifests/base/network-policies.yaml`: `allow-litellm-https-egress`
     allows outbound HTTPS. LiteLLM does not need to be reachable from the
     internet.

4. Test through the LiteLLM API. Authentication errors from Google show up in
   `kubectl logs -n llm-gateway-internal deploy/litellm`.

   ```bash
   ./do port-forward
   curl http://127.0.0.1:4000/v1/chat/completions \
     -H "Authorization: Bearer <virtual-key>" \
     -H 'Content-Type: application/json' \
     -d '{"model":"gemini-3.6-flash","messages":[{"role":"user","content":"Hello"}]}'
   ```

Gemini models work without activation. Partner models such as Claude must be
enabled once in Model Garden in the Google Cloud console.

## Docs

- [Configure Workload Identity Federation with Kubernetes](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-kubernetes):
  what the Terraform stack and the manifests implement, with service account
  impersonation
- [STACKIT: Use Workload Identity](https://docs.stackit.cloud/products/runtime/kubernetes-engine/how-tos/workload-identity/):
  the SKE cluster's issuer
- [Set up Application Default Credentials](https://docs.cloud.google.com/docs/authentication/provide-credentials-adc)
- [Use partner models](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/partner-models/use-partner-models)
- [LiteLLM: Vertex AI](https://docs.litellm.ai/docs/providers/vertex)
