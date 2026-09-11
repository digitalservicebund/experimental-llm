terraform {
  required_providers {
    stackit = {
      source = "stackitcloud/stackit"
    }
  }
}

locals {
  bootstrap_ssh_public_key = trimspace(var.bootstrap_ssh_public_key)
  security_group_name      = "${var.vm_name}-ssh"
  network_interface_name   = "${var.vm_name}-nic"
}

check "bootstrap_ssh_public_key_required_when_vm_enabled" {
  assert {
    condition     = !var.vm_enabled || local.bootstrap_ssh_public_key != ""
    error_message = "Set bootstrap_ssh_public_key before enabling the VM."
  }
}

check "vm_machine_type_required_when_vm_enabled" {
  assert {
    condition     = !var.vm_enabled || trimspace(var.vm_machine_type_name) != ""
    error_message = "Set vm_machine_type_name before enabling the VM."
  }
}

data "stackit_network" "existing" {
  project_id = var.project_id
  network_id = var.existing_network_id
}

data "stackit_machine_type" "vm" {
  count      = var.vm_enabled ? 1 : 0
  project_id = var.project_id
  filter     = "name == \"${var.vm_machine_type_name}\""
}

resource "stackit_volume" "boot" {
  project_id        = var.project_id
  availability_zone = var.availability_zone
  name              = "${var.vm_name}-boot"
  description       = "Persistent boot volume for ${var.vm_name}"
  size              = var.boot_volume_size_gb
  performance_class = var.boot_volume_performance_class

  source = {
    type = "image"
    id   = "f73d4ce4-c870-47c2-8622-24b030f2c9c1" # Ubuntu 26.04 x86
  }

  lifecycle {
    ignore_changes = [source]
  }
}

resource "stackit_security_group" "ssh" {
  project_id  = var.project_id
  name        = local.security_group_name
  description = "SSH-only security group for ${var.vm_name}"
  stateful    = true
}

resource "stackit_security_group_rule" "ssh_ipv4" {
  project_id        = var.project_id
  security_group_id = stackit_security_group.ssh.security_group_id
  direction         = "ingress"
  ether_type        = "IPv4"
  description       = "Allow SSH from IPv4 clients"
  ip_range          = "0.0.0.0/0"

  protocol = {
    name = "tcp"
  }

  port_range = {
    min = 22
    max = 22
  }
}

resource "stackit_security_group_rule" "ssh_ipv6" {
  project_id        = var.project_id
  security_group_id = stackit_security_group.ssh.security_group_id
  direction         = "ingress"
  ether_type        = "IPv6"
  description       = "Allow SSH from IPv6 clients"
  ip_range          = "::/0"

  protocol = {
    name = "tcp"
  }

  port_range = {
    min = 22
    max = 22
  }
}

resource "stackit_network_interface" "server" {
  count      = var.vm_enabled ? 1 : 0
  project_id = var.project_id
  network_id = data.stackit_network.existing.network_id
  name       = local.network_interface_name

  security_group_ids = [stackit_security_group.ssh.security_group_id]
}

resource "stackit_server" "vm" {
  count             = var.vm_enabled ? 1 : 0
  project_id        = var.project_id
  availability_zone = var.availability_zone
  name              = var.vm_name
  machine_type      = data.stackit_machine_type.vm[0].name

  boot_volume = {
    source_type = "volume"
    source_id   = stackit_volume.boot.volume_id
  }

  network_interfaces = [stackit_network_interface.server[0].network_interface_id]
  user_data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
    hostname                 = var.vm_name
    ssh_user                 = var.bootstrap_ssh_user
    bootstrap_ssh_public_key = local.bootstrap_ssh_public_key
  })
}

resource "stackit_public_ip" "server" {
  count                = var.vm_enabled ? 1 : 0
  project_id           = var.project_id
  network_interface_id = stackit_network_interface.server[0].network_interface_id
}

