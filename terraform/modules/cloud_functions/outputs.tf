output "ingestor_uri" {
  value = google_cloudfunctions2_function.ingestor.service_config[0].uri
}

output "notificador_uri" {
  value = google_cloudfunctions2_function.notificador.service_config[0].uri
}

output "audit_logger_uri" {
  value = google_cloudfunctions2_function.audit_logger.service_config[0].uri
}
