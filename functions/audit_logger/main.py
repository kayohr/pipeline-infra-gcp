import base64
import json
import os
import uuid
import functions_framework
from datetime import datetime, timezone
from google.cloud import bigquery

PROJECT_ID = os.environ["GCP_PROJECT"]
BQ_DATASET = os.environ["BQ_DATASET_RAW"]
BQ_TABLE = os.environ["BQ_TABLE_AUDIT_LOG"]

bq_client = bigquery.Client(project=PROJECT_ID)


@functions_framework.cloud_event
def audit_logger(cloud_event):
    # Filtra: só processa mensagens com atributo status=sucesso
    atributos = cloud_event.data["message"].get("attributes", {})
    if atributos.get("status") != "sucesso":
        return

    raw = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    evento = json.loads(raw)

    row = {
        "event_id": evento.get("event_id", str(uuid.uuid4())),
        "service": evento.get("service", "desconhecido"),
        "status": evento.get("status", "sucesso"),
        "message": evento.get("message"),
        "event_timestamp": evento.get(
            "event_timestamp",
            datetime.now(timezone.utc).isoformat(),
        ),
        "metadata": json.dumps(evento.get("metadata")) if evento.get("metadata") else None,
    }

    table_ref = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"
    errors = bq_client.insert_rows_json(table_ref, [row])
    if errors:
        raise RuntimeError(f"Erro ao registrar audit log: {errors}")
