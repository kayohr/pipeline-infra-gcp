locals {
  suffix = var.environment
}

# Bucket para código fonte das functions
resource "google_storage_bucket" "functions_source" {
  project                     = var.project_id
  name                        = "${var.project_id}-functions-src-${local.suffix}"
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = var.environment == "dev" ? true : false

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

# --- INGESTOR ---
data "archive_file" "ingestor_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../functions/ingestor"
  output_path = "/tmp/ingestor-${local.suffix}.zip"
}

resource "google_storage_bucket_object" "ingestor_source" {
  name   = "ingestor-${data.archive_file.ingestor_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.ingestor_zip.output_path
}

resource "google_cloudfunctions2_function" "ingestor" {
  project  = var.project_id
  name     = "ingestor-${local.suffix}"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "ingestor"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.ingestor_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 3
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 120
    service_account_email = var.ingestor_sa_email

    environment_variables = {
      GCP_PROJECT       = var.project_id
      BQ_DATASET_RAW    = var.bq_dataset_raw
      BQ_TABLE_CLIMA_RAW = var.bq_table_clima_raw
      PUBSUB_TOPIC      = split("/", var.pubsub_topic_id)[length(split("/", var.pubsub_topic_id)) - 1]
    }
  }

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

# --- NOTIFICADOR ---
data "archive_file" "notificador_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../functions/notificador"
  output_path = "/tmp/notificador-${local.suffix}.zip"
}

resource "google_storage_bucket_object" "notificador_source" {
  name   = "notificador-${data.archive_file.notificador_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.notificador_zip.output_path
}

resource "google_cloudfunctions2_function" "notificador" {
  project  = var.project_id
  name     = "notificador-${local.suffix}"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "notificador"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.notificador_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 3
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = var.notificador_sa_email

    environment_variables = {
      GCP_PROJECT        = var.project_id
      SENDGRID_SECRET_ID = var.sendgrid_secret_id
      NOTIFICATION_EMAIL = var.notification_email
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.pubsub_topic_id
    service_account_email = var.notificador_sa_email
    retry_policy          = "RETRY_POLICY_RETRY"
  }

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

# --- AUDIT LOGGER ---
data "archive_file" "audit_logger_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../functions/audit_logger"
  output_path = "/tmp/audit-logger-${local.suffix}.zip"
}

resource "google_storage_bucket_object" "audit_logger_source" {
  name   = "audit-logger-${data.archive_file.audit_logger_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.audit_logger_zip.output_path
}

resource "google_cloudfunctions2_function" "audit_logger" {
  project  = var.project_id
  name     = "audit-logger-${local.suffix}"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "audit_logger"
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.audit_logger_source.name
      }
    }
  }

  service_config {
    max_instance_count    = 3
    min_instance_count    = 0
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = var.audit_logger_sa_email

    environment_variables = {
      GCP_PROJECT        = var.project_id
      BQ_DATASET_RAW     = var.bq_dataset_raw
      BQ_TABLE_AUDIT_LOG = var.bq_table_audit_log
    }
  }

  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.pubsub_topic_id
    service_account_email = var.audit_logger_sa_email
    retry_policy          = "RETRY_POLICY_RETRY"
  }

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}
