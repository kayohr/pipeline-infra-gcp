# Guia Terraform — Do zero ao deploy no GCP

Este guia ensina Terraform do zero usando como base o projeto real construído aqui.
Cada conceito é explicado com o código que foi escrito, por que foi escrito assim,
e o que acontece no GCP quando você roda.

---

## O que é Terraform e por que usar

Terraform é uma ferramenta de **IaC — Infrastructure as Code**. Em vez de criar
recursos no GCP clicando no console, você descreve o que quer em arquivos de texto
(extensão `.tf`) usando uma linguagem chamada **HCL — HashiCorp Configuration Language**.

**Por que isso importa:**

| Sem Terraform | Com Terraform |
|---|---|
| Clica no console, não tem registro | Código versionado no Git |
| Refazer em outro ambiente é manual | `terraform apply` recria tudo igual |
| Difícil saber o que existe na nuvem | `terraform show` mostra o estado completo |
| Deletar recursos é arriscado | `terraform destroy` remove tudo de forma controlada |
| Dev e prod diferentes sem querer | Mesmo código, variáveis diferentes |

---

## Conceitos fundamentais antes de começar

### Resource
É a unidade básica do Terraform. Representa um recurso real na nuvem.

```hcl
resource "google_bigquery_dataset" "raw" {
  dataset_id = "raw_dev"
  location   = "us-central1"
}
```

A sintaxe é sempre: `resource "<tipo>" "<nome_local>"`. O tipo determina qual API do GCP
será chamada. O nome local é só para referenciar dentro do Terraform.

### Provider
É o plugin que sabe como falar com cada nuvem. Sem o provider, o Terraform não sabe
o que fazer com `google_bigquery_dataset`. No projeto:

```hcl
# terraform/provider.tf
terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"   # aceita 5.x, não aceita 6.x
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}
```

O `~> 5.0` é um **constraint de versão** — o operador `~>` significa "pessimistic
constraint": aceita patches e minors (5.1, 5.45) mas não majors (6.0). Isso evita
quebras por atualização automática do provider.

### State (tfstate)
O arquivo `terraform.tfstate` é o coração do Terraform. Ele registra tudo que foi
criado — IDs, metadados, dependências. Quando você roda `terraform apply` de novo,
o Terraform compara o que está no `.tf` (desejado) com o que está no `tfstate`
(real) e calcula só o diff.

**Backend local** significa que o tfstate fica na sua máquina:
```hcl
backend "local" {
  path = "terraform.tfstate"
}
```

Alternativa seria backend remoto no GCS — útil em times para compartilhar o estado.
Neste projeto usamos local porque é um projeto individual de estudo.

### Variable e Output
**Variables** são os parâmetros de entrada de um módulo ou ambiente:
```hcl
variable "project_id" {
  type = string   # string, number, bool, list, map, object
}
```

**Outputs** são os valores que um módulo expõe para outros módulos usarem:
```hcl
output "ingestor_sa_email" {
  value = google_service_account.ingestor.email
}
```

### Data source
Lê informações de recursos existentes sem criá-los. Neste projeto é usado para
empacotar o código Python em zip:
```hcl
data "archive_file" "ingestor_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../functions/ingestor"
  output_path = "/tmp/ingestor-dev.zip"
}
```

### Locals
Valores computados internamente, sem vir de fora:
```hcl
locals {
  suffix = var.environment   # "dev" ou "prod"
}
# uso: local.suffix
```

Usado em todo projeto para compor nomes de recursos: `"raw_${local.suffix}"` → `"raw_dev"`.

### Módulo
Um módulo é uma pasta com arquivos `.tf` que agrupa recursos relacionados.
Permite reutilização — o mesmo módulo `bigquery` é usado por `dev` e `prod`
com variáveis diferentes.

```
módulo = pasta com main.tf + variables.tf + outputs.tf
```

---

## Passo 1 — Estrutura de pastas

A primeira decisão em qualquer projeto Terraform é a estrutura. Existem várias
convenções. A usada aqui é **environments + modules**:

```
terraform/
├── provider.tf              # provider e backend (compartilhado)
├── variables.tf             # variáveis globais
│
├── environments/            # ponto de entrada por ambiente
│   ├── dev/
│   │   ├── main.tf          # chama os módulos
│   │   ├── variables.tf     # declara variáveis do ambiente
│   │   ├── terraform.tfvars # valores públicos (versionado no Git)
│   │   └── secret.auto.tfvars  # valores sensíveis (no .gitignore)
│   └── prod/
│       └── (mesma estrutura)
│
└── modules/                 # módulos reutilizáveis
    ├── iam/
    ├── bigquery/
    ├── pubsub/
    ├── secret_manager/
    ├── cloud_functions/
    ├── cloud_run/
    └── scheduler/
```

**Por que separar environments de modules?**
O código dos módulos é escrito uma vez. O ambiente (`dev` ou `prod`) determina
os valores das variáveis. Quando você roda `terraform apply` dentro de
`environments/dev/`, o Terraform usa aquele diretório como **root module** —
ponto de entrada de tudo.

---

## Passo 2 — Provider e backend

O arquivo `terraform/provider.tf` é o primeiro a ser criado. Ele define:
- qual provider usar (Google Cloud)
- qual versão
- onde guardar o tfstate (backend)
- as configurações padrão do provider

```hcl
# terraform/provider.tf
terraform {
  required_version = ">= 1.5"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "local" {}   # tfstate na máquina local
}

provider "google" {
  project = var.project_id   # lido do terraform.tfvars ou secret.auto.tfvars
  region  = var.region
}
```

**Por que `required_version >= 1.5`?** Garante que todos que rodam o projeto
usam uma versão compatível. Evita comportamentos diferentes entre versões.

---

## Passo 3 — Variáveis e separação de segredos

Antes de criar qualquer recurso, defina as variáveis. Existe uma distinção
importante entre o que é público e o que é sensível.

**Valores públicos** — `terraform.tfvars` (versionado no Git):
```hcl
# terraform/environments/dev/terraform.tfvars
region      = "us-central1"
environment = "dev"
```

**Valores sensíveis** — `secret.auto.tfvars` (no .gitignore):
```hcl
# terraform/environments/dev/secret.auto.tfvars
project_id         = "seu-project-id"
sendgrid_api_key   = "SG.xxxx"
notification_email = "seu@email.com"
```

O sufixo `.auto.tfvars` faz o Terraform carregar o arquivo automaticamente,
sem precisar passar `-var-file` na linha de comando. Qualquer arquivo com esse
sufixo é carregado automaticamente. Isso é uma convenção para separar segredos
sem complicar o comando de execução.

**Declaração das variáveis** — `variables.tf`:
```hcl
variable "project_id" {
  type = string
}

variable "environment" {
  type = string

  validation {
    condition     = contains(["dev", "prod"], var.environment)
    error_message = "Environment deve ser dev ou prod."
  }
}

variable "sendgrid_api_key" {
  type      = string
  sensitive = true   # não aparece em logs nem no plan
}
```

O bloco `validation` é uma guarda — se alguém passar `environment = "staging"`,
o Terraform para com erro antes de criar qualquer coisa.

---

## Passo 4 — Módulo IAM (sempre o primeiro)

IAM — **Identity and Access Management** — deve ser o primeiro módulo porque
todos os outros recursos precisam de uma identidade (service account) para rodar.

**Princípio fundamental: least privilege**
Cada serviço recebe apenas as permissões mínimas para fazer seu trabalho.
Nunca use `roles/owner` ou `roles/editor` em service accounts de serviços.

### O que foi criado em `modules/iam/main.tf`

**Service Accounts** — identidades dos serviços:
```hcl
resource "google_service_account" "ingestor" {
  project      = var.project_id
  account_id   = "sa-ingestor-${local.suffix}"   # sa-ingestor-dev
  display_name = "SA - Cloud Function Ingestor (${local.suffix})"
}
```

Uma service account por serviço. Nunca compartilhe service accounts entre serviços
diferentes — se uma for comprometida, o blast radius é limitado.

**IAM Bindings** — permissões de cada service account:
```hcl
resource "google_project_iam_member" "ingestor_bq_editor" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.ingestor.email}"
}
```

