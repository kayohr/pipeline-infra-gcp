# Guia Técnico — Pipeline de Dados GCP

Este guia cobre o fluxo completo do projeto: do código local até os dados disponíveis para análise no BigQuery. Cada seção explica o que roda, qual arquivo é responsável, por que existe e o que acontece a seguir.

---

## Visão geral da arquitetura

```
SUA MÁQUINA (local)
├── Docker          → isola Terraform e dbt sem instalar na máquina
├── Terraform       → declara e provisiona toda a infraestrutura no GCP
└── dbt (local)     → desenvolve e testa transformações SQL

GCP (nuvem, roda sozinho após o deploy)
├── Cloud Scheduler      → dispara jobs por horário (cron)
├── Cloud Functions      → ingestor, notificador, audit-logger (FaaS)
├── Pub/Sub              → mensageria assíncrona entre serviços
├── Secret Manager       → armazena credenciais com segurança
├── Cloud Run Job        → container dbt-runner (transformações)
└── BigQuery             → data warehouse em camadas (raw → staging → marts)
```

---

## Parte 1 — Infraestrutura como Código (IaC) com Terraform

### Por que Terraform?

Terraform é uma ferramenta de **IaC (Infrastructure as Code)** — você descreve o estado desejado da infraestrutura em arquivos `.tf` (HCL, HashiCorp Configuration Language) e o Terraform calcula o que precisa criar, modificar ou destruir para chegar nesse estado. Isso substitui clicar no console do GCP manualmente e garante que o ambiente seja **reproduzível**, **versionado** e **auditável**.

### Por que Docker para rodar o Terraform?

O Terraform não está instalado na máquina. O [docker-compose.yml](docker-compose.yml) define um serviço que usa a imagem oficial `hashicorp/terraform:1.8` — um container temporário que sobe, executa o comando e some. As credenciais GCP (`~/.config/gcloud/`) são montadas como volume read-only, então o Terraform autentica na API do Google sem precisar de chave de serviço.

```yaml
# docker-compose.yml
services:
  terraform:
    image: hashicorp/terraform:1.8
    working_dir: /workspace/terraform/environments/dev
    volumes:
      - .:/workspace                              # projeto inteiro montado
      - ~/.config/gcloud:/root/.config/gcloud:ro  # credenciais GCP (read-only)
```

### Estrutura modular do Terraform

```
terraform/
├── provider.tf                    # configura o provider Google e o backend local
├── variables.tf                   # declara tipos das variáveis globais
└── environments/
│   ├── dev/
│   │   ├── main.tf                # ponto de entrada — chama todos os módulos
│   │   ├── variables.tf           # tipos das variáveis do ambiente
│   │   ├── terraform.tfvars       # valores públicos (region, environment)
│   │   └── secret.auto.tfvars    # valores sensíveis — NÃO vai pro Git
│   └── prod/
│       └── (mesma estrutura)
└── modules/
    ├── iam/           bigquery/   pubsub/
    ├── secret_manager/            cloud_functions/
    ├── cloud_run/     scheduler/
```

Cada módulo é independente e reutilizável entre dev e prod. O `main.tf` do ambiente orquestra todos os módulos passando outputs de um como inputs de outro — por exemplo, o email do service account criado pelo módulo `iam` é passado diretamente para o módulo `cloud_functions`.

### Os três comandos

```bash
docker compose run --rm terraform init
```
**O que faz:** baixa os providers (plugin `hashicorp/google ~> 5.0`) e inicializa o backend. O backend está configurado como `local` em [terraform/provider.tf](terraform/provider.tf) — o `terraform.tfstate` fica na máquina, não no GCS. O `tfstate` é o arquivo que registra o estado atual de cada recurso criado no GCP.

```bash
docker compose run --rm terraform plan
```
**O que faz:** compara o estado desejado (arquivos `.tf`) com o estado atual (`tfstate`) e mostra o diff — o que será criado, modificado ou destruído. Não altera nada. É o "dry run" antes de aplicar.

