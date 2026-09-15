#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ansible_dir="${repo_dir}/ansible"

usage() {
  cat <<'EOF'
Usage: ./do <command> [args]

Commands:
  lint             Run local Ansible lint and syntax checks.
  apply [tags]     Run Ansible apply. Optional: specify tags to limit tasks.
                   Common tags: common, postgresql, vllm, litellm
                   Example: ./do apply litellm
  ping [args...]   Ping hosts in llm_servers.
  login [args...]  SSH into the server from 1Password.
  tunnel           Open SSH tunnel to remote vLLM API.
  generate-keys    Generate Virtual Keys for LiteLLM proxy authentication.
  help             Show this help text.
EOF
}

if [[ $# -gt 0 ]]; then
  command="$1"
  shift
else
  command="help"
fi

case "${command}" in
  lint)
    cd "${ansible_dir}"
    ansible-galaxy collection install -r requirements.yml
    yamllint -d relaxed .
    ansible-playbook playbooks/site.yml --syntax-check
    ansible-inventory --graph
    ansible-playbook playbooks/site.yml --list-hosts
    ansible-playbook playbooks/site.yml --list-tasks
    ansible-lint playbooks roles
    ;;

  apply)
    cd "${ansible_dir}"
    if [[ $# -gt 0 ]]; then
      # If tags are provided, run only those tags
      op run --env-file=.env.op -- ansible-playbook playbooks/site.yml \
        -i inventories/production/hosts.yml \
        --tags "$@"
    else
      # Run full playbook
      op run --env-file=.env.op -- ansible-playbook playbooks/site.yml \
        -i inventories/production/hosts.yml
    fi
    ;;

  ping)
    cd "${ansible_dir}"
    op run --env-file=.env.op -- ansible llm_servers -m ansible.builtin.ping "$@"
    ;;

  login)
    ssh_user="${SSH_USER:-ubuntu}"
    server_public_ip="$(cd "${ansible_dir}" && op read "op://z3yr24dkqmdjsvc724nouabjpi/eslyhyeireaxhtopettp7fxbwm/server-public-ip")"
    exec ssh "${ssh_user}@${server_public_ip}" "$@"
    ;;

  tunnel)
    local_port="${VLLM_TUNNEL_LOCAL_PORT:-8000}"
    remote_port="${VLLM_TUNNEL_REMOTE_PORT:-8000}"
    remote_host="${VLLM_TUNNEL_REMOTE_HOST:-127.0.0.1}"
    ssh_user="${VLLM_SSH_USER:-ubuntu}"

    cd "${ansible_dir}"
    VLLM_TUNNEL_LOCAL_PORT="${local_port}" \
    VLLM_TUNNEL_REMOTE_PORT="${remote_port}" \
    VLLM_TUNNEL_REMOTE_HOST="${remote_host}" \
    VLLM_SSH_USER="${ssh_user}" \
    op run --env-file=.env.op -- bash -c '
      set -euo pipefail
      echo "Opening tunnel on 127.0.0.1:${VLLM_TUNNEL_LOCAL_PORT} -> ${VLLM_TUNNEL_REMOTE_HOST}:${VLLM_TUNNEL_REMOTE_PORT} via ${SERVER_PUBLIC_IP}" >&2
      exec ssh \
        -N \
        -L "${VLLM_TUNNEL_LOCAL_PORT}:${VLLM_TUNNEL_REMOTE_HOST}:${VLLM_TUNNEL_REMOTE_PORT}" \
        -o ExitOnForwardFailure=yes \
        -o ServerAliveInterval=30 \
        -o ServerAliveCountMax=3 \
        "${VLLM_SSH_USER}@${SERVER_PUBLIC_IP}"
    '
    ;;

  generate-keys)
    key_alias="${1:-test_key_1}"
    cd "${ansible_dir}"
    op run --env-file=.env.op -- bash -c '
      set -euo pipefail
      echo "Generating Virtual Key: '"${key_alias}"'" >&2
      curl -s -X POST "http://127.0.0.1:4000/key/generate" \
        -H "Authorization: Bearer ${LLM_MASTER_KEY}" \
        -H "Content-Type: application/json" \
        -d "{\"key_alias\": \"'"${key_alias}"'\"}" | jq .
    '
    ;;

  help|-h|--help)
    usage
    ;;

  *)
    echo "Unknown command: ${command}" >&2
    usage >&2
    exit 1
    ;;
esac