A sintaxe `google_project_iam_member` adiciona uma **binding** no nível do projeto.
O `member` referencia o email da service account usando interpolação
`${google_service_account.ingestor.email}` — o Terraform resolve isso
automaticamente, criando a dependência implícita: a binding só é criada depois
que a service account existe.

**Mapa de permissões do projeto:**

| Service Account | Role | Por quê |
|---|---|---|
| `sa-ingestor-dev` | `bigquery.dataEditor` | inserir linhas na tabela |
| `sa-ingestor-dev` | `bigquery.jobUser` | executar jobs de query |
| `sa-ingestor-dev` | `pubsub.publisher` | publicar mensagens no tópico |
| `sa-notificador-dev` | `secretmanager.secretAccessor` | ler a chave SendGrid |
| `sa-notificador-dev` | `pubsub.subscriber` | consumir mensagens do Pub/Sub |
| `sa-audit-logger-dev` | `bigquery.dataEditor` | inserir no audit log |
| `sa-audit-logger-dev` | `pubsub.subscriber` | consumir mensagens do Pub/Sub |
| `sa-dbt-runner-dev` | `bigquery.dataEditor` | criar views e tabelas |
| `sa-dbt-runner-dev` | `pubsub.publisher` | publicar resultado no Pub/Sub |
| `sa-scheduler-dev` | `run.invoker` | disparar Cloud Functions e Cloud Run |

**Outputs do módulo IAM:**
```hcl
output "ingestor_sa_email" {
  value = google_service_account.ingestor.email
}
```

Os emails são expostos como outputs porque o módulo `cloud_functions` precisa
deles para configurar qual identidade cada function vai assumir.

---

## Passo 5 — Módulo Secret Manager (segredos antes dos serviços)

Credenciais nunca devem estar no código. O Secret Manager é o cofre do GCP —
armazena, versiona e controla acesso a segredos.

```hcl
# modules/secret_manager/main.tf

resource "google_secret_manager_secret" "sendgrid_api_key" {
  project   = var.project_id
  secret_id = "sendgrid-api-key-${var.environment}"

  replication {
    auto {}   # GCP escolhe as regiões automaticamente
  }
}

resource "google_secret_manager_secret_version" "sendgrid_api_key" {
  secret      = google_secret_manager_secret.sendgrid_api_key.id
  secret_data = var.sendgrid_api_key   # valor vem do secret.auto.tfvars
}
```

Dois recursos distintos:
- `google_secret_manager_secret` — o cofre (container do segredo)
- `google_secret_manager_secret_version` — o valor real (versionado)

O Secret Manager versiona automaticamente. Se você mudar a chave SendGrid e
rodar `terraform apply`, uma nova versão é criada. A função `notificador` sempre
acessa `versions/latest` — pega a versão mais recente.

**Por que não usar variável de ambiente na Cloud Function?**
Variáveis de ambiente em Cloud Functions ficam visíveis no console do GCP
para qualquer pessoa com acesso ao projeto. O Secret Manager adiciona uma camada
de controle de acesso — só a service account com `secretAccessor` pode ler.

---

## Passo 6 — Módulo BigQuery (dados antes das functions)

O BigQuery precisa existir antes das Cloud Functions, porque o ingestor
vai inserir dados assim que rodar.

```hcl
# modules/bigquery/main.tf

resource "google_bigquery_dataset" "raw" {
  project    = var.project_id
  dataset_id = "raw_${local.suffix}"      # raw_dev ou raw_prod
  location   = "us-central1"
  delete_contents_on_destroy = var.environment == "dev" ? true : false
}
```

**`delete_contents_on_destroy`**: em dev, permite destruir o dataset mesmo com
dados dentro (`terraform destroy` funciona). Em prod, protege os dados — o
Terraform vai recusar destruir um dataset com dados.

**Expressão ternária HCL**: `var.environment == "dev" ? true : false`
É o if-else do HCL. Lê-se: se environment é dev, retorna true, senão retorna false.