```bash
docker compose run --rm terraform apply
```
**O que faz:** executa o plano. Para cada recurso declarado, chama a API correspondente do GCP (`google_bigquery_dataset` → BigQuery API, `google_cloudfunctions2_function` → Cloud Functions API, etc). Ao final, atualiza o `tfstate` com os IDs e metadados de tudo que foi criado.

### O que o Terraform cria e em que ordem

O Terraform resolve o grafo de dependências automaticamente. Recursos que dependem de outros esperam — por exemplo, a Cloud Function só é criada após o bucket GCS existir, e o bucket só após o IAM estar configurado.

**1. [modules/iam/main.tf](terraform/modules/iam/main.tf) — Identidade e permissões**

Cria 5 `google_service_account` (uma por serviço) e vincula roles mínimas via `google_project_iam_member`:
- `sa-ingestor-dev` → `roles/bigquery.dataEditor` + `roles/pubsub.publisher`
- `sa-notificador-dev` → `roles/secretmanager.secretAccessor` + `roles/pubsub.subscriber`
- `sa-audit-logger-dev` → `roles/bigquery.dataEditor` + `roles/pubsub.subscriber`
- `sa-dbt-runner-dev` → `roles/bigquery.dataEditor` + `roles/pubsub.publisher`
- `sa-scheduler-dev` → `roles/run.invoker`

**Princípio aplicado:** least privilege — cada serviço tem acesso apenas ao que precisa, nada além.

**2. [modules/secret_manager/main.tf](terraform/modules/secret_manager/main.tf) — Credenciais seguras**

Cria um `google_secret_manager_secret` com o ID `sendgrid-api-key-dev` e uma `google_secret_manager_secret_version` com o valor real da chave. A chave vem de `var.sendgrid_api_key`, que é lida do `secret.auto.tfvars` (nunca hardcoded no código). O notificador acessa via API do Secret Manager em runtime — nunca a chave é exposta como variável de ambiente.

**3. [modules/bigquery/main.tf](terraform/modules/bigquery/main.tf) — Data warehouse em camadas**

Cria 3 datasets na região `us-central1` e 2 tabelas:

| Recurso | ID | Papel na arquitetura |
|---|---|---|
| `google_bigquery_dataset` | `raw_dev` | zona de aterrissagem dos dados brutos |
| `google_bigquery_dataset` | `staging_dev` | zona de transformação (views dbt) |
| `google_bigquery_dataset` | `marts_dev` | zona analítica (tabelas incrementais dbt) |
| `google_bigquery_table` | `raw_dev.clima_raw` | recebe dados do ingestor — particionada por `ingest_timestamp` (DAY), clusterizada por `cidade` |
| `google_bigquery_table` | `raw_dev.pipeline_audit_log` | recebe eventos de sucesso do pipeline — particionada por `event_timestamp` |

**Particionamento** reduz custo e tempo de query — ao filtrar por data, o BigQuery lê apenas as partições relevantes em vez da tabela inteira. **Clustering** por `cidade` organiza os dados fisicamente no disco, otimizando queries que filtram por cidade.

**4. [modules/pubsub/main.tf](terraform/modules/pubsub/main.tf) — Mensageria assíncrona**

Cria o tópico `pipeline-eventos-dev` e uma subscription `dead-letter` para observabilidade. O Pub/Sub desacopla os serviços — o ingestor publica uma mensagem e não sabe nem se importa quem vai consumi-la. As Cloud Functions (notificador e audit-logger) são conectadas ao tópico via Eventarc no módulo cloud_functions, que cria as subscriptions automaticamente.

**5. [modules/cloud_functions/main.tf](terraform/modules/cloud_functions/main.tf) — Deploy das functions**

Para cada function, o Terraform executa 3 passos:
1. `data "archive_file"` — empacota o diretório `functions/<nome>/` em `.zip`, calcula o MD5
2. `google_storage_bucket_object` — faz upload do `.zip` no bucket GCS usando o MD5 no nome (garante que mudanças no código trigam redeploy)
3. `google_cloudfunctions2_function` — cria a Cloud Function gen2 apontando para o objeto no GCS

