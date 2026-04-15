FROM python:3.11-slim

WORKDIR /dbt

# Instala dbt-core + adaptador BigQuery
RUN pip install --no-cache-dir dbt-core==1.8.* dbt-bigquery==1.8.*

# Copia projeto dbt
COPY . .

# Copia profiles para localização padrão do dbt
RUN mkdir -p /root/.dbt && cp profiles.yml /root/.dbt/profiles.yml

# Script de entrada: roda dbt, publica no Pub/Sub, retorna código de saída
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
