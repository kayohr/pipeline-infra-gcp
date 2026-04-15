# pipeline-infra-gcp

Pipeline de dados end-to-end na GCP, com ingestão automática, transformação via dbt e notificações por email. Toda a infraestrutura é provisionada como código com Terraform.

---

## Arquitetura

```
Cloud Scheduler (hourly)
    │
    ▼
Cloud Function: ingestor
    │  busca dados da Open-Meteo API (SP, RJ, Curitiba)
    │  grava em BigQuery raw_dev.clima_raw
    │
    ├──► Pub/Sub topic: pipeline-eventos-dev
    │         │
    │         ├── status=sucesso → Cloud Function: audit-logger → BQ pipeline_audit_log
    │         └── status=erro   → Cloud Function: notificador  → email via SendGrid
    │
Cloud Scheduler (10min depois)
    │
    ▼
Cloud Run Job: dbt-runner
    │  dbt run  → staging_dev.stg_clima (view)
    └──          → marts_dev.mart_clima_diario (incremental)
```

---

## Stack

| Camada | Tecnologia |
|---|---|
| IaC | Terraform ~> 5.0 (backend local) |
| Ingestão | Cloud Functions gen2 (Python 3.11) |
| Mensageria | Pub/Sub + Eventarc |
| Transformação | dbt Core 1.8 + BigQuery adapter |
| Orquestração | Cloud Scheduler (cron) |
| Container | Cloud Run Job (Docker) |
| Armazenamento | BigQuery (raw / staging / marts) |
| Segredos | Secret Manager |
| Email | SendGrid |
| Dev local | Docker Compose |

---

## Estrutura

```
.
├── terraform/
│   ├── provider.tf                  # Google provider, backend local
│   ├── environments/dev/            # Orquestração do ambiente dev
│   │   ├── main.tf                  # Instância de todos os módulos
│   │   ├── terraform.tfvars         # Valores públicos (region, environment)
│   │   └── secret.auto.tfvars       # project_id, sendgrid_api_key [gitignored]
│   └── modules/
│       ├── iam/                     # Service accounts + bindings
│       ├── bigquery/                # Datasets e tabelas
│       ├── pubsub/                  # Tópico + dead-letter
│       ├── secret_manager/          # Secrets do projeto
│       ├── cloud_functions/         # ingestor, notificador, audit-logger
│       ├── cloud_run/               # dbt-runner job
│       └── scheduler/               # Cron jobs
├── functions/
│   ├── ingestor/                    # Busca Open-Meteo → BQ + Pub/Sub
│   ├── notificador/                 # Pub/Sub → SendGrid email
│   └── audit_logger/                # Pub/Sub → BQ audit log
├── dbt/
│   ├── models/
│   │   ├── staging/                 # Views de limpeza (stg_clima)
│   │   └── marts/                   # Tabelas analíticas incrementais
│   ├── macros/                      # generate_schema_name customizado
│   └── profiles.yml                 # Conexão BigQuery (oauth / service account)
├── docs/
│   └── terraform-guide.md           # Guia Terraform do zero ao deploy
├── github-preview/                  # Snapshot sanitizado do ambiente dev
├── docker-compose.yml               # Terraform + dbt sem instalar localmente
├── GUIDE.md                         # Guia técnico completo do projeto
└── .env                             # Variáveis locais [gitignored]
```

---

## Pré-requisitos

- Docker Desktop rodando
- Conta GCP com faturamento ativo
- `gcloud` CLI autenticado (`gcloud auth application-default login`)
- Projeto GCP criado e ID disponível
- Conta SendGrid com API key

APIs GCP necessárias:
```
bigquery, cloudfunctions, run, cloudscheduler, pubsub,
secretmanager, eventarc, artifactregistry, cloudbuild
```

---

## Como rodar

### 1. Configurar segredos locais

Copie o exemplo e preencha com seus valores:
```bash
cp terraform/environments/dev/secret.auto.tfvars.example \
   terraform/environments/dev/secret.auto.tfvars
```

Edite `secret.auto.tfvars`:
```hcl
project_id         = "seu-projeto-gcp"
sendgrid_api_key   = "SG.xxxx"
notification_email = "seu@email.com"
```

### 2. Build e push da imagem dbt-runner

Necessário antes do primeiro `terraform apply`:
```bash
docker build -t gcr.io/SEU_PROJETO/dbt-runner:latest ./dbt
docker push gcr.io/SEU_PROJETO/dbt-runner:latest
```

### 3. Provisionar infraestrutura

```bash
cd terraform/environments/dev
docker compose run --rm terraform init
docker compose run --rm terraform plan
docker compose run --rm terraform apply
```

### 4. Rodar dbt manualmente (opcional)

```bash
docker compose run --rm dbt run
docker compose run --rm dbt test
```

---

## Ambientes

| Ambiente | Status | Backend |
|---|---|---|
| dev | ativo | local (tfstate) |
| prod | planejado | GCS |

O sufixo `_dev` / `_prod` é aplicado automaticamente em todos os recursos (datasets BQ, functions, schedulers, service accounts).

---

## Documentação

- [GUIDE.md](GUIDE.md) — fluxo técnico completo, arquivo por arquivo
- [docs/terraform-guide.md](docs/terraform-guide.md) — Terraform do zero ao deploy
- [github-preview/README.md](github-preview/README.md) — recursos ativos no GCP (snapshot sanitizado)