As functions com `event_trigger` (notificador e audit-logger) têm o Eventarc configurado para escutar o tópico Pub/Sub. A filtragem por `status=erro` ou `status=sucesso` é feita dentro do código Python, não no trigger (limitação do Eventarc com Pub/Sub).

**6. [modules/cloud_run/main.tf](terraform/modules/cloud_run/main.tf) — Container de transformação**

Cria um `google_cloud_run_v2_job` apontando para a imagem `gcr.io/PROJECT/dbt-runner:latest`. Esta imagem é buildada localmente (`docker build`) a partir do [dbt/Dockerfile](dbt/Dockerfile) e pushed para o GCR antes do `terraform apply`. O Cloud Run Job **não fica de pé** — ele sobe sob demanda, executa e termina (diferente de um Cloud Run Service que fica ouvindo HTTP).

**7. [modules/scheduler/main.tf](terraform/modules/scheduler/main.tf) — Orquestração por horário**

Cria 2 `google_cloud_scheduler_job`:
- `scheduler-ingestor-dev`: cron `0 * * * *` — dispara HTTP POST autenticado (OIDC) para a URL da Cloud Function ingestor todo início de hora
- `scheduler-dbt-runner-dev`: cron `10 * * * *` — dispara HTTP POST autenticado (OAuth2) para a API do Cloud Run executar o job dbt-runner 10 minutos depois

**Limitação conhecida:** o Cloud Scheduler não tem dependência entre jobs — ele dispara por horário de relógio. Os 10 minutos são um workaround. A solução robusta seria o próprio ingestor disparar o dbt via API do Cloud Run ao terminar com sucesso.

---

## Parte 2 — Ingestão de dados (Cloud Function: ingestor)

### Arquivo: [functions/ingestor/main.py](functions/ingestor/main.py)

Após o `terraform apply`, esta função existe no GCP como um container gerenciado pelo Cloud Functions gen2 (por baixo é um Cloud Run Service). O Cloud Scheduler a dispara via HTTP POST autenticado com um token OIDC gerado pelo service account `sa-scheduler-dev`.

**Fluxo interno da função:**

```python
# 1. Para cada cidade (São Paulo, Rio de Janeiro, Curitiba):
rows = buscar_clima(cidade)
#    └── GET https://api.open-meteo.com/v1/forecast?latitude=...&hourly=temperature_2m,...
#        retorna 24 registros horários (forecast_days=1)

# 2. Insere todos os registros no BigQuery via Streaming Insert
bq_client.insert_rows_json("PROJECT.raw_dev.clima_raw", rows)
#    └── cada linha tem: cidade, lat, lon, timestamp_utc, temperatura_c,
#        umidade_pct, precipitacao_mm, vento_kmh, ingest_timestamp

# 3. Publica resultado no Pub/Sub com atributo de status
pubsub_client.publish(topic_path, payload, status="sucesso")  # ou "erro"
```

**Por que Streaming Insert?** O método `insert_rows_json` do cliente BigQuery usa a API de streaming — os dados ficam disponíveis para query em segundos, sem necessidade de job de load. A tabela `clima_raw` usa **particionamento por ingest_timestamp (DAY)** — cada execução horária cai na partição do dia correto automaticamente.

**Por que Pub/Sub e não chamar o audit-logger diretamente?** Desacoplamento. O ingestor não precisa saber o que acontece após publicar. Se o audit-logger estiver fora do ar, a mensagem fica retida no Pub/Sub por até 1 dia (configurado em `message_retention_duration`). Novos consumidores podem ser adicionados sem alterar o ingestor.

---

## Parte 3 — Mensageria e event-driven com Pub/Sub

### Tópico: `pipeline-eventos-dev`

