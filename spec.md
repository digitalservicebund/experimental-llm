# Specification: Internal LLM Gateway MVP (DigitalService des Bundes)

## 1. Context & Goal
Deploy a 14-day MVP of an internal LLM Gateway on a STACKIT Cloud environment. The objective is to provide a working OpenAI-compatible endpoint to OpenCode, validate the technical feasibility of hosting a baseline model, and collect token usage/performance data to calculate costs. 

**Strict Constraints:** 
- Do not use Docker or containerization. Provision infrastructure with Terraform and configure natively using Ansible. 
- To save costs, the compute instance must be entirely destroyed overnight, but its boot volume must be preserved to avoid reinstalling dependencies and re-downloading the model daily.

## 2. Architecture & Tech Stack
*   **Infrastructure Provisioning:** Terraform (Stateful Volume + Ephemeral Compute).
*   **Configuration Management:** Ansible.
*   **Host Environment:** STACKIT Ephemeral VM with 1x NVIDIA L40S (48GB VRAM) running **Ubuntu 26.04**.
*   **Model Inference:** `vLLM` serving `Qwen/Qwen2.5-Coder-32B-Instruct-AWQ` natively via Python virtual environment.
*   **API Gateway:** `LiteLLM Proxy` natively via Python virtual environment.
*   **Database (Metrics):** Local SQLite DB (LiteLLM default).
*   **Secrets Management:** 1Password CLI (`op`) and `.env.op` files.
*   **CI/CD & Automation:** GitHub Actions (for deployment, scheduled compute lifecycle, health checks, and 1Password IP updates).

## 3. Scope of Work (MVP)

### 3.1. Infrastructure & Networking (Terraform)
*   **Environment Specifics:** Target STACKIT region `EU01` and connect to the existing network `llm` (ID: `7cdd4ee0-cb53-40b7-b8e8-50a324c261f8`).
*   **Decoupled Storage & Compute:** Provision a persistent **100 GB Performance Class 6** Block Storage volume for the OS/boot disk. 
*   **Toggleable Compute:** Provision the STACKIT VM using a variable (e.g., `var.vm_enabled = true/false`). When enabled, boot from the persistent 100 GB volume. When disabled, destroy the VM but retain the volume.
*   **SSH Key Bootstrapping:** Inject a primary automation/deployer SSH public key via `cloud-init` (user-data) upon initial volume creation to guarantee base access. Subsequent user SSH keys will be managed via Ansible.
*   **Networking/Security:** Assign a Public IP to the VM upon creation. Restrict the firewall/security group to **only allow inbound traffic on port 22 (SSH)**.
*   **Outputs:** Output the newly assigned Public IP address.

### 3.2. Host Configuration (Ansible)
Write idempotent Ansible playbooks meant for initial provisioning, continuous configuration updates, and CI/CD integration. 
*   **SSH Key Management:** Use the `ansible.posix.authorized_key` module to manage developer SSH access (adding/removing keys over time).
*   **Drivers & Environment:** Ensure NVIDIA drivers, CUDA toolkit, and Python dependencies are installed.
*   **Secrets Integration:** Read `.env.op` (with 1Password references like `LLM_KEY_1="op://..."`) and resolve them to configure LiteLLM securely.
*   **vLLM Service:** 
    *   Install `vLLM` in a virtual environment.
    *   Create and enable a `systemd` service (`vllm.service`) serving the `Qwen2.5-Coder-32B-Instruct-AWQ` model on port `8000` (bound to `127.0.0.1`). Note: Model weights will be downloaded automatically by vLLM on first startup.
*   **LiteLLM Service:**
    *   Install `litellm[proxy]` in a virtual environment.
    *   Write `config.yaml` to route traffic to `http://127.0.0.1:8000`, utilizing the 3 test keys injected from 1Password.
    *   Configure SQLite database logging for telemetry.
    *   Create and enable a `systemd` service (`litellm.service`) starting the proxy on port `4000` (bound to `127.0.0.1`).
*   **Health-Check Playbook:** Create a dedicated, lightweight Ansible playbook (`healthcheck.yml`) that verifies both `systemd` services are running and that the LiteLLM endpoint returns a 200 OK status on `127.0.0.1:4000/health`.

### 3.3. Scheduled Ephemeral Compute (GitHub Actions)
*   **Scale Down (20:00 CET/CEST, Mon-Fri):** Runs `terraform apply -var="vm_enabled=false"` to completely destroy the GPU instance (stopping billing) while leaving the state and persistent volume intact.
*   **Scale Up (08:00 CET/CEST, Mon-Fri):** 
    1. Runs `terraform apply -var="vm_enabled=true"` to recreate the VM and attach the boot volume.
    2. Runs the Ansible `healthcheck.yml` playbook to verify the gateway successfully recovered and is responding.
    3. Uses the 1Password CLI (authenticated via Service Account token) to update the daily Public IP in the 1Password vault (e.g., updating the item containing `SERVER_PUBLIC_IP="op://z3yr24dkqmdjsvc724nouabjpi/eslyhyeireaxhtopettp7fxbwm/server-public-ip"`).

## 4. Definition of Done (DoD) for the Agent
1.  **Terraform:** Working `.tf` files referencing the `EU01` region, `llm` network, and separated 100 GB Performance Class 6 volume.
2.  **Ansible:** Playbooks (usable locally and in CI) that manage SSH keys, install CUDA/Python, resolve 1Password secrets, configure auto-starting `systemd` services, and provide a standalone health-check validation.
3.  **GitHub Actions:** Cron workflows for `scale-up` and `scale-down` that handle the daily lifecycle, execute the Ansible health check, and successfully update the dynamic Public IP in the 1Password vault.
4.  **`README.md` & `do` Script**:
    *   A brief `README.md` explaining the project architecture and how to query the LiteLLM endpoint with a test key.
    *   A `do` bash script (`./do <command>`) that serves as a task runner for common operations, including:
        *   `./do apply`: Applies the Terraform and Ansible playbooks initially (locally).
        *   `./do tunnel`: Uses the 1Password CLI to fetch the daily IP address and automatically opens the SSH tunnel (`ssh -N -L 4000:127.0.0.1:4000 <user>@$(op read op://.../server-public-ip)`).
        *   `./do lint`: Runs formatters and linters on the Terraform (`terraform fmt` / `tflint`) and Ansible (`ansible-lint`) code.

## 5. Out of Scope (Do NOT Implement)
*   Docker, Docker Compose, or Kubernetes.
*   HTTPS / SSL certificates on the VM (SSH tunnel handles encryption).
*   Multi-model switching, load balancing, or complex IAM/SSO.
*   Complex external databases (PostgreSQL/MySQL) — strictly use SQLite.
