output "public_ip" {
  description = "Public IPv4 address assigned to the VM, if enabled."
  value       = try(stackit_public_ip.server.ip, null)
}

output "server_id" {
  description = "STACKIT server ID when the VM is enabled."
  value       = try(stackit_server.vm[0].server_id, null)
}

output "network_interface_id" {
  description = "STACKIT network interface ID when the VM is enabled."
  value       = try(stackit_network_interface.server.network_interface_id, null)
}

output "boot_volume_id" {
  description = "Persistent boot volume ID."
  value       = stackit_volume.boot.volume_id
}

output "dns_name" {
  description = "DNS name pointing to the VM public IP."
  value       = trimsuffix(stackit_dns_record_set.vm.name, ".")
}

output "dns_zone_id" {
  description = "STACKIT DNS zone ID."
  value       = stackit_dns_zone.vm.zone_id
}
