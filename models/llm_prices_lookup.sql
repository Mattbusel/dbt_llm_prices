{#-
    One row per (model key, provider to match). Each model id, alias and
    provider/model id gets a row for its provider, and the default provider for
    the key gets a second row with llm_prices_match_provider = '' so lookups
    without a provider column resolve with a plain equality join.
-#}
{%- set money = dbt.type_numeric() -%}
{%- set text = dbt.type_string() -%}

with models as (

    select * from {{ ref('llm_prices_models') }}

),

model_keys as (

    select * from {{ ref('llm_prices_keys') }}

),

matches as (

    select
        model_key,
        provider,
        model,
        provider as match_provider
    from model_keys

    union all

    select
        model_key,
        provider,
        model,
        '' as match_provider
    from model_keys
    where cast(is_default as {{ text }}) in ('true', 'True', 'TRUE', '1')

)

select
    cast(matches.model_key as {{ text }}) as llm_prices_key,
    cast(matches.match_provider as {{ text }}) as llm_prices_match_provider,
    cast(models.provider as {{ text }}) as llm_prices_provider,
    cast(models.model as {{ text }}) as llm_prices_model,
    cast(models.model_name as {{ text }}) as llm_prices_model_name,
    cast(models.price_status as {{ text }}) as llm_prices_status,
    cast(models.input_usd_per_mtok as {{ money }}) as llm_prices_input_usd_per_mtok,
    cast(models.output_usd_per_mtok as {{ money }}) as llm_prices_output_usd_per_mtok,
    cast(models.cache_read_usd_per_mtok as {{ money }}) as llm_prices_cache_read_usd_per_mtok,
    cast(models.cache_write_5m_usd_per_mtok as {{ money }}) as llm_prices_cache_write_5m_usd_per_mtok,
    cast(models.cache_write_1h_usd_per_mtok as {{ money }}) as llm_prices_cache_write_1h_usd_per_mtok,
    cast(models.cache_write_30m_usd_per_mtok as {{ money }}) as llm_prices_cache_write_30m_usd_per_mtok,
    cast(models.cache_write_12h_usd_per_mtok as {{ money }}) as llm_prices_cache_write_12h_usd_per_mtok,
    cast(models.batch_input_usd_per_mtok as {{ money }}) as llm_prices_batch_input_usd_per_mtok,
    cast(models.batch_output_usd_per_mtok as {{ money }}) as llm_prices_batch_output_usd_per_mtok,
    cast(models.long_context_threshold_tokens as {{ dbt.type_bigint() }}) as llm_prices_long_context_threshold_tokens,
    cast(models.long_context_input_usd_per_mtok as {{ money }}) as llm_prices_long_context_input_usd_per_mtok,
    cast(models.long_context_output_usd_per_mtok as {{ money }}) as llm_prices_long_context_output_usd_per_mtok,
    cast(models.source_url as {{ text }}) as llm_prices_source_url,
    cast(models.checked_on as date) as llm_prices_checked_on,
    cast(models.note as {{ text }}) as llm_prices_note
from matches
inner join models
    on matches.provider = models.provider
    and matches.model = models.model
