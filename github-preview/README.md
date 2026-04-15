# github-preview — O que está rodando na nuvem

Snapshot do ambiente **dev** após `terraform apply`.
Mostra os recursos reais criados no GCP, com dados sensíveis substituídos por placeholders.

Projeto GCP: `YOUR_GCP_PROJECT_ID`
Região: `us-central1`
Data: 2026-04-15

> Estes arquivos são só para visualização — não são usados para deploy.
> O deploy é feito pelo Terraform na pasta `/terraform`.

---

## Recursos ativos no GCP

### BigQuery
| Dataset | Localização | Descrição |
|---|---|---|
| `raw_dev` | us-central1 | Dados brutos ingeridos pelo ingestor |
| `staging_dev` | us-central1 | Views dbt de limpeza |
| `marts_dev` | us-central1 | Tabelas analíticas incrementais |

### Cloud Functions
| Function | Trigger | O que faz |
|---|---|---|
| `ingestor-dev` | HTTP (Cloud Scheduler) | Busca Open-Meteo → BQ + Pub/Sub |
| `notificador-dev` | Pub/Sub (status=erro) | Envia email via SendGrid |
| `audit-logger-dev` | Pub/Sub (status=sucesso) | Grava audit log no BQ |

### Cloud Run Job
| Job | Imagem | O que faz |
|---|---|---|
| `dbt-runner-dev` | `gcr.io/YOUR_GCP_PROJECT_ID/dbt-runner:latest` | Roda dbt run + dbt test |

### Cloud Scheduler
| Job | Horário | Alvo |
|---|---|---|
| `scheduler-ingestor-dev` | `0 * * * *` (todo início de hora) | ingestor-dev |
| `scheduler-dbt-runner-dev` | `10 * * * *` (10min depois) | dbt-runner-dev |

### Pub/Sub
- Tópico: `pipeline-eventos-dev`
- Mensagens com `status=sucesso` → audit-logger
- Mensagens com `status=erro` → notificador

### IAM — Service Accounts criadas
| Service Account | Usado por |
|---|---|
| `sa-ingestor-dev` | Cloud Function ingestor |
| `sa-notificador-dev` | Cloud Function notificador |
| `sa-audit-logger-dev` | Cloud Function audit-logger |
| `sa-dbt-runner-dev` | Cloud Run Job dbt-runner |
| `sa-scheduler-dev` | Cloud Scheduler |

---

## Arquivos nesta pasta

| Arquivo | Conteúdo |
|---|---|
| `terraform-state.txt` | Estado completo dos recursos gerenciados pelo Terraform |
| `function-*.json` | Configuração real de cada Cloud Function |
| `cloudrun-job-dbt-runner.json` | Configuração do Cloud Run Job |
| `scheduler-*.json` | Configuração dos Cloud Schedulers |
| `pubsub-topic.json` | Configuração do tópico Pub/Sub |
| `bq-dataset-*.json` | Metadados dos datasets BigQuery |
| `bq-table-*.json` | Schemas das tabelas (clima_raw, pipeline_audit_log) |
| `iam-service-accounts.json` | Service accounts criadas |
| `sample-data-marts.json` | Amostra dos dados em marts_dev.mart_clima_diario |
