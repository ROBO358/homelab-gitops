terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
  # State is stored locally (.gitignored).
  # Run: terraform init && terraform apply
}

provider "cloudflare" {
  api_token = var.api_token
}
