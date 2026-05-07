output "team_domain" {
  description = "Cloudflare Zero Trust team domain (used in Access login redirect)"
  value       = "${var.team_name}.cloudflareaccess.com"
}

output "wildcard_app_aud" {
  description = "AUD claim (JWT audience) for the yh-k8s wildcard Access application"
  value       = cloudflare_zero_trust_access_application.yh_k8s_wildcard.aud
}

output "workers_probe_client_id" {
  description = "CF-Access-Client-Id for the Workers probe service token"
  value       = cloudflare_zero_trust_access_service_token.workers_probe.client_id
}

output "workers_probe_client_secret" {
  description = "CF-Access-Client-Secret for the Workers probe service token (sensitive)"
  value       = cloudflare_zero_trust_access_service_token.workers_probe.client_secret
  sensitive   = true
}
