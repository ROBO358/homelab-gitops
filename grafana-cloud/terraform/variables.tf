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