Cada mensagem publicada no tópico tem:
- **body (JSON):** `event_id`, `service`, `status`, `message`, `event_timestamp`
- **atributo:** `status=sucesso` ou `status=erro`

O Eventarc (camada de eventos do GCP) cria automaticamente subscriptions push para as Cloud Functions configuradas com `event_trigger`. Quando uma mensagem chega no tópico, o Eventarc entrega para **ambas** as functions. Cada function verifica o atributo `status` no início e retorna imediatamente se não for o seu caso — filtragem no código, não no broker.

```python
# functions/notificador/main.py e audit_logger/main.py
atributos = cloud_event.data["message"].get("attributes", {})
if atributos.get("status") != "erro":  # ou "sucesso"
    return  # descarta silenciosamente
```

---

## Parte 4 — Notificação de erro (Cloud Function: notificador)

### Arquivo: [functions/notificador/main.py](functions/notificador/main.py)

Ativada pelo Eventarc quando uma mensagem com `status=erro` chega no tópico.

```python
# 1. Acessa a chave SendGrid no Secret Manager em runtime
name = f"projects/{PROJECT_ID}/secrets/sendgrid-api-key-dev/versions/latest"
response = sm_client.access_secret_version(request={"name": name})
api_key = response.payload.data.decode("utf-8")

# 2. Chama a API REST do SendGrid
requests.post("https://api.sendgrid.com/v3/mail/send", json=payload,
              headers={"Authorization": f"Bearer {api_key}"})
```

**Por que Secret Manager e não variável de ambiente?** Variáveis de ambiente em Cloud Functions ficam visíveis no console do GCP para qualquer pessoa com acesso ao projeto. O Secret Manager adiciona uma camada de controle — só o service account `sa-notificador-dev` com a role `secretAccessor` pode ler o secret.

---

## Parte 5 — Audit log (Cloud Function: audit-logger)

### Arquivo: [functions/audit_logger/main.py](functions/audit_logger/main.py)

Ativada pelo Eventarc quando uma mensagem com `status=sucesso` chega no tópico. Insere um registro na tabela `raw_dev.pipeline_audit_log` com os metadados da execução — quem rodou, quando, qual mensagem. Funciona como **observabilidade** do pipeline: permite consultar o histórico de execuções diretamente no BigQuery.

---

## Parte 6 — Transformação com dbt (Cloud Run Job: dbt-runner)

### Por que dbt?

dbt (data build tool) trata transformações SQL como código — com versionamento, testes, documentação e DAG de dependências. Em vez de escrever SQL em um notebook ou job avulso, o dbt gerencia a ordem de execução dos modelos, cria as relações no BigQuery e valida a qualidade dos dados automaticamente.

### A imagem Docker

O [dbt/Dockerfile](dbt/Dockerfile) instala `dbt-core` e `dbt-bigquery` em cima de `python:3.11-slim`. O [dbt/entrypoint.sh](dbt/entrypoint.sh) é o script de entrada — roda `dbt run`, `dbt test` e publica o resultado no Pub/Sub. Esta imagem é buildada localmente e pushed para o GCR antes do deploy:

```bash
docker build -t gcr.io/PROJECT/dbt-runner:latest ./dbt/
docker push gcr.io/PROJECT/dbt-runner:latest
```

O Cloud Run Job aponta para esta imagem. Quando o Scheduler o dispara, o GCP puxa a imagem do GCR e executa o container.

### Perfil de conexão

O [dbt/profiles.yml](dbt/profiles.yml) configura como o dbt se conecta ao BigQuery:
- **dev:** método `oauth` — usa as credenciais da sua conta pessoal (`gcloud auth application-default login`)
- **prod:** método `service-account-impersonation` — o container assume a identidade do `sa-dbt-runner-dev`

O dataset base é `raw_dev` (onde estão os dados brutos), mas a macro `generate_schema_name` controla onde cada modelo é materializado.

### A macro generate_schema_name

