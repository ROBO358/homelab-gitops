terraform {
  required_providers {
    grafana = {
      source  = "grafana/grafana"
      version = "~> 3.7"
    }
  }
  # State is stored locally (.gitignored).
  # Run: terraform init && terraform apply
}

provider "grafana" {
  url  = var.grafana_url
  auth = var.grafana_auth

  connections_api_access_token = var.connections_api_access_token
  connections_api_url          = "https://connections-api-prod-ap-northeast-0.grafana.net"
  stack_id                     = var.stack_id
}

resource "grafana_folder" "yh_cluster" {
  title = "yh-cluster"
  uid   = "yh-cluster"
}

# Lookup the Prometheus datasource already provisioned in Grafana Cloud
data "grafana_data_source" "prometheus" {
  name = var.prometheus_datasource_name
}

# Grafana Cloud が Healthchecks.io の Prometheus エンドポイントを直接スクレイプ
# クラスタが落ちていても hc_check_up メトリクスが Grafana Cloud 側で取得できる
resource "grafana_connections_metrics_endpoint_scrape_job" "healthchecks" {
  stack_id                    = var.stack_id
  name                        = "healthchecks-io"
  enabled                     = true
  authentication_method       = "bearer"
  authentication_bearer_token = var.healthchecks_api_key
  url                         = "https://healthchecks.io/projects/${var.healthchecks_project_uuid}/metrics/"
  scrape_interval_seconds     = 60
}
