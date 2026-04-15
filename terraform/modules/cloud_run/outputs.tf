output "dbt_runner_job_name" {
  value = google_cloud_run_v2_job.dbt_runner.name
}

output "dbt_runner_job_id" {
  value = google_cloud_run_v2_job.dbt_runner.id
}
