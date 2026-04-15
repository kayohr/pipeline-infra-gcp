import base64
import json
import os
import functions_framework
import requests
from google.cloud import secretmanager

PROJECT_ID = os.environ["GCP_PROJECT"]
SECRET_ID = os.environ["SENDGRID_SECRET_ID"]
NOTIFICATION_EMAIL = os.environ["NOTIFICATION_EMAIL"]
FROM_EMAIL = os.environ.get("FROM_EMAIL", "pipeline@noreply.example.com")

SENDGRID_URL = "https://api.sendgrid.com/v3/mail/send"

sm_client = secretmanager.SecretManagerServiceClient()


def obter_sendgrid_key() -> str:
    name = f"projects/{PROJECT_ID}/secrets/{SECRET_ID}/versions/latest"
    response = sm_client.access_secret_version(request={"name": name})
    return response.payload.data.decode("utf-8")


def enviar_email(api_key: str, evento: dict) -> None:
    payload = {
        "personalizations": [{
            "to": [{"email": NOTIFICATION_EMAIL}],
            "subject": f"[PIPELINE ERRO] {evento.get('service', 'desconhecido')}",
        }],
        "from": {"email": FROM_EMAIL},
        "content": [{
            "type": "text/plain",
            "value": (
                f"Falha detectada no pipeline.\n\n"
                f"Serviço: {evento.get('service')}\n"
                f"Mensagem: {evento.get('message')}\n"
                f"Timestamp: {evento.get('event_timestamp')}\n"
                f"Event ID: {evento.get('event_id')}\n"
            ),
        }],
    }
    resp = requests.post(
        SENDGRID_URL,
        json=payload,
        headers={"Authorization": f"Bearer {api_key}"},
        timeout=10,
    )
    resp.raise_for_status()


@functions_framework.cloud_event
def notificador(cloud_event):
    # Filtra: só processa mensagens com atributo status=erro
    atributos = cloud_event.data["message"].get("attributes", {})
    if atributos.get("status") != "erro":
        return

    raw = base64.b64decode(cloud_event.data["message"]["data"]).decode("utf-8")
    evento = json.loads(raw)

    api_key = obter_sendgrid_key()
    enviar_email(api_key, evento)
