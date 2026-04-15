locals {
  suffix = var.environment
}

resource "google_pubsub_topic" "pipeline_eventos" {
  project = var.project_id
  name    = "pipeline-eventos-${local.suffix}"

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

# Subscription de dead-letter para mensagens não processadas (observabilidade)
resource "google_pubsub_subscription" "dead_letter" {
  project = var.project_id
  name    = "sub-pipeline-dead-letter-${local.suffix}"
  topic   = google_pubsub_topic.pipeline_eventos.name

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s" # 7 dias

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}
