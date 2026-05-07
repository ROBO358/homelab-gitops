resource "cloudflare_zero_trust_access_application" "yh_k8s_wildcard" {
  account_id                = var.account_id
  name                      = "yh-k8s wildcard"
  domain                    = "*-yh-k8s.tsuru.run"
  type                      = "self_hosted"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true
}

resource "cloudflare_zero_trust_access_policy" "self_only" {
  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.yh_k8s_wildcard.id
  name           = "Allow self only"
  decision       = "allow"
  precedence     = 1
  include = [{
    github = {
      name                 = var.allowed_github_login
      identity_provider_id = cloudflare_zero_trust_access_identity_provider.github.id
    }
  }]
}

# Service Token for Cloudflare Workers probe (bypasses interactive browser auth).
# After apply, set token on the Worker:
#   task worker:secret:cf-access
resource "cloudflare_zero_trust_access_service_token" "workers_probe" {
  account_id = var.account_id
  name       = "workers-probe"
}

resource "cloudflare_zero_trust_access_policy" "workers_probe" {
  account_id     = var.account_id
  application_id = cloudflare_zero_trust_access_application.yh_k8s_wildcard.id
  name           = "Allow workers probe service token"
  decision       = "non_identity"
  precedence     = 0
  include = [{
    service_token = {
      token_id = cloudflare_zero_trust_access_service_token.workers_probe.id
    }
  }]
}
