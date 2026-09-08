#!/usr/bin/env bash
set -euo pipefail

op run --env-file=.env.op -- ansible llm_servers -m ansible.builtin.ping
