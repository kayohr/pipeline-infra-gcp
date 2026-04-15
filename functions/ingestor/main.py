import os
import uuid
import functions_framework
import requests
from datetime import datetime, timezone
from google.cloud import bigquery, pubsub_v1
import json

PROJECT_ID = os.environ["GCP_PROJECT"]
BQ_DATASET = os.environ["BQ_DATASET_RAW"]
BQ_TABLE = os.environ["BQ_TABLE_CLIMA_RAW"]
PUBSUB_TOPIC = os.environ["PUBSUB_TOPIC"]

CIDADES = [
    {"nome": "São Paulo",    "lat": -23.5505, "lon": -46.6333},
    {"nome": "Rio de Janeiro", "lat": -22.9068, "lon": -43.1729},
    {"nome": "Curitiba",    "lat": -25.4284, "lon": -49.2733},
]

OPEN_METEO_URL = "https://api.open-meteo.com/v1/forecast"

bq_client = bigquery.Client(project=PROJECT_ID)
pubsub_client = pubsub_v1.PublisherClient()


def buscar_clima(cidade: dict) -> list[dict]:
    params = {
        "latitude": cidade["lat"],
        "longitude": cidade["lon"],
        "hourly": "temperature_2m,relative_humidity_2m,precipitation,wind_speed_10m",
        "forecast_days": 1,
        "timezone": "UTC",
    }
    resp = requests.get(OPEN_METEO_URL, params=params, timeout=10)
    resp.raise_for_status()
    data = resp.json()

    ingest_ts = datetime.now(timezone.utc).isoformat()
    rows = []
    hourly = data["hourly"]
    for i, ts in enumerate(hourly["time"]):
        rows.append({
            "cidade": cidade["nome"],
            "latitude": cidade["lat"],
            "longitude": cidade["lon"],
            "timestamp_utc": ts + ":00Z",  # ISO 8601 → BQ TIMESTAMP
            "temperatura_c": hourly["temperature_2m"][i],
            "umidade_pct": hourly["relative_humidity_2m"][i],
            "precipitacao_mm": hourly["precipitation"][i],
            "vento_kmh": hourly["wind_speed_10m"][i],
            "ingest_timestamp": ingest_ts,
        })
    return rows


def inserir_bigquery(rows: list[dict]) -> None:
    table_ref = f"{PROJECT_ID}.{BQ_DATASET}.{BQ_TABLE}"
    errors = bq_client.insert_rows_json(table_ref, rows)
    if errors:
        raise RuntimeError(f"Erros ao inserir no BigQuery: {errors}")


def publicar_pubsub(status: str, mensagem: str) -> None:
    topic_path = pubsub_client.topic_path(PROJECT_ID, PUBSUB_TOPIC)
    payload = json.dumps({
        "event_id": str(uuid.uuid4()),
        "service": "ingestor",
        "status": status,
        "message": mensagem,
        "event_timestamp": datetime.now(timezone.utc).isoformat(),
    }).encode("utf-8")
    pubsub_client.publish(
        topic_path,
        payload,
        status=status,
    )


@functions_framework.http
def ingestor(request):
    try:
        todas_as_linhas = []
        for cidade in CIDADES:
            linhas = buscar_clima(cidade)
            todas_as_linhas.extend(linhas)

        inserir_bigquery(todas_as_linhas)

        mensagem = f"Ingestão concluída: {len(todas_as_linhas)} registros inseridos."
        publicar_pubsub("sucesso", mensagem)
        return {"status": "ok", "registros": len(todas_as_linhas)}, 200

    except Exception as exc:
        mensagem = f"Falha na ingestão: {exc}"
        publicar_pubsub("erro", mensagem)
        return {"status": "erro", "mensagem": mensagem}, 500
