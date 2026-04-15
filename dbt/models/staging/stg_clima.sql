with source as (
    select * from {{ source('raw', 'clima_raw') }}
),

limpo as (
    select
        cidade,
        latitude,
        longitude,

        -- Normaliza timestamp para TIMESTAMP
        cast(timestamp_utc as timestamp)                    as timestamp_utc,

        -- Garante tipos corretos e trata nulos com fallback conservador
        coalesce(cast(temperatura_c   as float64), 0.0)    as temperatura_c,
        coalesce(cast(umidade_pct     as int64),   0)      as umidade_pct,
        coalesce(cast(precipitacao_mm as float64), 0.0)    as precipitacao_mm,
        coalesce(cast(vento_kmh       as float64), 0.0)    as vento_kmh,

        cast(ingest_timestamp as timestamp)                 as ingest_timestamp,

        -- Colunas derivadas para facilitar agregações
        date(timestamp_utc)                                 as data_medicao,
        extract(hour from timestamp_utc)                    as hora_medicao

    from source
    where timestamp_utc is not null
      and cidade is not null
)

select * from limpo
