locals {
  ds_ref = { type = "prometheus", uid = data.grafana_data_source.prometheus.uid }

  sli_dashboard = {
    title         = "SLI Overview — yh-cluster"
    uid           = "yh-sli-overview"
    description   = "SLI metrics sourced via Prometheus remoteWrite (14-day retention)"
    refresh       = "1m"
    schemaVersion = 38
    tags          = ["yh-cluster", "sli"]
    time          = { from = "now-7d", to = "now" }
    graphTooltip  = 1
    panels = [
      {
        id    = 1
        title = "Node Availability"
        type  = "timeseries"
        gridPos = { h = 8, w = 12, x = 0, y = 0 }
        fieldConfig = {
          defaults = {
            unit = "short"
            min  = 0
            max  = 1
            custom = { lineWidth = 2, fillOpacity = 10 }
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "red", value = null }, { color = "green", value = 1 }]
            }
            mappings = [
              { type = "value", options = { "0" = { text = "Down", color = "red" }, "1" = { text = "Up", color = "green" } } }
            ]
          }
        }
        options = { tooltip = { mode = "single" }, legend = { displayMode = "list", placement = "bottom" } }
        targets = [{ datasource = local.ds_ref, expr = "sli:node_availability:bool", legendFormat = "{{instance}}", refId = "A" }]
      },
      {
        id    = 2
        title = "API Server Availability"
        type  = "timeseries"
        gridPos = { h = 8, w = 12, x = 12, y = 0 }
        fieldConfig = {
          defaults = {
            unit   = "percentunit"
            min    = 0
            max    = 1
            custom = { lineWidth = 2, fillOpacity = 10 }
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "red", value = null }, { color = "yellow", value = 0.95 }, { color = "green", value = 0.99 }]
            }
          }
        }
        options = { tooltip = { mode = "single" }, legend = { displayMode = "list", placement = "bottom" } }
        targets = [{ datasource = local.ds_ref, expr = "sli:apiserver_availability:ratio_rate5m", legendFormat = "availability", refId = "A" }]
      },
      {
        id    = 3
        title = "Certificate Expiry"
        type  = "stat"
        gridPos = { h = 8, w = 6, x = 0, y = 8 }
        fieldConfig = {
          defaults = {
            unit = "d"
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "red", value = null }, { color = "yellow", value = 14 }, { color = "green", value = 30 }]
            }
          }
        }
        options = { reduceOptions = { calcs = ["lastNotNull"] }, orientation = "auto", colorMode = "background" }
        targets = [{ datasource = local.ds_ref, expr = "sli:certificate_expiry_days", legendFormat = "{{exported_namespace}}/{{name}}", refId = "A", instant = true }]
      },
      {
        id    = 4
        title = "Pod Restart Rate"
        type  = "timeseries"
        gridPos = { h = 8, w = 18, x = 6, y = 8 }
        fieldConfig = {
          defaults = {
            unit   = "ops"
            min    = 0
            custom = { lineWidth = 2, fillOpacity = 10 }
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "green", value = null }, { color = "yellow", value = 0.1 }, { color = "red", value = 1 }]
            }
          }
        }
        options = { tooltip = { mode = "single" }, legend = { displayMode = "list", placement = "bottom" } }
        targets = [{ datasource = local.ds_ref, expr = "sli:pod_restart_rate:rate5m", legendFormat = "{{namespace}}/{{pod}}", refId = "A" }]
      },
    ]
  }
}

resource "grafana_dashboard" "sli_overview" {
  folder      = grafana_folder.yh_cluster.uid
  config_json = jsonencode(local.sli_dashboard)
}
