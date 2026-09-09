locals {
  celery_queue_length_query = "max by (queue) (celery_queue_length{cluster=\"${data.terraform_remote_state.infra.outputs.cluster_name}\",namespace=\"${local.namespace_name}\",queue=\"${var.helm_config.care_metrics_exporter.queue}\"})"
}

resource "google_monitoring_dashboard" "care_application" {
  project = var.project_id

  dashboard_json = jsonencode({
    displayName = "CARE Application - ${var.environment}"
    mosaicLayout = {
      columns = 48
      tiles = [{
        xPos   = 0
        yPos   = 0
        width  = 48
        height = 20
        widget = {
          title = "Celery queue length"
          xyChart = {
            dataSets = [{
              plotType   = "LINE"
              targetAxis = "Y1"
              timeSeriesQuery = {
                prometheusQuery = local.celery_queue_length_query
              }
            }]
            yAxis = {
              label = "messages"
              scale = "LINEAR"
            }
          }
        }
      }]
    }
  })
}

resource "google_monitoring_notification_channel" "email" {
  for_each = var.monitoring_notification_emails
  project  = var.project_id

  display_name = "CARE monitoring - ${each.value}"
  type         = "email"
  labels = {
    email_address = each.value
  }

  user_labels = {
    application = "care"
    environment = var.environment
    managed_by  = "opentofu"
  }
}

resource "google_monitoring_alert_policy" "care_queue_length" {
  count   = var.helm_config.care_metrics_exporter.enabled ? 1 : 0
  project = var.project_id

  display_name          = "CARE Celery queue above 200 - ${var.environment}"
  combiner              = "OR"
  enabled               = true
  severity              = "WARNING"
  notification_channels = [for channel in google_monitoring_notification_channel.email : channel.name]

  conditions {
    display_name = "Celery queue length is greater than 200"
    condition_prometheus_query_language {
      query               = "${local.celery_queue_length_query} > 200"
      duration            = "300s"
      evaluation_interval = "60s"
      alert_rule          = "CareCeleryQueueAbove200"
      rule_group          = "care-metrics-exporter"
    }
  }

  documentation {
    mime_type = "text/markdown"
    content   = "The CARE Celery queue has remained above 200 ready messages for five minutes in `${var.environment}`. Check worker health and whether the queue is draining."
  }

  alert_strategy {
    auto_close           = "1800s"
    notification_prompts = ["OPENED", "CLOSED"]
  }

  user_labels = {
    application = "care"
    component   = "metrics-exporter"
    environment = var.environment
  }
}
