output "sendgrid_secret_id" {
  value = google_secret_manager_secret.sendgrid_api_key.secret_id
}

output "sendgrid_secret_name" {
  value = google_secret_manager_secret.sendgrid_api_key.name
}
