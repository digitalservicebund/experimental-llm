# experimental-llm

[Documentation for agents](AGENTS.md)

LiteLLM Proxy and Open WebUI on STACKIT Kubernetes. LiteLLM serves models from
Google Vertex AI and provides authentication and metrics.

## Terraform

There are separate Terraform configurations with different execution models:

- **`terraform/bootstrap-github-oidc/`** — one-time bootstrap that creates the
  GitHub OIDC/workload identity federation used by the main stack. Run this
  **locally** (see upstream guides below).
- **`terraform/bootstrap-secrets-manager/`** — one-time bootstrap for the
  STACKIT Secrets Manager that External Secrets reads from, and its users for
  External Secrets and Terraform. Run this **locally**.
- **`terraform/non-prod/`** (and any future STACKIT stack) — the STACKIT DNS
  zone `experimental-llm.digitalservice.dev`. Runs **only** from GitHub Actions
  via OIDC: after merging, start the *Terraform Apply* workflow manually. Never
  apply this stack locally.
- **`terraform/gcp-vertex-ai/`** — Google Cloud resources for Vertex AI (see
  [Google Vertex AI](#google-vertex-ai)). Run this **locally** with your Google
  account.

For bootstrap and setup details, use the upstream guides:

- https://platform-docs.prod.tech.digitalservice.dev/stackit-user-docs/how-to-guides/terraform-github-actions
- https://github.com/digitalservicebund/terraform-modules/tree/main/stackit-identity-federation

The bootstrap stacks authenticate against STACKIT with a short-lived service
account token:

```bash
export STACKIT_SERVICE_ACCOUNT_TOKEN=$(stackit auth get-access-token)
```

All stacks keep their state in the STACKIT Object Storage bucket
`self-hosted-llm-terraform-state`, each under its own key. Never commit state
files: they can contain passwords in plain text. Terraform reads the bucket
credentials from these environment variables:

```bash
export AWS_ACCESS_KEY_ID="op://<Employee or Team Vault>/<state bucket name> credentials/ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="op://<Employee or Team Vault>/<state bucket name> credentials/SECRET_ACCESS_KEY"
```

## Workstation setup

On macOS, install the 1Password CLI with Homebrew:

```bash
brew install 1password-cli
op --version
```

From the repository root, use the shared `do` command runner to port-forward
LiteLLM and Open WebUI and to generate Virtual Keys. To see available commands,
run:

```bash
./do
```

### Secrets

Secrets are kept in 1Password and injected with `op`.

Ask to be added to the 1Password vault.
Open and unlock the 1Password desktop app, enable **Settings > Developer >
Integrate with 1Password CLI**, and run `op vault list` once to confirm the CLI
can authenticate through the desktop app.

## LiteLLM Proxy and Virtual Keys

The deployment runs three services in Kubernetes, namespace
`llm-gateway-internal`, all deployed from `manifests/`:

1. **LiteLLM Proxy**, service `litellm` on port 4000 — provides authentication
   and metrics in front of the models on Google Vertex AI
2. **PostgreSQL** — stores LiteLLM Virtual Keys and spend/usage metrics
3. **Open WebUI**, service `open-webui` on port 80 — chat interface that uses
   LiteLLM with its own Virtual Key

Clients access the LiteLLM proxy via `kubectl port-forward`. The proxy uses **Virtual Keys**
for authentication instead of a static key.

### Generating Virtual Keys

Once LiteLLM is running in Kubernetes, generate Virtual Keys for your users.
Port-forward the API and use the master key to generate them:

```bash
# Terminal 1: Forward the LiteLLM API locally
./do port-forward

# Terminal 2: Generate a Virtual Key using the master key and ./do
./do generate-key my_key_alias
```

Each request returns a JSON response with the generated key. Store these keys securely.

### Using Virtual Keys

Users authenticate using the generated Virtual Keys against the LiteLLM proxy:

```bash
curl http://127.0.0.1:4000/v1/models \
  -H 'Authorization: Bearer <generated_virtual_key>'
```

## Open WebUI

Open WebUI uses one shared Virtual Key for all of its users. Users log in to
Open WebUI with their own accounts; Open WebUI then calls LiteLLM with this key.
The key is stored only in the STACKIT Secrets Manager, in the secret
`open-webui-secrets` (property `litellm-api-key`). To replace it, generate a new
one with `./do generate-key <alias>`, write it there, and delete the old key. In
the cluster, Open WebUI reads the key and its session secret from the
`open-webui-secrets` Secret, which External Secrets creates.

### Testing locally

Run Open WebUI in Docker against the LiteLLM API in the cluster.
`./do webui-local` creates a temporary Virtual Key with the master key from
1Password; the key expires after 8 hours. Login is disabled for the local
instance:

```bash
# Terminal 1: Forward the LiteLLM API locally
./do port-forward

# Terminal 2: Start Open WebUI on http://localhost:8080
./do webui-local
```

### Using the cluster deployment

Open WebUI is available at https://experimental-llm.dev.tech.digitalservice.dev.
This is reachable from the internet, but only meant to be shared within
DigitalService.

You can also reach it through a port-forward:

```bash
./do port-forward-webui   # Open WebUI on http://localhost:8080
```

Users log in with Open WebUI accounts. The first account created on a fresh
deployment becomes the admin, so create it right after the first deployment.
Self-signup is disabled; the admin adds all other users in the Admin Panel.

### Spend and budgets per user

Open WebUI sends the signed-in user's email to LiteLLM
(`ENABLE_FORWARD_USER_INFO_HEADERS`). LiteLLM tracks each email as an end user
(customer) with its own spend. Every user gets the budget `open-webui-user`
(`max_end_user_budget_id`), and LiteLLM rejects their requests once they exceed
it. Create the budget once, for example 10 USD per 30 days:

```bash
# Terminal 1: Forward the LiteLLM API locally
./do port-forward

# Terminal 2
./do create-budget open-webui-user 10 30d
./do user-spend   # spend in USD per user
```

To change the amount, use `/budget/update`. To give a single user a different
budget, create another budget and assign it with `/customer/update`.

Docs:

- [LiteLLM: Open WebUI](https://docs.litellm.ai/docs/tutorials/openweb_ui)
- [LiteLLM: Budgets](https://docs.litellm.ai/docs/proxy/users)

## Google Vertex AI

LiteLLM serves models from Vertex AI through the EU
multi-region endpoint (`vertex_location: eu`). Our organization policy
disallows API keys, so LiteLLM authenticates with [Workload Identity Federation.](https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-kubernetes)
The models are listed in `manifests/base/litellm-chart-values.yaml`.

The GCP project is `internal-llm-513109` (project number `530198116931`). For
setup and troubleshooting, see [docs/vertex-ai.md](docs/vertex-ai.md).

## Checking service status and logs

```bash
kubectl get pods -n llm-gateway-internal
kubectl logs -n llm-gateway-internal deploy/litellm -f
kubectl logs -n llm-gateway-internal statefulset/litellm-postgres-postgresql -f
kubectl logs -n llm-gateway-internal statefulset/open-webui -f
curl http://127.0.0.1:4000/health/liveliness   # LiteLLM liveness via ./do port-forward, no key needed
```

## Former GPU VM

[PR #11](https://github.com/digitalservicebund/experimental-llm/pull/11)
removed the GPU VM (vLLM with Qwen2.5-Coder), its Terraform module and the
Ansible configuration. To bring it back, restore the removed files from the PR.

## Open topics

- SSO: users log in with local Open WebUI accounts. Google SSO is possible but
  not configured yet.
- Usage limits: no budget is configured yet, see
  [Spend and budgets per user](#spend-and-budgets-per-user).
- Production: Open WebUI should run with multiple replicas. That needs Postgres
  instead of SQLite, Redis, shared file storage (S3) and an external vector DB.
  Docs: [Open WebUI: Scaling](https://docs.openwebui.com/getting-started/advanced-topics/scaling)
- Claude models: enable in Model Garden and accept Anthropic's terms, check the
  EU quota, verify the model IDs, then uncomment them in
  `manifests/base/litellm-chart-values.yaml`.
- Embeddings: Open WebUI uses `gemini-embedding-2` for now. EmbeddingGemma 2
  has no pay-per-token offering on Vertex AI. Options: deploy it to a Vertex AI
  endpoint in `europe-west3` (billed per hour) or run it in our cluster.
