resource "grafana_rule_group" "sli" {
  name             = "SLI Alerts"
  folder_uid       = grafana_folder.yh_cluster.uid
  interval_seconds = 60

  # ── Alert 1: remoteWrite 途絶検知 ─────────────────────────────────────────
  # sli:* メトリクスが 15 分間届かない = クラスタ全断 or remoteWrite 停止
  # no_data_state = "Alerting" がトリガー条件（absent() 相当）
  rule {
    name           = "RemoteWriteAbsent"
    condition      = "A"
    no_data_state  = "Alerting"
    exec_err_state = "Error"
    for            = "15m"

    annotations = {
      summary     = "Prometheus remoteWrite to Grafana Cloud has stopped for 15+ minutes"
      description = "No sli:* metrics received. Possible causes: cluster down, Prometheus crash, or remoteWrite misconfiguration."
    }
    labels = {
      severity = "critical"
      source   = "grafana-cloud"
    }

    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus.uid
      relative_time_range {
        from = 900
        to   = 0
      }
      model = jsonencode({
        expr          = "sli:node_availability:bool"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
      })
    }
  }

  # ── Alert 2: 証明書期限（14 日前）────────────────────────────────────────
  # ローカル Alertmanager は 7 日閾値なので、クラウド側は 14 日で早期警告
  rule {
    name           = "CertificateExpiringSoon"
    condition      = "C"
    no_data_state  = "NoData"
    exec_err_state = "Error"
    for            = "1h"

    annotations = {
      summary     = "TLS certificate expires in less than 14 days"
      description = "Certificate {{ $labels.name }} in namespace {{ $labels.exported_namespace }} expires in {{ $values.B.Value | humanizeDuration }}."
    }
    labels = {
      severity = "warning"
      source   = "grafana-cloud"
    }

    # Query: sli:certificate_expiry_days
    data {
      ref_id         = "A"
      datasource_uid = data.grafana_data_source.prometheus.uid
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        expr          = "sli:certificate_expiry_days"
        intervalMs    = 1000
        maxDataPoints = 43200
        refId         = "A"
      })
    }

    # Reduce: last value per series
    data {
      ref_id         = "B"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        type       = "reduce"
        refId      = "B"
        expression = "A"
        reducer    = "last"
        datasource = { type = "__expr__", uid = "__expr__" }
      })
    }

    # Threshold: B < 14
    data {
      ref_id         = "C"
      datasource_uid = "__expr__"
      relative_time_range {
        from = 600
        to   = 0
      }
      model = jsonencode({
        type       = "threshold"
        refId      = "C"
        expression = "B"
        datasource = { type = "__expr__", uid = "__expr__" }
        conditions = [{
          evaluator = { type = "lt", params = [14] }
          unloadEvaluator = { type = "gt", params = [14] }
          query     = { params = ["C"] }
          reducer   = { type = "last", params = [] }
          type      = "query"
        }]
      })
    }
  }
}
