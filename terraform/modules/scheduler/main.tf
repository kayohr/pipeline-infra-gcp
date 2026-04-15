locals {
  suffix = var.environment
}

# Scheduler para o ingestor — a cada hora
resource "google_cloud_scheduler_job" "ingestor_horario" {
  project  = var.project_id
  name     = "scheduler-ingestor-${local.suffix}"
  region   = var.region
  schedule = "0 * * * *"  # todo início de hora
  time_zone = "America/Sao_Paulo"

  http_target {
    uri         = var.ingestor_function_uri
    http_method = "POST"
    body        = base64encode("{}")

    oidc_token {
      service_account_email = google_service_account.scheduler_invoker.email
      audience              = var.ingestor_function_uri
    }
  }

  retry_config {
    retry_count = 3
  }
}

# Scheduler para o dbt-runner — 10 minutos após o ingestor
resource "google_cloud_scheduler_job" "dbt_runner" {
  project  = var.project_id
  name     = "scheduler-dbt-runner-${local.suffix}"
  region   = var.region
  schedule = "10 * * * *"  # 10 minutos após o ingestor
  time_zone = "America/Sao_Paulo"

  http_target {
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/${var.dbt_runner_job_name}:run"
    http_method = "POST"

    oauth_token {
      service_account_email = google_service_account.scheduler_invoker.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count = 2
  }
}

# Service Account para o Scheduler invocar os serviços
resource "google_service_account" "scheduler_invoker" {
  project      = var.project_id
  account_id   = "sa-scheduler-${local.suffix}"
  display_name = "SA - Cloud Scheduler Invoker (${local.suffix})"
}

resource "google_project_iam_member" "scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler_invoker.email}"
}
