variable "project_id" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "ingestor_sa_email" {
  type = string
}

variable "notificador_sa_email" {
  type = string
}

variable "audit_logger_sa_email" {
  type = string
}

variable "pubsub_topic_id" {
  type = string
}

variable "sendgrid_secret_id" {
  type = string
}

variable "notification_email" {
  type = string
}

variable "bq_dataset_raw" {
  type = string
}

variable "bq_table_clima_raw" {
  type = string
}

variable "bq_table_audit_log" {
  type = string
}
