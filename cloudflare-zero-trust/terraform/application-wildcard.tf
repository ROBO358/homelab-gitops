# Policy: allow only the owner's email (GitHub IdP sends the primary GitHub email)
resource "cloudflare_zero_trust_access_policy" "self_only" {
  account_id = var.account_id
  name       = "Allow self only"
  decision   = "allow"
  include = [{
    email = { email = var.allowed_email }
  }]
}

# Service Token for Cloudflare Workers probe (bypasses interactive browser auth).
# After apply, set token on the Worker:
#   task worker:secret:cf-access
resource "cloudflare_zero_trust_access_service_token" "workers_probe" {
  account_id = var.account_id
  name       = "workers-probe"
}

# Policy: allow Workers probe via service token (non_identity, precedence 0 = evaluated first)
resource "cloudflare_zero_trust_access_policy" "workers_probe" {
  account_id = var.account_id
  name       = "Allow workers probe service token"
  decision   = "non_identity"
  include = [{
    service_token = {
      token_id = cloudflare_zero_trust_access_service_token.workers_probe.id
    }
  }]
}

resource "cloudflare_zero_trust_access_application" "yh_k8s_wildcard" {
  account_id                = var.account_id
  name                      = "yh-k8s wildcard"
  domain                    = "*-yh-k8s.tsuru.run"
  type                      = "self_hosted"
  session_duration          = "24h"
  allowed_idps              = [cloudflare_zero_trust_access_identity_provider.github.id]
  auto_redirect_to_identity = true

  # v5: precedence is set here, policies referenced by id
  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.workers_probe.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.self_only.id
      precedence = 2
    },
  ]
}
