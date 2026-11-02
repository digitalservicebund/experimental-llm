provider "stackit" {
  default_region = var.region
  experiments    = ["iam"]
}

provider "aws" {
  region                      = "eu01"
  skip_credentials_validation = true
  skip_region_validation      = true
  skip_requesting_account_id  = true

  access_key = var.backend_access_key_id
  secret_key = var.backend_secret_access_key

  endpoints {
    s3 = "https://object.storage.eu01.onstackit.cloud"
  }
}
