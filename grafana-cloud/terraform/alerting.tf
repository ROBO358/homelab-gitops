resource "grafana_contact_point" "discord" {
  name = "Discord"
  discord {
    url = var.discord_webhook_url
  }
}

# Root notification policy: route all alerts to Discord.
# This replaces the Grafana Cloud default routing tree.
resource "grafana_notification_policy" "default" {
  contact_point = grafana_contact_point.discord.name
  group_by      = ["alertname", "grafana_folder"]
  group_wait      = "30s"
  group_interval  = "5m"
  repeat_interval = "4h"
}
