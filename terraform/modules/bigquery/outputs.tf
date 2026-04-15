output "dataset_raw_id" {
  value = google_bigquery_dataset.raw.dataset_id
}

output "dataset_staging_id" {
  value = google_bigquery_dataset.staging.dataset_id
}

output "dataset_marts_id" {
  value = google_bigquery_dataset.marts.dataset_id
}

output "table_clima_raw_id" {
  value = google_bigquery_table.clima_raw.table_id
}

output "table_audit_log_id" {
  value = google_bigquery_table.pipeline_audit_log.table_id
}
