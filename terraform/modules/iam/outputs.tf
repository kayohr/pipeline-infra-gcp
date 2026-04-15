output "ingestor_sa_email" {
  value = google_service_account.ingestor.email
}

output "notificador_sa_email" {
  value = google_service_account.notificador.email
}

output "audit_logger_sa_email" {
  value = google_service_account.audit_logger.email
}

output "dbt_runner_sa_email" {
  value = google_service_account.dbt_runner.email
}
