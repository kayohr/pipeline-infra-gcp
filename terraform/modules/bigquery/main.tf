locals {
  suffix = var.environment
}

# Datasets
resource "google_bigquery_dataset" "raw" {
  project                    = var.project_id
  dataset_id                 = "raw_${local.suffix}"
  friendly_name              = "Raw (${local.suffix})"
  description                = "Dados brutos ingeridos diretamente das fontes"
  location                   = "us-central1"
  delete_contents_on_destroy = var.environment == "dev" ? true : false

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

resource "google_bigquery_dataset" "staging" {
  project                    = var.project_id
  dataset_id                 = "staging_${local.suffix}"
  friendly_name              = "Staging (${local.suffix})"
  description                = "Views dbt de limpeza e padronização"
  location                   = "us-central1"
  delete_contents_on_destroy = var.environment == "dev" ? true : false

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

resource "google_bigquery_dataset" "marts" {
  project                    = var.project_id
  dataset_id                 = "marts_${local.suffix}"
  friendly_name              = "Marts (${local.suffix})"
  description                = "Tabelas analíticas finais (dbt incremental)"
  location                   = "us-central1"
  delete_contents_on_destroy = var.environment == "dev" ? true : false

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }
}

# Tabela: clima_raw
resource "google_bigquery_table" "clima_raw" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  table_id   = "clima_raw"

  description = "Dados climáticos horários brutos do Open-Meteo"

  time_partitioning {
    type  = "DAY"
    field = "ingest_timestamp"
  }

  clustering = ["cidade"]

  schema = jsonencode([
    { name = "cidade",            type = "STRING",    mode = "REQUIRED", description = "Nome da cidade" },
    { name = "latitude",          type = "FLOAT64",   mode = "NULLABLE", description = "Latitude da cidade" },
    { name = "longitude",         type = "FLOAT64",   mode = "NULLABLE", description = "Longitude da cidade" },
    { name = "timestamp_utc",     type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp da medição (UTC)" },
    { name = "temperatura_c",     type = "FLOAT64",   mode = "NULLABLE", description = "Temperatura em Celsius" },
    { name = "umidade_pct",       type = "INT64",     mode = "NULLABLE", description = "Umidade relativa (%)" },
    { name = "precipitacao_mm",   type = "FLOAT64",   mode = "NULLABLE", description = "Precipitação (mm)" },
    { name = "vento_kmh",         type = "FLOAT64",   mode = "NULLABLE", description = "Velocidade do vento (km/h)" },
    { name = "ingest_timestamp",  type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp de ingestão no BigQuery" }
  ])

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }

  deletion_protection = var.environment == "prod" ? true : false
}

# Tabela: pipeline_audit_log
resource "google_bigquery_table" "pipeline_audit_log" {
  project    = var.project_id
  dataset_id = google_bigquery_dataset.raw.dataset_id
  table_id   = "pipeline_audit_log"

  description = "Registro de execuções bem-sucedidas do pipeline"

  time_partitioning {
    type  = "DAY"
    field = "event_timestamp"
  }

  schema = jsonencode([
    { name = "event_id",        type = "STRING",    mode = "REQUIRED", description = "UUID do evento" },
    { name = "service",         type = "STRING",    mode = "REQUIRED", description = "Serviço que gerou o evento" },
    { name = "status",          type = "STRING",    mode = "REQUIRED", description = "Status: sucesso ou erro" },
    { name = "message",         type = "STRING",    mode = "NULLABLE", description = "Mensagem de log" },
    { name = "event_timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Timestamp do evento" },
    { name = "metadata",        type = "JSON",      mode = "NULLABLE", description = "Metadados adicionais em JSON" }
  ])

  labels = {
    environment = local.suffix
    managed_by  = "terraform"
  }

  deletion_protection = var.environment == "prod" ? true : false
}
