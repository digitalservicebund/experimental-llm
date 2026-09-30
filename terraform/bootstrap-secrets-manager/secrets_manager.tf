module "secrets_manager" {
  source = "git::https://github.com/digitalservicebund/terraform-modules.git//stackit-secrets-manager?ref=042bb60122c78c797970a4bc16c7a5e4f8663e80"

  project_id           = var.project_id
  name                 = var.secrets_manager_name
  kubernetes_namespace = var.kubernetes_namespace
}

locals {
  staging_overlay_dir = "${path.module}/../../manifests/overlays/staging"
}

resource "null_resource" "secret_store_manifest" {
  provisioner "local-exec" {
    command = <<-EOT
cat <<'EOF' > ${local.staging_overlay_dir}/secret-store.yaml
${module.secrets_manager.external_secrets_secret_store_manifest}
EOF
    EOT
  }
}

resource "null_resource" "secret_manifest" {
  provisioner "local-exec" {
    command = <<-EOT
cat <<'EOF' > ${local.staging_overlay_dir}/do-not-commit.yaml
${module.secrets_manager.external_secrets_secret_manifest}
EOF
    EOT
  }
}
