variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "us-central1"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "sendgrid_api_key" {
  type      = string
  sensitive = true
}

variable "notification_email" {
  type = string
}
