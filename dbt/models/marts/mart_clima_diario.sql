{{
  config(
    materialized='incremental',
    unique_key=['cidade', 'data_medicao'],
    partition_by={
      'field': 'data_medicao',
      'data_type': 'date',
      'granularity': 'day'
    },
    cluster_by=['cidade'],
    incremental_strategy='merge'
  )
}}

with staging as (
    select * from {{ ref('stg_clima') }}
    {% if is_incremental() %}
    -- Reprocessa apenas os últimos 2 dias para capturar dados atrasados
    where data_medicao >= date_sub(current_date(), interval 2 day)
    {% endif %}
),

agregado as (
    select
        cidade,
        data_medicao,

        -- Temperatura
        round(avg(temperatura_c), 2)  as temperatura_media_c,
        round(min(temperatura_c), 2)  as temperatura_min_c,
        round(max(temperatura_c), 2)  as temperatura_max_c,

        -- Umidade
        round(avg(umidade_pct), 1)    as umidade_media_pct,

        -- Precipitação acumulada no dia
        round(sum(precipitacao_mm), 2) as precipitacao_total_mm,

        -- Vento
        round(avg(vento_kmh), 2)      as vento_medio_kmh,
        round(max(vento_kmh), 2)      as vento_max_kmh,

        -- Metadados
        count(*)                       as qtd_medicoes,
        min(ingest_timestamp)          as primeira_ingestao,
        max(ingest_timestamp)          as ultima_ingestao

    from staging
    group by cidade, data_medicao
)

select * from agregado
