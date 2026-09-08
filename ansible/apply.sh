#!/usr/bin/env bash
set -euo pipefail

op run --env-file=.env.op -- ansible-playbook playbooks/site.yml \
	-i inventories/production/hosts.yml
