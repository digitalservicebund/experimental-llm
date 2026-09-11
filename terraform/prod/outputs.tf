output "public_ip" {
  description = "Public IP of the production VM, if enabled."
  value       = module.llm_gateway.public_ip
}

output "server_id" {
  description = "Server ID of the production VM, if enabled."
  value       = module.llm_gateway.server_id
}

output "network_interface_id" {
  description = "Network interface ID of the production VM, if enabled."
  value       = module.llm_gateway.network_interface_id
}

output "boot_volume_id" {
  description = "Persistent boot volume ID for the production VM."
  value       = module.llm_gateway.boot_volume_id
}

