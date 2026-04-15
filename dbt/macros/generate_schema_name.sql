{% macro generate_schema_name(custom_schema_name, node) -%}
  {%- set env = env_var('ENVIRONMENT', 'dev') -%}
  {%- if custom_schema_name is none -%}
    {{ default_schema }}
  {%- else -%}
    {{ custom_schema_name }}_{{ env }}
  {%- endif -%}
{%- endmacro %}
