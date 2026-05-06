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
}

resource "grafana_folder" "yh_cluster" {
  title = "yh-cluster"
  uid   = "yh-cluster"
}

# Lookup the Prometheus datasource already provisioned in Grafana Cloud
data "grafana_data_source" "prometheus" {
  name = var.prometheus_datasource_name
}
