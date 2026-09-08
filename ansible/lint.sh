#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${script_dir}"

ansible-galaxy collection install -r requirements.yml

yamllint -d relaxed .
ansible-playbook playbooks/site.yml --syntax-check
ansible-inventory --graph
ansible-playbook playbooks/site.yml --list-hosts
ansible-playbook playbooks/site.yml --list-tasks
ansible-lint playbooks roles
