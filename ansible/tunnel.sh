#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

# Local override knobs for different client setups.
local_port="${VLLM_TUNNEL_LOCAL_PORT:-8000}"
remote_port="${VLLM_TUNNEL_REMOTE_PORT:-8000}"
remote_host="${VLLM_TUNNEL_REMOTE_HOST:-127.0.0.1}"
ssh_user="${VLLM_SSH_USER:-ubuntu}"

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

