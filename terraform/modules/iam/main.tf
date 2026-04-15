locals {
  suffix = var.environment
}

# Service Accounts
resource "google_service_account" "ingestor" {
  project      = var.project_id
  account_id   = "sa-ingestor-${local.suffix}"
  display_name = "SA - Cloud Function Ingestor (${local.suffix})"
}

resource "google_service_account" "notificador" {
  project      = var.project_id
  account_id   = "sa-notificador-${local.suffix}"
  display_name = "SA - Cloud Function Notificador (${local.suffix})"
}

resource "google_service_account" "audit_logger" {
  project      = var.project_id
  account_id   = "sa-audit-logger-${local.suffix}"
  display_name = "SA - Cloud Function Audit Logger (${local.suffix})"
}

resource "google_service_account" "dbt_runner" {
  project      = var.project_id
  account_id   = "sa-dbt-runner-${local.suffix}"
  display_name = "SA - Cloud Run Job dbt Runner (${local.suffix})"
}

# IAM — ingestor: BigQuery Data Editor + Pub/Sub Publisher
resource "google_project_iam_member" "ingestor_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.ingestor.email}"
}

resource "google_project_iam_member" "ingestor_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.ingestor.email}"
}

resource "google_project_iam_member" "ingestor_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.ingestor.email}"
}

# IAM — notificador: Secret Manager accessor + Pub/Sub subscriber
resource "google_project_iam_member" "notificador_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.notificador.email}"
}

resource "google_project_iam_member" "notificador_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.notificador.email}"
}

# IAM — audit_logger: BigQuery Data Editor + Pub/Sub subscriber
resource "google_project_iam_member" "audit_logger_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.audit_logger.email}"
}

resource "google_project_iam_member" "audit_logger_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.audit_logger.email}"
}

resource "google_project_iam_member" "audit_logger_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.audit_logger.email}"
}

# IAM — dbt_runner: BigQuery Data Editor + Job User
resource "google_project_iam_member" "dbt_runner_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.dbt_runner.email}"
}

resource "google_project_iam_member" "dbt_runner_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt_runner.email}"
}

resource "google_project_iam_member" "dbt_runner_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.dbt_runner.email}"
}
