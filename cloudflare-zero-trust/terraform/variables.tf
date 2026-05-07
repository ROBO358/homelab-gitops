variable "api_token" {
  description = <<-EOT
    Cloudflare API token with Access: Apps and Policies + Identity Providers scopes.
    Scope: Account.Access: Apps and Policies:Edit, Account.Access: Identity Providers:Edit
    Create at: Cloudflare Dashboard > My Profile > API Tokens > Create Token
    Store in 1Password: cloudflare-access-terraform-token / api-token (yh-cluster vault)
  EOT
  type      = string
  sensitive = true
}

variable "account_id" {
  description = <<-EOT
    Cloudflare Account ID (found in Dashboard > right sidebar or any zone URL).
    Store in 1Password: cloudflare-access-terraform-token / account-id (yh-cluster vault)
  EOT
  type = string
}

variable "team_name" {
  description = <<-EOT
    Cloudflare Zero Trust team name (the subdomain of <team>.cloudflareaccess.com).
    Store in 1Password: cloudflare-access-terraform-token / team-name (yh-cluster vault)
  EOT
  type = string
}

variable "github_oauth_client_id" {
  description = <<-EOT
    GitHub OAuth App Client ID for Cloudflare Access GitHub IdP.
    Create a NEW OAuth App (separate from Dex):
      GitHub Settings > Developer settings > OAuth Apps > New OAuth App
      Homepage URL: https://<team>.cloudflareaccess.com
      Callback URL: https://<team>.cloudflareaccess.com/cdn-cgi/access/callback
    Store in 1Password: cloudflare-access-github-oauth / client-id (yh-cluster vault)
  EOT
  type = string
}

variable "github_oauth_client_secret" {
  description = <<-EOT
    GitHub OAuth App Client Secret for Cloudflare Access GitHub IdP.
    Store in 1Password: cloudflare-access-github-oauth / client-secret (yh-cluster vault)
  EOT
  type      = string
  sensitive = true
}

variable "allowed_github_login" {
  description = <<-EOT
    GitHub username (login) allowed through Access (e.g. "ROBO358").
    Store in 1Password: cloudflare-access-terraform-token / allowed-github-login (yh-cluster vault)
  EOT
  type = string
}
