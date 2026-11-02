resource "stackit_dns_zone" "experimental_llm" {
  project_id    = var.project_id
  name          = var.dns_zone_display_name
  dns_name      = var.dns_name
  contact_email = var.dns_contact_email
  type          = "primary"
  description   = "Zone for llm-gateway-non-prod"
  default_ttl   = var.dns_default_ttl

  lifecycle {
    prevent_destroy = true
  }
}

# The zone used to be part of the GPU VM module. Its attributes are unchanged,
# so Terraform only moves it in the state.
moved {
  from = module.llm_gateway.stackit_dns_zone.vm
  to   = stackit_dns_zone.experimental_llm
}