**Tabela com schema, particionamento e clustering:**
```hcl
resource "google_bigquery_table" "clima_raw" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  table_id   = "clima_raw"

  time_partitioning {
    type  = "DAY"
    field = "ingest_timestamp"   # partição por dia de ingestão
  }

  clustering = ["cidade"]   # ordena fisicamente por cidade dentro de cada partição

  schema = jsonencode([
    { name = "cidade",           type = "STRING",    mode = "REQUIRED" },
    { name = "timestamp_utc",    type = "TIMESTAMP", mode = "REQUIRED" },
    { name = "temperatura_c",    type = "FLOAT64",   mode = "NULLABLE" },
    ...
  ])

  deletion_protection = var.environment == "prod" ? true : false
}
```

**`deletion_protection`**: em prod, impede que o Terraform (ou qualquer operação)
delete a tabela acidentalmente. Precisa ser setado como `false` antes de um
`terraform destroy` em prod.

**`jsonencode()`**: função built-in do HCL que converte um objeto HCL para JSON.
O BigQuery espera o schema em JSON — `jsonencode` faz essa conversão automaticamente.

---

## Passo 7 — Módulo Pub/Sub (mensageria)

```hcl
# modules/pubsub/main.tf

resource "google_pubsub_topic" "pipeline_eventos" {
  project = var.project_id
  name    = "pipeline-eventos-${local.suffix}"
}

resource "google_pubsub_subscription" "dead_letter" {
  project = var.project_id
  name    = "sub-pipeline-dead-letter-${local.suffix}"
  topic   = google_pubsub_topic.pipeline_eventos.name

  ack_deadline_seconds       = 60      # tempo para processar antes de reenviar
  message_retention_duration = "604800s"  # guarda mensagens por 7 dias
}
```

**Por que dead-letter subscription?** É uma subscription de observabilidade —
permite ver mensagens que não foram processadas por nenhuma function, útil para
debugging. As subscriptions das functions (notificador e audit-logger) são criadas
automaticamente pelo Eventarc quando as Cloud Functions são deployadas com
`event_trigger`.

**Output importante:**
```hcl
output "topic_id" {
  value = google_pubsub_topic.pipeline_eventos.id
  # retorna: projects/PROJECT_ID/topics/pipeline-eventos-dev
}
```

O `topic_id` é passado para o módulo `cloud_functions` e `cloud_run` — eles
precisam saber para qual tópico publicar.

---

## Passo 8 — Módulo Cloud Functions (deploy do código Python)

Este é o módulo mais complexo. Ele precisa dos outputs de IAM, BigQuery,
Pub/Sub e Secret Manager — só pode ser criado após todos eles existirem.
O Terraform resolve isso automaticamente pelo **grafo de dependências implícitas**.

### Deploy em 3 etapas por function

**Etapa 1 — Empacotar o código:**
```hcl
data "archive_file" "ingestor_zip" {
  type        = "zip"
  source_dir  = "${path.root}/../../../functions/ingestor"
  output_path = "/tmp/ingestor-${local.suffix}.zip"
}
```

`path.root` é a pasta raiz do módulo sendo executado (`environments/dev/`).
O caminho relativo `../../../functions/ingestor` navega até a pasta Python.
O `archive_file` calcula o **MD5 do zip** — se o código mudar, o MD5 muda.

**Etapa 2 — Fazer upload no GCS:**
```hcl
resource "google_storage_bucket_object" "ingestor_source" {
  name   = "ingestor-${data.archive_file.ingestor_zip.output_md5}.zip"
  bucket = google_storage_bucket.functions_source.name
  source = data.archive_file.ingestor_zip.output_path
}
```

O MD5 está no nome do objeto (`ingestor-abc123.zip`). Quando o código muda,
o MD5 muda, o nome muda, o Terraform cria um novo objeto e redeploya a function.
Isso garante **deploy automático ao mudar o código Python** sem precisar forçar.

