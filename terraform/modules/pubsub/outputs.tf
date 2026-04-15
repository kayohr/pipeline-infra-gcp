output "topic_id" {
  value = google_pubsub_topic.pipeline_eventos.id
}

output "topic_name" {
  value = google_pubsub_topic.pipeline_eventos.name
}

output "dead_letter_subscription_id" {
  value = google_pubsub_subscription.dead_letter.id
}
