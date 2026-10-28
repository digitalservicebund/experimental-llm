# experimental-llm

[Documentation for agents](AGENTS.md)

Ansible configuration for an existing Ubuntu 26.04 NVIDIA server running a
native Python vLLM OpenAI-compatible API with a configurable Hugging Face model,
fronted by a LiteLLM Proxy for authentication and metrics.

## Terraform

There are two separate Terraform configurations with different execution models:

- **`terraform/bootstrap-github-oidc/`** — one-time bootstrap that creates the
  GitHub OIDC/workload identity federation used by the main stack. Run this
  **locally** (see upstream guides below) and push the resulting state files
  (`terraform.tfstate*`) to the repository afterwards, since no CI job manages
  this state.
- **`terraform/non-prod/`** (and any future STACKIT stack) — runs **only** from
  GitHub Actions (`.github/workflows/terraform.yml`) via OIDC. Never apply this
  stack locally.

For bootstrap and setup details, use the upstream guides:

- https://platform-docs.prod.tech.digitalservice.dev/stackit-user-docs/how-to-guides/terraform-github-actions
- https://github.com/digitalservicebund/terraform-modules/tree/main/stackit-identity-federation

Local Terraform runs (bootstrap only) can authenticate with a short-lived
service account token:

```bash
export STACKIT_SERVICE_ACCOUNT_TOKEN=$(stackit auth get-access-token)
```

## Workstation setup

On macOS, install the control-node tools with Homebrew and the official Ansible
`pipx` method. Pin the pipx environment to Python 3.14: `ansible-core` 2.21 does
not support Python 3.15, which may already be installed and used as default Python.

```bash
brew install pipx python@3.14
pipx ensurepath
# Open a new terminal after ensurepath, if pipx is not yet on PATH.
pipx install --python "$(brew --prefix python@3.14)/bin/python3.14" --include-deps ansible-core==2.21.3
ansible --version  # should report python version = 3.14.x
brew install 1password-cli
op --version
```

To run the same static checks locally as GitHub Actions, inject the linters into
the `ansible-core` pipx environment. Inject yamllint first and separately:
ansible-lint pulls it in as a dependency, and pipx then skips exposing the
yamllint command.

```bash
pipx inject --include-apps ansible-core yamllint
pipx inject --include-apps ansible-core ansible-lint
ansible-lint --version
yamllint --version
```

Install the project collections. The local
`ansible.cfg` configures the inventory and role path:

```bash
ansible-galaxy collection install -r requirements.yml
```

The repository keeps Python control-node dependencies in
`ansible/requirements.txt` (used as the pip cache key in CI) and Ansible Galaxy
collections in `ansible/requirements.yml`. `pipx ensurepath` only updates the
shell `PATH`, so it stays out of `requirements.txt`.

From the repository root, use the shared `do` command runner to lint, apply Ansible,
and port-forward the LiteLLM API locally. To see available commands, run:

```bash
./do
```


### Secrets

Secrets are kept in 1Password and injected with `op`.

Ask to be added to the 1Password vault.
Open and unlock the 1Password desktop app, enable **Settings > Developer >
Integrate with 1Password CLI**, and run `op vault list` once to confirm the CLI
can authenticate through the desktop app.

Add SSH host key fingerprint to `known_hosts` before running Ansible so the
connection is not prompted for interactive host key verification:

```bash
op run --env-file=./ansible/.env.op -- sh -c 'ssh-keyscan -H "$SERVER_PUBLIC_IP" >> ~/.ssh/known_hosts'
```

Verify the printed fingerprint against the one shown in the STACKIT console (or
another trusted out-of-band source) before trusting it.

### LiteLLM Proxy and Virtual Keys

The deployment runs three services in two places:

1. **vLLM** on the GPU VM, `127.0.0.1:8000` (internal only) — serves the model.
   The VM only exists while scaled up via the *Scale Up* workflow; Ansible
   installs vLLM as a systemd service.
2. **LiteLLM Proxy** in Kubernetes, namespace `llm-gateway-internal`, service
   `litellm` on port 4000 — provides authentication and metrics on top of vLLM
3. **PostgreSQL** in Kubernetes, same namespace — stores LiteLLM Virtual Keys
   and spend/usage metrics

LiteLLM and PostgreSQL are deployed from `manifests/`. The VM and the Terraform
module are still named `llm-gateway` because all three services used to run on
the VM.

Clients access the LiteLLM proxy via `kubectl port-forward`. The proxy uses **Virtual Keys**
for authentication instead of a static key.

#### Generating Virtual Keys

Once LiteLLM is running in Kubernetes, generate Virtual Keys for your users.
Port-forward the API and use the master key to generate them:

```bash
# Terminal 1: Forward the LiteLLM API locally
./do port-forward

# Terminal 2: Generate a Virtual Key using the master key and ./do
./do generate-key my_key_alias
```

Each request returns a JSON response with the generated key. Store these keys securely.

#### Using Virtual Keys

Users authenticate using the generated Virtual Keys against the LiteLLM proxy:

```bash
curl http://127.0.0.1:4000/v1/models \
  -H 'Authorization: Bearer <generated_virtual_key>'
```

Virtual Keys are:
- Stored in PostgreSQL in Kubernetes, alongside spend/usage metrics
- Revocable (can be deleted or disabled)
- More secure than static keys (can be rotated without redeploying)

#### Using LiteLLM without the vLLM VM

LiteLLM runs independently of the GPU VM. While the VM is scaled down you can
still port-forward, check the proxy, generate keys, and list models. Only
requests that reach the model, such as `/v1/chat/completions`, need the VM.

```bash
kubectl get pods -n llm-gateway-internal       # litellm and litellm-postgres pods
curl http://127.0.0.1:4000/health/liveliness   # proxy liveness, no key needed
```

### Open WebUI

Open WebUI uses one shared Virtual Key with the alias `open-webui` for all of
its users. Users log in to Open WebUI with their own accounts; Open WebUI then
calls LiteLLM with this key. Generate it once with
`./do generate-key open-webui` and store it in 1Password as
`open-webui-api-key`, next to the LiteLLM master key. In the cluster, Open WebUI
reads the key and its session secret from the `open-webui-secrets` Secret,
which External Secrets creates.

#### Testing locally

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

### Checking service status and logs

**vLLM** runs as the `vllm` systemd service on the GPU VM and logs only to the
journal. From an SSH session on the server (`./do login`):

```bash
systemctl status vllm

journalctl -u vllm -f                 # follow live
journalctl -u vllm -n 200 --no-pager  # last N lines
journalctl -u vllm -p err -e          # errors only
```

**LiteLLM Proxy** and **PostgreSQL** run in Kubernetes:

```bash
kubectl get pods -n llm-gateway-internal
kubectl logs -n llm-gateway-internal deploy/litellm -f
kubectl logs -n llm-gateway-internal statefulset/litellm-postgres-postgresql -f
```

## Upstream references

- [Ansible installation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [vLLM GPU installation](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/)
- [Qwen2.5-Coder-32B-Instruct model card](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct)
- [STACKIT documentation](https://docs.stackit.cloud/)