O arquivo [dbt/macros/generate_schema_name.sql](dbt/macros/generate_schema_name.sql) sobrescreve o comportamento padrão do dbt, que concatenaria o dataset do profile com o schema do modelo (resultaria em `raw_dev_staging`). A macro garante que:
- modelos com `+schema: staging` vão para `staging_dev`
- modelos com `+schema: marts` vão para `marts_dev`

```sql
{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- set env = env_var('ENVIRONMENT', 'dev') -%}
  {%- if custom_schema_name is none -%}
    {{ default_schema }}
  {%- else -%}
    {{ custom_schema_name }}_{{ env }}  {# staging_dev, marts_dev #}
  {%- endif -%}
{%- endmacro %}
```

### Modelo staging: [dbt/models/staging/stg_clima.sql](dbt/models/staging/stg_clima.sql)

**Materialização: view** — não armazena dados, executa a query sob demanda. Serve como camada de limpeza e padronização sobre o raw.

```sql
-- lê de raw_dev.clima_raw via source()
select
    cidade, latitude, longitude,
    cast(timestamp_utc as timestamp)           as timestamp_utc,
    coalesce(cast(temperatura_c as float64), 0.0) as temperatura_c,
    -- ... casts e tratamento de nulos
    date(timestamp_utc)                        as data_medicao,
    extract(hour from timestamp_utc)           as hora_medicao
from source
where timestamp_utc is not null and cidade is not null
```

A referência `{{ source('raw', 'clima_raw') }}` é declarada em [dbt/models/staging/sources.yml](dbt/models/staging/sources.yml) — o dbt usa isso para montar o grafo de dependências e para os testes de source.

### Modelo marts: [dbt/models/marts/mart_clima_diario.sql](dbt/models/marts/mart_clima_diario.sql)

**Materialização: incremental com estratégia merge** — na primeira execução cria a tabela completa. Nas seguintes, processa apenas os últimos 2 dias e faz MERGE por `(cidade, data_medicao)`, evitando reprocessar o histórico inteiro.

```sql
{{ config(
    materialized='incremental',
    unique_key=['cidade', 'data_medicao'],
    partition_by={'field': 'data_medicao', 'data_type': 'date', 'granularity': 'day'},
    cluster_by=['cidade'],
    incremental_strategy='merge'
) }}

{% if is_incremental() %}
where data_medicao >= date_sub(current_date(), interval 2 day)
{% endif %}
```

**Por que incremental?** A tabela `clima_raw` cresce 72 linhas por hora (3 cidades × 24h). Reprocessar tudo a cada hora seria custoso. O incremental processa só o delta, mantendo o histórico acumulado.

### Testes dbt

Declarados em [dbt/models/staging/sources.yml](dbt/models/staging/sources.yml) e [dbt/models/marts/schema.yml](dbt/models/marts/schema.yml). O comando `dbt test` valida:
- `not_null` — campos obrigatórios não podem ser nulos
- `accepted_values` — cidade só pode ser São Paulo, Rio de Janeiro ou Curitiba

Se um teste falha, o `entrypoint.sh` captura o exit code e publica `status=erro` no Pub/Sub, disparando o email de notificação.

---

## Parte 7 — Desenvolvimento local com dbt

Para desenvolver e testar modelos sem esperar o Cloud Run Job:

```bash
docker compose run --rm dbt run --target dev    # executa todos os modelos
docker compose run --rm dbt test --target dev   # roda os testes
docker compose run --rm dbt run --select stg_clima --target dev  # modelo específico
```

O mesmo container que roda no Cloud Run Job é usado localmente — garante paridade entre desenvolvimento e produção.

---

## Parte 8 — Ambientes dev e prod

O projeto tem dois ambientes isolados. O ambiente `prod` usa os mesmos módulos Terraform com sufixo `-prod` em todos os recursos:

```
dev:  raw_dev, staging_dev, marts_dev, ingestor-dev, sa-ingestor-dev ...
prod: raw_prod, staging_prod, marts_prod, ingestor-prod, sa-ingestor-prod ...
```

