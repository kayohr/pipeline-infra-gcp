terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "local" {
    path = "terraform.tfstate"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

module "iam" {
  source      = "../../modules/iam"
  project_id  = var.project_id
  environment = var.environment
}

module "secret_manager" {
  source           = "../../modules/secret_manager"
  project_id       = var.project_id
  environment      = var.environment
  sendgrid_api_key = var.sendgrid_api_key
}

module "bigquery" {
  source      = "../../modules/bigquery"
  project_id  = var.project_id
  environment = var.environment
  region      = var.region
}

module "pubsub" {
  source      = "../../modules/pubsub"
  project_id  = var.project_id
  environment = var.environment
}

module "cloud_functions" {
  source                    = "../../modules/cloud_functions"
  project_id                = var.project_id
  region                    = var.region
  environment               = var.environment
  ingestor_sa_email         = module.iam.ingestor_sa_email
  notificador_sa_email      = module.iam.notificador_sa_email
  audit_logger_sa_email     = module.iam.audit_logger_sa_email
  pubsub_topic_id           = module.pubsub.topic_id
  sendgrid_secret_id        = module.secret_manager.sendgrid_secret_id
  notification_email        = var.notification_email
  bq_dataset_raw            = module.bigquery.dataset_raw_id
  bq_table_clima_raw        = module.bigquery.table_clima_raw_id
  bq_table_audit_log        = module.bigquery.table_audit_log_id
}

module "cloud_run" {
  source          = "../../modules/cloud_run"
  project_id      = var.project_id
  region          = var.region
  environment     = var.environment
  dbt_runner_sa   = module.iam.dbt_runner_sa_email
  pubsub_topic_id = module.pubsub.topic_id
}

module "scheduler" {
  source                  = "../../modules/scheduler"
  project_id              = var.project_id
  region                  = var.region
  environment             = var.environment
  ingestor_function_uri   = module.cloud_functions.ingestor_uri
  dbt_runner_job_name     = module.cloud_run.dbt_runner_job_name
}