**Etapa 3 — Criar a Cloud Function:**
```hcl
resource "google_cloudfunctions2_function" "ingestor" {
  name     = "ingestor-${local.suffix}"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "ingestor"   # nome da função Python em main.py
    source {
      storage_source {
        bucket = google_storage_bucket.functions_source.name
        object = google_storage_bucket_object.ingestor_source.name
      }
    }
  }

  service_config {
    available_memory      = "256M"
    timeout_seconds       = 120
    service_account_email = var.ingestor_sa_email   # vem do output do módulo IAM

    environment_variables = {
      GCP_PROJECT        = var.project_id
      BQ_DATASET_RAW     = var.bq_dataset_raw       # vem do output do módulo BigQuery
      BQ_TABLE_CLIMA_RAW = var.bq_table_clima_raw
      PUBSUB_TOPIC       = split("/", var.pubsub_topic_id)[length(split("/", var.pubsub_topic_id)) - 1]
    }
  }
}
```

**`split()` e `length()`**: funções built-in do HCL. O `pubsub_topic_id` vem como
`projects/PROJECT/topics/pipeline-eventos-dev`. O código extrai só o nome do tópico
fazendo split por `/` e pegando o último elemento. Resultado: `pipeline-eventos-dev`.

**Functions com `event_trigger` (notificador e audit-logger):**
```hcl
resource "google_cloudfunctions2_function" "notificador" {
  ...
  event_trigger {
    trigger_region        = var.region
    event_type            = "google.cloud.pubsub.topic.v1.messagePublished"
    pubsub_topic          = var.pubsub_topic_id
    service_account_email = var.notificador_sa_email
    retry_policy          = "RETRY_POLICY_RETRY"
  }
}
```

O `event_trigger` instrui o **Eventarc** (serviço de eventos do GCP) a criar
uma subscription no Pub/Sub e entregar mensagens para a function automaticamente.
O `retry_policy = "RETRY_POLICY_RETRY"` garante que, se a function falhar,
o Pub/Sub tenta reenviar a mensagem com backoff exponencial.

---

## Passo 9 — Módulo Cloud Run Job (container dbt)

```hcl
# modules/cloud_run/main.tf

resource "google_cloud_run_v2_job" "dbt_runner" {
  name     = "dbt-runner-${local.suffix}"
  location = var.region

  template {
    template {
      service_account = var.dbt_runner_sa

      containers {
        image = "gcr.io/${var.project_id}/dbt-runner:latest"

        resources {
          limits = {
            cpu    = "1"
            memory = "1Gi"
          }
        }
      }

      timeout     = "1800s"   # 30 minutos máximo
      max_retries = 1
    }
  }
}
```

**Cloud Run Job vs Cloud Run Service:**
- **Service**: fica de pé esperando requisições HTTP (tem URL permanente)
- **Job**: executa, termina, some (sem URL, sem custo quando parado)

O dbt-runner é um Job porque ele executa transformações e termina — não faz sentido
manter um container rodando 24h esperando. Você paga apenas pelo tempo de execução.

**A imagem `gcr.io/PROJECT/dbt-runner:latest` precisa existir no GCR antes
do `terraform apply`**. Por isso o fluxo é:
```bash
docker build -t gcr.io/PROJECT/dbt-runner:latest ./dbt/
docker push gcr.io/PROJECT/dbt-runner:latest
terraform apply
```

---

## Passo 10 — Módulo Scheduler (orquestração por horário)

```hcl
# modules/scheduler/main.tf

resource "google_cloud_scheduler_job" "ingestor_horario" {
  name      = "scheduler-ingestor-${local.suffix}"
  schedule  = "0 * * * *"          # cron: todo início de hora
  time_zone = "America/Sao_Paulo"

  http_target {
    uri         = var.ingestor_function_uri   # vem do output do módulo cloud_functions
    http_method = "POST"
    body        = base64encode("{}")

    oidc_token {
      service_account_email = google_service_account.scheduler_invoker.email
      audience              = var.ingestor_function_uri
    }
  }

  retry_config {
    retry_count = 3
  }
}
```

**Sintaxe cron** `"0 * * * *"`:
```
┌──── minuto (0-59)
│  ┌─── hora (0-23)
│  │  ┌── dia do mês (1-31)
│  │  │  ┌─ mês (1-12)
│  │  │  │  ┌ dia da semana (0-7)
0  *  *  *  *
```
`0 * * * *` = minuto 0 de toda hora = todo início de hora.
`10 * * * *` = minuto 10 de toda hora = 10 minutos após o início de cada hora.

