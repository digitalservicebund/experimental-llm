#!/usr/bin/env bash
set -euo pipefail
SSH_USER="${SSH_USER:-ubuntu}"
SERVER_PUBLIC_IP="$(op read "op://z3yr24dkqmdjsvc724nouabjpi/eslyhyeireaxhtopettp7fxbwm/server-public-ip")"
ssh "$SSH_USER@$SERVER_PUBLIC_IP" "$@"