Para subir o prod:
```bash
# trocar o working_dir no docker-compose.yml para /workspace/terraform/environments/prod
docker compose run --rm terraform init
docker compose run --rm terraform apply
```

Os dois ambientes vivem no mesmo projeto GCP mas são completamente isolados — datasets separados, service accounts separadas, schedulers separados.

---

## Fluxo completo — arquivo por arquivo

```
SUA MÁQUINA
│
├─ docker-compose.yml
│   └── define containers terraform e dbt com volumes e env vars
│
├─ terraform/environments/dev/secret.auto.tfvars   ← project_id, sendgrid_key
├─ terraform/environments/dev/terraform.tfvars     ← region, environment
│
│  $ docker compose run --rm terraform init
│       └── lê: provider.tf → baixa hashicorp/google ~> 5.0
│               escreve: .terraform.lock.hcl
│
│  $ docker compose run --rm terraform plan
│       └── lê todos os .tf → compara com terraform.tfstate
│               mostra diff sem aplicar
│
│  $ docker compose run --rm terraform apply
│       └── chama API GCP para cada recurso em ordem de dependência:
│
│           modules/iam/main.tf
│           └── POST googleapis.com/iam/v1/projects/.../serviceAccounts
│               POST googleapis.com/cloudresourcemanager/v1/projects/.../setIamPolicy
│
│           modules/secret_manager/main.tf
│           └── POST secretmanager.googleapis.com/v1/projects/.../secrets
│               POST .../versions → armazena sendgrid_api_key
│
│           modules/bigquery/main.tf
│           └── POST bigquery.googleapis.com/bigquery/v2/projects/.../datasets
│               POST .../tables → cria clima_raw (schema + partição + cluster)
│               POST .../tables → cria pipeline_audit_log
│
│           modules/pubsub/main.tf
│           └── PUT pubsub.googleapis.com/v1/projects/.../topics/pipeline-eventos-dev
│
│           modules/cloud_functions/main.tf
│           └── data.archive_file → empacota functions/ingestor/ em .zip (MD5 no nome)
│               POST storage.googleapis.com → upload .zip no bucket GCS
│               POST cloudfunctions.googleapis.com/v2/.../functions → deploy ingestor-dev
│               (repete para notificador e audit-logger)
│               Eventarc cria subscriptions automáticas no Pub/Sub para notificador e audit-logger
│
│           modules/cloud_run/main.tf
│           └── POST run.googleapis.com/v2/projects/.../jobs → cria dbt-runner-dev
│               (aponta para gcr.io/PROJECT/dbt-runner:latest)
│
│           modules/scheduler/main.tf
│           └── POST cloudscheduler.googleapis.com/v1/.../jobs → scheduler-ingestor-dev
│               POST .../jobs → scheduler-dbt-runner-dev
│
│           escreve: terraform.tfstate (IDs e metadados de tudo criado)
│
│  Terraform termina. GCP está configurado. Máquina local não precisa mais estar ligada.
│
═══════════════════════════════════════════════════════
NO GCP — EXECUÇÃO AUTOMÁTICA A CADA HORA
═══════════════════════════════════════════════════════
│
│  00min — Cloud Scheduler: scheduler-ingestor-dev
│          └── cron "0 * * * *" → HTTP POST + OIDC token para ingestor-dev URL
│
│               Cloud Function: ingestor-dev
│               └── functions/ingestor/main.py
│                   buscar_clima() → GET api.open-meteo.com/v1/forecast (×3 cidades)
│                   inserir_bigquery() → POST bigquery.googleapis.com streaming insert
│                       └── raw_dev.clima_raw (72 linhas, partição do dia)
│                   publicar_pubsub() → POST pubsub.googleapis.com/publish
│                       └── tópico: pipeline-eventos-dev
│                           atributo: status=sucesso (ou status=erro)
│
│               Pub/Sub entrega para Eventarc → dispara as duas functions:
│
│               ┌── Cloud Function: audit-logger-dev (se status=sucesso)
│               │   └── functions/audit_logger/main.py
│               │       verifica atributo status == "sucesso"
│               │       insert_rows_json → raw_dev.pipeline_audit_log
│               │
│               └── Cloud Function: notificador-dev (se status=erro)
│                   └── functions/notificador/main.py
│                       verifica atributo status == "erro"
│                       sm_client.access_secret_version → sendgrid-api-key-dev
│                       POST api.sendgrid.com/v3/mail/send → email para você
│
│  10min — Cloud Scheduler: scheduler-dbt-runner-dev
│          └── cron "10 * * * *" → HTTP POST + OAuth2 token para Cloud Run Jobs API
│
│               Cloud Run Job: dbt-runner-dev
│               └── GCR puxa gcr.io/PROJECT/dbt-runner:latest
│                   executa dbt/entrypoint.sh
│                   │
│                   ├── dbt run --target prod
│                   │   └── lê dbt/dbt_project.yml → resolve DAG de modelos
│                   │       lê dbt/profiles.yml → conecta BigQuery us-central1
│                   │       executa dbt/models/staging/stg_clima.sql
│                   │           └── CREATE OR REPLACE VIEW staging_dev.stg_clima
│                   │               (lê raw_dev.clima_raw via source())
│                   │       executa dbt/models/marts/mart_clima_diario.sql
│                   │           └── MERGE INTO marts_dev.mart_clima_diario
│                   │               (lê staging_dev.stg_clima via ref())
│                   │               unique_key: (cidade, data_medicao)
│                   │               só processa últimos 2 dias (incremental)
│                   │
│                   ├── dbt test
│                   │   └── valida sources.yml: not_null, accepted_values
│                   │       valida schema.yml: not_null nos campos do mart
│                   │
│                   └── publica no Pub/Sub → status=sucesso ou status=erro
│                       (mesmo fluxo do ingestor: audit-logger ou notificador)
│
═══════════════════════════════════════════════════════
DADOS DISPONÍVEIS PARA ANÁLISE
═══════════════════════════════════════════════════════

BigQuery — projeto: seu_projeto — região: us-central1

raw_dev.clima_raw
  Dados brutos, 1 linha por hora por cidade
  Schema: cidade, latitude, longitude, timestamp_utc, temperatura_c,
          umidade_pct, precipitacao_mm, vento_kmh, ingest_timestamp
  Partição: DAY (ingest_timestamp) | Cluster: cidade

staging_dev.stg_clima
  VIEW — não armazena dados, executa on demand
  Dados com tipos corretos, nulos tratados, colunas derivadas (data_medicao, hora_medicao)

marts_dev.mart_clima_diario
  TABLE incremental, 1 linha por dia por cidade, histórico acumulado
  Schema: cidade, data_medicao, temperatura_media_c, temperatura_min_c,
          temperatura_max_c, umidade_media_pct, precipitacao_total_mm,
          vento_medio_kmh, vento_max_kmh, qtd_medicoes
  Partição: DAY (data_medicao) | Cluster: cidade

raw_dev.pipeline_audit_log
  TABLE, 1 linha por execução bem-sucedida
  Schema: event_id, service, status, message, event_timestamp, metadata

Conecte Looker Studio, Power BI ou qualquer ferramenta BI
diretamente em marts_dev.mart_clima_diario.
```

---

## Quando rodar cada comando

| Situação | Comando |
|---|---|
| Primeira vez / novo ambiente | `terraform init` → `terraform plan` → `terraform apply` |
| Mudou arquivo `.tf` | `terraform plan` → `terraform apply` |
| Mudou código Python das functions | `terraform apply` (reempacota o .zip pelo MD5) |
| Mudou modelo dbt local | `docker compose run --rm dbt run` |
| Mudou Dockerfile do dbt-runner | `docker build` + `docker push` + `terraform apply` |
| Verificar o que está na nuvem | `terraform show` |
| Destruir ambiente dev | `terraform destroy` |
