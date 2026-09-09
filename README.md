# experimental-llm

Ansible configuration for an existing Ubuntu 26.04 NVIDIA server running a
native Python vLLM OpenAI-compatible API with a configurable Hugging Face model.

## Important prerequisite

`Qwen/Qwen2.5-Coder-32B-Instruct` is a 32.5B-parameter BF16 model. Confirm the
STACKIT server has a compatible GPU and enough VRAM before applying the
playbook. The role installs pinned Ubuntu NVIDIA server driver packages and can
reboot automatically when the driver changes.

The NVIDIA kernel driver is required. Verify it on the server with
`nvidia-smi`. A CUDA toolkit installation is normally not required when using a
compatible prebuilt vLLM/PyTorch wheel; the driver must still be new enough for
the CUDA runtime selected by `vllm_torch_index`. Install or upgrade the driver
using the STACKIT/Ubuntu GPU image documentation if `nvidia-smi` is unavailable,
then reboot and verify it before running Ansible.

### NVIDIA driver change procedure

Treat the NVIDIA driver as part of the server platform, not as an ordinary
application package. Before changing it:

1. Record `nvidia-smi`, `uname -a`, `ubuntu-drivers devices`, the installed
	packages from `dpkg -l | grep -E 'nvidia|cuda'`, and the current vLLM service
	status.
2. Confirm the exact GPU model, Ubuntu kernel, NVIDIA driver branch, and CUDA
	runtime required by the selected vLLM/PyTorch version. Do not choose a driver
	merely because it is the newest package in APT.
3. Confirm console/SSH access, a recent server backup or rebuild path, and a
	maintenance window. A driver change can require a reboot and can leave the
	machine without GPU access if DKMS fails to build for the active kernel.
4. Prefer a STACKIT image that already contains a validated driver. If installing
	manually, use the Ubuntu/STACKIT-supported package method and install only the
	specific driver branch selected in step 2. Do not mix NVIDIA `.run` installers
	with distribution packages.
5. Reboot explicitly, then verify `nvidia-smi`, `lsmod | grep nvidia`, and the
	kernel/DKMS status before starting vLLM. Run a small inference smoke test and
	inspect `journalctl -u vllm`.

The Ansible playbook installs pinned NVIDIA server driver packages, then checks
`nvidia-smi` and stops if the driver is still unavailable. It still does not
install a desktop graphics stack or use NVIDIA `.run` installers.

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

The repository keeps Python control-node dependencies in
`ansible/requirements.txt`. GitHub Actions installs that file and uses it as the
pip cache key. The separate `ansible/requirements.yml` file contains Ansible
Galaxy collections.

`pipx ensurepath` is not a Python dependency. It updates the shell `PATH` so
commands installed by pipx can be found, so it belongs in workstation setup
instructions rather than in `requirements.txt`.

From the repository root, enter the `ansible` directory once. Run all Ansible
commands below from that directory:

```bash
cd ansible
./lint.sh
```

Open and unlock the 1Password desktop app, enable **Settings > Developer >
Integrate with 1Password CLI**, and run `op vault list` once to confirm the CLI
can authenticate through the desktop app.

Install the project collections. The local
`ansible.cfg` configures the inventory and role path:

```bash
ansible-galaxy collection install -r requirements.yml
```

Edit `inventories/production/hosts.yml` with the public IP and the SSH key used
for the existing `ubuntu` login.

Set a tested, pinned `vllm_version` and matching CUDA PyTorch index in
`inventories/production/group_vars/all.yml`.

Store the server's public IP in 1Password alongside the other secrets, then add
its SSH host key fingerprint to `known_hosts` before running Ansible so the
connection is not prompted for interactive host key verification:

```bash
op run --env-file=.env.op -- sh -c 'ssh-keyscan -H "$SERVER_PUBLIC_IP" >> ~/.ssh/known_hosts'
```

Verify the printed fingerprint against the one shown in the STACKIT console (or
another trusted out-of-band source) before trusting it.

### Secrets

Ansible Vault and HashiCorp Vault are different things. Ansible Vault is merely
local file encryption; it is not the STACKIT service and it is not used by this
repository.

