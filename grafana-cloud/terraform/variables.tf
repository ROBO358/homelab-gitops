variable "grafana_url" {
  description = "Grafana Cloud instance URL (e.g. https://yourorg.grafana.net)"
  type        = string
}

variable "grafana_auth" {
  description = <<-EOT
    Grafana service account token with Editor role.
    Create at: Grafana Cloud > Administration > Service accounts > Add service account token
    Store in 1Password: grafana-cloud-terraform / token
    NOT the same as the metrics:write token used for remoteWrite.
  EOT
  type      = string
  sensitive = true
}

variable "prometheus_datasource_name" {
  description = "Name of the Prometheus datasource in Grafana Cloud (shown in Connections > Data sources)"
  type        = string
  # Grafana Cloud default pattern: grafanacloud-<orgname>-prom
}

variable "connections_api_access_token" {
  description = <<-EOT
    Grafana Cloud Access Policy token with integration-management:read/write scopes.
    Create at: Grafana Cloud > My Account > Access Policies
    Store in 1Password: grafana-cloud-terraform / connections_token
  EOT
  type      = string
  sensitive = true
}

variable "stack_id" {
  description = "Grafana Cloud stack numeric ID (shown in My Account > Your Stacks > stack URL)"
  type        = string
}

variable "healthchecks_project_uuid" {
  description = "Healthchecks.io project UUID (Project Settings > API Access)"
  type        = string
}

variable "healthchecks_api_key" {
  description = "Healthchecks.io read-only API key (Project Settings > API Access)"
  type        = string
  sensitive   = true
}

variable "discord_webhook_url" {
  description = <<-EOT
    Discord webhook URL for Grafana Cloud alert contact point (Discord native format — no /slack suffix).
    Store in 1Password: monitoring-discord-grafana-cloud / webhook-url
    Format: https://discord.com/api/webhooks/{id}/{token}
  EOT
  type      = string
  sensitive = true
}