**OIDC vs OAuth2:**
- **OIDC token** — usado para chamar Cloud Functions (HTTP target com autenticação de identidade)
- **OAuth2 token** — usado para chamar APIs do GCP (Cloud Run Jobs API)

O Scheduler precisa de uma service account (`sa-scheduler-dev`) com
`roles/run.invoker` para ter permissão de disparar tanto Cloud Functions
quanto Cloud Run Jobs.

---

## Passo 11 — O main.tf do ambiente orquestra tudo

O `environments/dev/main.tf` é onde os módulos se conectam. O ponto crítico
são os **outputs sendo passados como inputs**:

```hcl
# environments/dev/main.tf

module "iam" {
  source      = "../../modules/iam"
  project_id  = var.project_id
  environment = var.environment
}

# outputs do IAM alimentam o cloud_functions:
module "cloud_functions" {
  source                = "../../modules/cloud_functions"
  ingestor_sa_email     = module.iam.ingestor_sa_email      # ← output do IAM
  notificador_sa_email  = module.iam.notificador_sa_email   # ← output do IAM
  pubsub_topic_id       = module.pubsub.topic_id            # ← output do Pub/Sub
  sendgrid_secret_id    = module.secret_manager.sendgrid_secret_id  # ← output do Secret Manager
  bq_dataset_raw        = module.bigquery.dataset_raw_id    # ← output do BigQuery
  ...
}

# outputs do cloud_functions e cloud_run alimentam o scheduler:
module "scheduler" {
  source                = "../../modules/scheduler"
  ingestor_function_uri = module.cloud_functions.ingestor_uri  # ← output das functions
  dbt_runner_job_name   = module.cloud_run.dbt_runner_job_name # ← output do Cloud Run
}
```

O Terraform lê essas referências e monta um **DAG — Directed Acyclic Graph**
de dependências. Recursos sem dependências são criados em paralelo. Recursos
que dependem de outros esperam. O scheduler, por exemplo, só é criado após
`cloud_functions` e `cloud_run` existirem — porque precisa das URIs deles.

---

## Os três comandos em detalhe

### terraform init
```bash
docker compose run --rm terraform init
```

O que acontece internamente:
1. Lê o bloco `required_providers` no `.tf`
2. Baixa o plugin `hashicorp/google ~> 5.0` do Terraform Registry
3. Cria a pasta `.terraform/providers/` com o binário do provider
4. Gera `.terraform.lock.hcl` — arquivo de lock com o hash exato do provider baixado
5. Inicializa o backend (neste caso, cria o arquivo `terraform.tfstate` se não existir)

O `.terraform.lock.hcl` **deve ser versionado no Git**. Ele garante que todos
usem exatamente o mesmo binário do provider, evitando diferenças de comportamento.

### terraform plan
```bash
docker compose run --rm terraform plan
```

O que acontece internamente:
1. Lê todos os arquivos `.tf` do diretório
2. Lê o `terraform.tfstate` (estado atual)
3. Chama as APIs do GCP para verificar o estado real dos recursos
4. Calcula o diff: o que criar (`+`), modificar (`~`) ou destruir (`-`)
5. Exibe o plano — não modifica nada

O plan é o **contrato** antes de aplicar. Em times, o ideal é revisar o plan
antes de aprovar o apply — igual a um code review de infraestrutura.

### terraform apply
```bash
docker compose run --rm terraform apply
```

O que acontece internamente:
1. Executa o plan novamente (para garantir que nada mudou)
2. Para cada recurso no plano, chama a API do GCP correspondente:
   - `google_service_account` → `POST iam.googleapis.com/v1/projects/.../serviceAccounts`
   - `google_bigquery_dataset` → `POST bigquery.googleapis.com/bigquery/v2/projects/.../datasets`
   - `google_cloudfunctions2_function` → `POST cloudfunctions.googleapis.com/v2/.../functions`
3. Aguarda cada recurso ficar no estado `ACTIVE`
4. Atualiza o `terraform.tfstate` com IDs e metadados de cada recurso

---

## Comandos úteis do dia a dia