Use STACKIT Secrets Manager as the source of truth for `LLM_API_KEY` and, if
needed, `HF_TOKEN`. STACKIT documents a Vault-compatible API and AppRole
authentication for automated workloads. Retrieve those values just before the
Ansible run and expose them to Ansible only as process environment variables.
Do not commit a fetched secret, a token file, or a generated `.env` file.

On workstations, keep the STACKIT Secret Manager AppRole credentials or an
approved local development secret in 1Password and use `op` to inject it for the
duration of the command. For example:

```bash
LLM_API_KEY='op://Work/llm-api-key/credential' \
HF_TOKEN='op://Work/huggingface-token/credential' \
op run -- ansible-playbook playbooks/site.yml \
	-i inventories/production/hosts.yml
```

For the production flow, replace the direct 1Password secret references with a
small local wrapper that authenticates to STACKIT Secrets Manager using the
approved AppRole/API method, reads the two secret fields, exports them as
`LLM_API_KEY` and `HF_TOKEN`, and `exec`s the same Ansible command. Keep the
wrapper free of secret values; only its secret paths and non-sensitive endpoint
configuration belong in Git. The exact STACKIT project, instance, secret paths,
and AppRole setup are environment-specific and should be filled in from the
STACKIT Secrets Manager configuration rather than guessed here.

The API key is required because the server has a public IP. The STACKIT security
group should still restrict port 8000 to trusted client networks, or an
authenticated TLS reverse proxy should be used in front of it.

Validate connectivity and the playbook before changing the server:

```bash
ansible-inventory --graph
ansible llm_servers -i inventories/production/hosts.yml -m ping
ansible-playbook playbooks/site.yml --syntax-check
LLM_API_KEY='op://Work/llm-api-key/credential' \
op run -- ansible-playbook playbooks/site.yml \
	-i inventories/production/hosts.yml --check --diff
LLM_API_KEY='op://Work/llm-api-key/credential' \
op run -- ansible-playbook playbooks/site.yml \
	-i inventories/production/hosts.yml
```

The first run installs Python 3, creates `/opt/vllm/venv`, installs the pinned
vLLM package, downloads the model on first start, and creates a systemd service.
It does not install Ansible on the server. After deployment, test the API from
the server:

```bash
curl http://127.0.0.1:8000/v1/models \
  -H 'Authorization: Bearer YOUR_API_KEY'
sudo journalctl -u vllm -f
```

Use a dedicated vLLM version and CUDA wheel combination that has been tested on
the actual NVIDIA driver. The model is 32.5B parameters, so available VRAM and
the selected context length are operational constraints; a single GPU may need
quantization or tensor parallelism across multiple GPUs.

## GitHub Actions validation

The repository includes [ansible-validate.yml](.github/workflows/ansible-validate.yml).
There is nothing to install locally for this workflow. Push the repository to
GitHub with the workflow committed, then GitHub Actions will automatically run
the YAML, syntax, inventory, task-listing, and Ansible Lint checks on pushes to
`main` and on pull requests that change `ansible/**`.

The workflow does not have server credentials and never runs a normal playbook
against a host. It only uses `--syntax-check`, `--list-hosts`, and
`--list-tasks`, which do not connect to managed servers.

GitHub Actions and local development both execute `ansible/lint.sh` from the
`ansible` working directory. The script
installs the declared Ansible collections, validates YAML, checks playbook
syntax, resolves the inventory, lists hosts and tasks, and runs Ansible Lint.
All of these checks are non-connecting; they never apply the playbook to a
server.

## Upstream references

- [Ansible installation](https://docs.ansible.com/ansible/latest/installation_guide/intro_installation.html)
- [vLLM GPU installation](https://docs.vllm.ai/en/stable/getting_started/installation/gpu/)
- [Qwen2.5-Coder-32B-Instruct model card](https://huggingface.co/Qwen/Qwen2.5-Coder-32B-Instruct)
- [STACKIT documentation](https://docs.stackit.cloud/)
- [STACKIT Secrets Manager AppRole](https://docs.stackit.cloud/products/security/secrets-manager/how-tos/configure-and-use-approles/)