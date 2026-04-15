variable "project_id" {
  type = string
}

variable "environment" {
  type = string
}

variable "sendgrid_api_key" {
  type      = string
  sensitive = true
}
