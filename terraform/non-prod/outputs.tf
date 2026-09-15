output "public_ip" {
  description = "Public IP of the non-production VM, if enabled."
  value       = module.llm_gateway.public_ip
}

output "server_id" {
  description = "Server ID of the non-production VM, if enabled."
  value       = module.llm_gateway.server_id
}

output "network_interface_id" {
  description = "Network interface ID of the non-production VM, if enabled."
  value       = module.llm_gateway.network_interface_id
}

output "boot_volume_id" {
  description = "Persistent boot volume ID for the non-production VM."
  value       = module.llm_gateway.boot_volume_id
}

output "dns_name" {
  description = "DNS name pointing to the non-production VM public IP."
  value       = module.llm_gateway.dns_name
}

output "dns_zone_id" {
  description = "STACKIT DNS zone ID for the non-production VM."
  value       = module.llm_gateway.dns_zone_id
}

