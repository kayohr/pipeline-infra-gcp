locals {
  suffix     = var.environment
  job_name   = "dbt-runner-${local.suffix}"
  image_name = "gcr.io/${var.project_id}/dbt-runner:latest"
}

resource "google_cloud_run_v2_job" "dbt_runner" {
  project  = var.project_id
  name     = local.job_name
  location = var.region

  template {
    template {
      service_account = var.dbt_runner_sa

      containers {
        image = local.image_name

        env {
          name  = "GCP_PROJECT"
          value = var.project_id
        }
        env {
          name  = "ENVIRONMENT"
          value = local.suffix
        }
        env {
          name  = "PUBSUB_TOPIC"
          value = split("/", var.pubsub_topic_id)[length(split("/", var.pubsub_topic_id)) - 1]
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }

      timeout     = "1800s"
      max_retries = 1
    }
  }

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}
