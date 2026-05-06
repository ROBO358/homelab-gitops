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
      {
        id    = 5
        title = "Healthchecks.io — Checks Down"
        type  = "stat"
        gridPos = { h = 4, w = 4, x = 0, y = 16 }
        fieldConfig = {
          defaults = {
            unit = "short"
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "green", value = null }, { color = "red", value = 1 }]
            }
          }
        }
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          colorMode     = "background"
          textMode      = "auto"
          graphMode     = "none"
        }
        targets = [{ datasource = local.ds_ref, expr = "hc_checks_down_total", legendFormat = "Down", refId = "A", instant = true }]
      },
      {
        id    = 6
        title = "Healthchecks.io — Current Status"
        type  = "stat"
        gridPos = { h = 4, w = 20, x = 4, y = 16 }
        fieldConfig = {
          defaults = {
            unit = "short"
            mappings = [
              { type = "value", options = {
                "0" = { text = "Down", color = "red"   }
                "1" = { text = "Up",   color = "green" }
              }}
            ]
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "red", value = null }, { color = "green", value = 1 }]
            }
          }
        }
        options = {
          reduceOptions = { calcs = ["lastNotNull"] }
          orientation   = "auto"
          colorMode     = "background"
          textMode      = "value_and_name"
        }
        targets = [{ datasource = local.ds_ref, expr = "hc_check_up", legendFormat = "{{name}}", refId = "A", instant = true }]
      },
      {
        id    = 7
        title = "Healthchecks.io — Availability History"
        type  = "state-timeline"
        gridPos = { h = 8, w = 24, x = 0, y = 20 }
        fieldConfig = {
          defaults = {
            mappings = [
              { type = "value", options = {
                "0" = { text = "Down", color = "red",   index = 0 }
                "1" = { text = "Up",   color = "green", index = 1 }
              }}
            ]
            thresholds = {
              mode  = "absolute"
              steps = [{ color = "red", value = null }, { color = "green", value = 1 }]
            }
            color = { mode = "thresholds" }
          }
        }
        options = {
          mergeValues = true
          showValue   = "auto"
          alignValue  = "center"
          rowHeight   = 0.9
          legend      = { displayMode = "list", placement = "bottom" }
          tooltip     = { mode = "single" }
        }
        targets = [{ datasource = local.ds_ref, expr = "hc_check_up", legendFormat = "{{name}}", refId = "A" }]
      },
    ]
  }
}

resource "grafana_dashboard" "sli_overview" {
  folder      = grafana_folder.yh_cluster.uid
  config_json = jsonencode(local.sli_dashboard)
}