```bash
# Ver o que está no tfstate (o que existe na nuvem)
docker compose run --rm terraform show

# Ver só os outputs de um módulo
docker compose run --rm terraform output

# Forçar redeploy de um recurso específico
docker compose run --rm terraform taint module.cloud_functions.google_cloudfunctions2_function.ingestor
docker compose run --rm terraform apply

# Importar um recurso existente para o tfstate (sem recriar)
docker compose run --rm terraform import module.bigquery.google_bigquery_dataset.raw PROJECT/raw_dev

# Ver o grafo de dependências (requer graphviz)
docker compose run --rm terraform graph | dot -Tsvg > grafo.svg

# Destruir tudo (cuidado em prod)
docker compose run --rm terraform destroy
```

---

## Ordem obrigatória de criação neste projeto

O Terraform resolve automaticamente, mas entender a ordem ajuda a debugar:

```
1. IAM
   └── service accounts e roles
       └── outputs: emails das SAs

2. Secret Manager
   └── secret sendgrid-api-key-dev
       └── output: secret_id

3. BigQuery
   └── datasets raw_dev, staging_dev, marts_dev
   └── tabelas clima_raw, pipeline_audit_log
       └── outputs: dataset_ids, table_ids

4. Pub/Sub
   └── tópico pipeline-eventos-dev
   └── subscription dead-letter
       └── output: topic_id

5. Cloud Functions         ← depende de: IAM + BigQuery + Pub/Sub + Secret Manager
   └── bucket GCS (código fonte)
   └── zip + upload do código Python
   └── ingestor-dev (HTTP trigger)
   └── notificador-dev (Eventarc trigger → Pub/Sub)
   └── audit-logger-dev (Eventarc trigger → Pub/Sub)
       └── output: ingestor_uri

6. Cloud Run Job           ← depende de: IAM + Pub/Sub
   └── dbt-runner-dev
       └── output: job_name

7. Cloud Scheduler         ← depende de: Cloud Functions + Cloud Run Job
   └── scheduler-ingestor-dev  (cron → HTTP → ingestor)
   └── scheduler-dbt-runner-dev (cron → HTTP → Cloud Run API → dbt-runner)
```

---

## O que fazer quando algo dá errado

**Erro: resource already exists**
O recurso existe no GCP mas não está no tfstate. Solução: importar.
```bash
docker compose run --rm terraform import <resource_address> <resource_id>
```

**Erro: permission denied**
A service account do Terraform não tem permissão para criar o recurso.
Solução: verificar se `gcloud auth application-default login` foi rodado
e se a conta tem as roles necessárias no projeto.

**Erro: API not enabled**
A API do GCP precisa ser habilitada antes.
```bash
gcloud services enable cloudfunctions.googleapis.com --project=PROJECT_ID
```

**Mudança de localização de dataset BigQuery**
O BigQuery não permite mudar a localização de um dataset existente.
É necessário destruir e recriar — o tfstate controla isso com
`delete_contents_on_destroy = true` em dev.

---

## Resumo: o que cada arquivo faz

| Arquivo | Função |
|---|---|
| `provider.tf` | Configura o provider Google e o backend do tfstate |
| `variables.tf` | Declara os tipos e validações das variáveis |
| `terraform.tfvars` | Valores públicos das variáveis (versionado) |
| `secret.auto.tfvars` | Valores sensíveis — project_id, chaves (não versionado) |
| `environments/dev/main.tf` | Ponto de entrada: chama os módulos e conecta outputs/inputs |
| `modules/iam/main.tf` | Cria service accounts e vincula roles IAM |
| `modules/bigquery/main.tf` | Cria datasets e tabelas com schema, partição e clustering |
| `modules/pubsub/main.tf` | Cria tópico e subscription de dead-letter |
| `modules/secret_manager/main.tf` | Cria e versiona o secret da chave SendGrid |
| `modules/cloud_functions/main.tf` | Empacota código Python, faz upload e deploya as functions |
| `modules/cloud_run/main.tf` | Cria o Cloud Run Job do dbt-runner |
| `modules/scheduler/main.tf` | Cria os cron jobs que disparam ingestor e dbt |
| `terraform.tfstate` | Estado atual — nunca editar manualmente |
| `.terraform.lock.hcl` | Lock do provider — versionar no Git |
