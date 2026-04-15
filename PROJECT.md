# Projeto Data Engineer GCP

## Objetivo

Construir um pipeline de engenharia de dados real no GCP usando Terraform local como IaC.
O projeto cobre o que um engenheiro de dados pleno GCP precisa dominar tecnicamente.

---

## Decisões arquiteturais fechadas

### Fonte de dados
- **Open-Meteo API** — API pública, sem chave, dados climáticos horários
- Cidades: São Paulo, Rio de Janeiro, Curitiba (justifica clustering no BigQuery)
- URL base: `https://api.open-meteo.com/v1/forecast`

### Terraform
- Roda **local** (na máquina do dev)
- Backend **local** (tfstate na máquina, não no GCS)
- Infraestrutura criada no **GCP via `terraform apply`**
- Ambientes: **dev** e **prod** separados via `terraform.tfvars`

### Computação
- **Cloud Functions** — ingestor, notificador, audit-logger (FaaS, serverless, event-driven)
- **Cloud Run Job** — dbt-runner (precisa de container com dbt instalado)
- **Sem Cloud Run Service** (não tem API HTTP de pé)
- **Sem GCS para dados** (API → BigQuery direto, sem intermediário)

### Orquestração
- **Cloud Scheduler** — dispara ingestor (a cada hora) e dbt-runner (após ingestão)

### Mensageria
- **Pub/Sub Topic:** `pipeline-eventos`
- **Atributo de filtro:** `status=erro` ou `status=sucesso`
- **Subscription A** (status=erro) → Cloud Function: notificador → SendGrid → email
- **Subscription B** (status=sucesso) → Cloud Function: audit-logger → BigQuery

### Notificação de erro
- **SendGrid** (transactional email, REST API, gratuito até 100 emails/dia)
- Credencial no **Secret Manager** (nunca no código)

### BigQuery — arquitetura em camadas
```
dataset: raw     → tabela: clima_raw (inserção via Cloud Function ingestor)
dataset: staging → view: stg_clima (dbt — limpeza, cast, padronização)
dataset: marts   → table: mart_clima_diario (dbt incremental — agregações)
dataset: raw     → tabela: pipeline_audit_log (registro de execuções)
```

### dbt
- **dbt Core** instalado local para desenvolvimento
- No pipeline produtivo roda via **Cloud Run Job: dbt-runner**
- Materializations: staging = view, marts = incremental table
- Testes via `schema.yml`

---

## Fluxo completo do pipeline

```
Open-Meteo API
      ↓
Cloud Scheduler (a cada hora)
      ↓
Cloud Function: ingestor
  - chama API para SP, RJ, Curitiba
  - insere em BigQuery dataset:raw → tabela:clima_raw
  ├── sucesso → Pub/Sub pipeline-eventos (status=sucesso)
  └── erro    → Pub/Sub pipeline-eventos (status=erro)
      ↓
BigQuery dataset: raw
      ↓
Cloud Scheduler (após ingestão)
      ↓
Cloud Run Job: dbt-runner
  - dbt run staging (view sobre raw)
  - dbt run marts (incremental sobre staging)
  - dbt test
  ├── sucesso → Pub/Sub pipeline-eventos (status=sucesso)
  └── erro    → Pub/Sub pipeline-eventos (status=erro)
      ↓
BigQuery dataset: staging → marts

Pub/Sub Topic: pipeline-eventos
  ├── status=erro    → Cloud Function: notificador → SendGrid → email
  └── status=sucesso → Cloud Function: audit-logger → BigQuery: pipeline_audit_log
```

---

## Estrutura de pastas

```
projeto/
├── terraform/
│   ├── modules/
│   │   ├── bigquery/
│   │   ├── pubsub/
│   │   ├── cloud_functions/
│   │   ├── cloud_run/
│   │   ├── scheduler/
│   │   └── iam/
│   ├── environments/
│   │   ├── dev/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   └── terraform.tfvars
│   │   └── prod/
│   │       ├── main.tf
│   │       ├── variables.tf
│   │       └── terraform.tfvars
│   └── provider.tf
│
├── functions/
│   ├── ingestor/
│   │   └── main.py
│   ├── notificador/
│   │   └── main.py
│   └── audit_logger/
│       └── main.py
│
├── dbt/
│   ├── dbt_project.yml
│   ├── profiles.yml
│   └── models/
│       ├── staging/
│       │   ├── sources.yml
│       │   └── stg_clima.sql
│       └── marts/
│           └── mart_clima_diario.sql
│
├── PROJECT.md
└── CLAUDE.MD
```

---

## Recursos Terraform (google_*)

| Recurso | Para quê |
|---|---|
| `google_service_account` | identidade de cada serviço |
| `google_project_iam_member` | permissões mínimas por SA |
| `google_secret_manager_secret` | sendgrid_api_key |
| `google_bigquery_dataset` | raw, staging, marts |
| `google_bigquery_table` | clima_raw, pipeline_audit_log |
| `google_pubsub_topic` | pipeline-eventos |
| `google_pubsub_subscription` | subscription erro e sucesso |
| `google_cloudfunctions2_function` | ingestor, notificador, audit-logger |
| `google_cloud_run_v2_job` | dbt-runner |
| `google_cloud_scheduler_job` | ingestor (horário) e dbt-runner |

---

## Issues — ordem de execução

### Bloco 1 — Fundação (fazer primeiro)
- [ ] Autenticação GCP local (`gcloud auth login`, `gcloud auth application-default login`)
- [ ] Criar estrutura de pastas do projeto
- [ ] Configurar `provider.tf` e `variables.tf` base (projeto, região, ambiente)

### Bloco 2 — Segurança (antes dos serviços)
- [ ] Módulo IAM: service accounts + permissões mínimas por serviço
- [ ] Módulo Secret Manager: secret `sendgrid_api_key`

### Bloco 3 — Dados (antes das functions)
- [ ] Módulo BigQuery: datasets raw, staging, marts + tabelas clima_raw e pipeline_audit_log
- [ ] Módulo Pub/Sub: topic pipeline-eventos + subscriptions com filtro por atributo

### Bloco 4 — Serviços
- [ ] Cloud Function: ingestor (Open-Meteo → BigQuery raw + Pub/Sub)
- [ ] Cloud Function: notificador (Pub/Sub erro → SendGrid → email)
- [ ] Cloud Function: audit-logger (Pub/Sub sucesso → BigQuery pipeline_audit_log)
- [ ] Cloud Run Job: dbt-runner (container com dbt-core + dbt-bigquery)
- [ ] Módulo Scheduler: jobs para ingestor e dbt-runner

### Bloco 5 — Transformação
- [ ] Projeto dbt: sources.yml, stg_clima.sql, mart_clima_diario.sql, testes

### Bloco 6 — Ambientes e validação
- [ ] Configurar environments dev e prod com terraform.tfvars separados
- [ ] Validar `terraform plan` no ambiente dev antes de aplicar

---

## Status atual

> Fase: **planejamento concluído** — ainda não foi escrita nenhuma linha de código ou arquivo Terraform.
> Próximo passo: **Bloco 1 — autenticação GCP local**.
