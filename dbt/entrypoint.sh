#!/bin/bash
set -e

ENVIRONMENT="${ENVIRONMENT:-dev}"
GCP_PROJECT="${GCP_PROJECT}"
PUBSUB_TOPIC="${PUBSUB_TOPIC:-pipeline-eventos-${ENVIRONMENT}}"

DBT_TARGET="prod"
if [ "$ENVIRONMENT" = "dev" ]; then
  DBT_TARGET="dev"
fi

echo "=== dbt-runner iniciando (env: $ENVIRONMENT, target: $DBT_TARGET) ==="

# Executa dbt e captura status
if dbt run --target "$DBT_TARGET" && dbt test --target "$DBT_TARGET"; then
  STATUS="sucesso"
  MESSAGE="dbt-runner concluído com sucesso no ambiente $ENVIRONMENT"
  EXIT_CODE=0
else
  STATUS="erro"
  MESSAGE="dbt-runner falhou no ambiente $ENVIRONMENT"
  EXIT_CODE=1
fi

# Publica evento no Pub/Sub
EVENT_ID=$(python3 -c "import uuid; print(str(uuid.uuid4()))")
TIMESTAMP=$(python3 -c "from datetime import datetime, timezone; print(datetime.now(timezone.utc).isoformat())")

python3 - <<EOF
import json
from google.cloud import pubsub_v1

client = pubsub_v1.PublisherClient()
topic_path = client.topic_path("${GCP_PROJECT}", "${PUBSUB_TOPIC}")

payload = json.dumps({
    "event_id": "${EVENT_ID}",
    "service": "dbt-runner",
    "status": "${STATUS}",
    "message": "${MESSAGE}",
    "event_timestamp": "${TIMESTAMP}",
}).encode("utf-8")

client.publish(topic_path, payload, status="${STATUS}")
print(f"Evento publicado: status=${STATUS}")
EOF

exit $EXIT_CODE
