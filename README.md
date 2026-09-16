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
`pipx` method:

```bash
brew install pipx
pipx ensurepath
# Open a new terminal after ensurepath, if pipx is not yet on PATH.
pipx install --include-deps ansible-core==2.21.3
ansible --version
brew install 1password-cli
op --version
```

To run the same static checks locally as GitHub Actions, inject the linters into
the Ansible pipx environment:

```bash
pipx inject --include-apps ansible ansible-lint yamllint
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
and open an SSH tunnel to the server. To see available commands, run:

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
op run --env-file=.env.op -- sh -c 'ssh-keyscan -H "$SERVER_PUBLIC_IP" >> ~/.ssh/known_hosts'
```

Verify the printed fingerprint against the one shown in the STACKIT console (or
another trusted out-of-band source) before trusting it.

### LiteLLM Proxy and Virtual Keys

The deployment runs three services:

1. **vLLM** on `127.0.0.1:8000` (internal only) — serves the model
2. **PostgreSQL** on `127.0.0.1:5432` (internal only) — stores LiteLLM Virtual
   Keys and spend/usage metrics
3. **LiteLLM Proxy** on `127.0.0.1:4000` (internal only) — provides
   authentication and metrics on top of vLLM

Clients access the LiteLLM proxy via SSH tunnel. The proxy uses **Virtual Keys**
for authentication instead of a static key.

#### Generating Virtual Keys

After the Ansible playbook completes and LiteLLM is running, generate Virtual
Keys for your users. Open an SSH tunnel and use the master key to generate them:

```bash
# Terminal 1: Open SSH tunnel to LiteLLM
./do tunnel

# Terminal 2: Generate a Virtual Key using the master key and ./do
./do generate-keys my_key_alias
```

Each request returns a JSON response with the generated key. Store these keys securely.

#### Using Virtual Keys

Users authenticate using the generated Virtual Keys against the LiteLLM proxy:

```bash
curl http://127.0.0.1:4000/v1/models \
  -H 'Authorization: Bearer <generated_virtual_key>'
```

Virtual Keys are:
- Stored in PostgreSQL on the server, alongside spend/usage metrics
- Revocable (can be deleted or disabled)
- More secure than static keys (can be rotated without redeploying)

### Checking service status and logs

**vLLM** (`vllm`), **PostgreSQL** (`postgresql`), and **LiteLLM Proxy**
(`litellm`) each run as systemd services. vLLM and LiteLLM log only to the
journal. From an SSH session on the server:

```bash
systemctl status vllm postgresql litellm

journalctl -u vllm -f                 # follow live
journalctl -u vllm -n 200 --no-pager  # last N lines
journalctl -u vllm -p err -e          # errors only
```

### SSH tunnel for local clients (for example opencode)

`./do tunnel` opens a local tunnel to the server; by default it forwards
`127.0.0.1:4000` (LiteLLM proxy). Customize the local and remote ports with environment variables:

```bash
VLLM_TUNNEL_LOCAL_PORT=8000 \
VLLM_TUNNEL_REMOTE_PORT=8000 \
./do tunnel
```

Then point your OpenAI-compatible client (including opencode) at
`http://127.0.0.1:4000/v1` and authenticate with your Virtual Key as the
`Authorization: Bearer` token.

## Upstream references

- [Ansible installation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [vLLM GPU installation](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/)
- [Qwen2.5-Coder-32B-Instruct model card](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct)
- [STACKIT documentation](https://docs.stackit.cloud/)
