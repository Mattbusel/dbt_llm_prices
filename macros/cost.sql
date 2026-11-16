{#-
    Cost in USD of one LLM call, as a SQL expression you can put in a select list.

        select
            request_id,
            {{ llm_prices.cost('model', 'input_tokens', 'output_tokens') }} as cost_usd
        from {{ ref('stg_llm_usage') }}

    Arguments are column names or SQL expressions from the calling model:
      model_col           model id as your logs carry it (gpt-4.1, claude-sonnet-4-6,
                          openai/gpt-4.1, an alias). Matched case- and space-insensitively.
      input_tokens        uncached input tokens
      output_tokens       output tokens
      cache_read_tokens   optional: prompt-cache reads, priced at the cache read rate
      cache_write_tokens  optional: prompt-cache writes, priced at the cache write rate
                          for cache_write_ttl ('5m', '1h', '30m' or '12h')
      provider_col        optional: provider column, for a model id that more than one
                          host prices (openai/gpt-oss-120b on groq and together)
      tier                'standard' (default) or 'batch'

    Returns null when the model is not in the price table, so unpriced usage shows up
    instead of being counted as free.
-#}
{% macro cost(model_col, input_tokens, output_tokens, cache_read_tokens=none, cache_write_tokens=none, provider_col=none, tier='standard', cache_write_ttl='5m') %}
    {{ return(adapter.dispatch('cost', 'llm_prices')(model_col, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, provider_col, tier, cache_write_ttl)) }}
{% endmacro %}

{% macro default__cost(model_col, input_tokens, output_tokens, cache_read_tokens, cache_write_tokens, provider_col, tier, cache_write_ttl) %}
    {%- if tier not in ['standard', 'batch'] -%}
        {{ exceptions.raise_compiler_error("llm_prices.cost: tier must be 'standard' or 'batch', got '" ~ tier ~ "'") }}
    {%- endif -%}
    {%- if cache_write_ttl not in ['5m', '1h', '30m', '12h'] -%}
        {{ exceptions.raise_compiler_error("llm_prices.cost: cache_write_ttl must be '5m', '1h', '30m' or '12h', got '" ~ cache_write_ttl ~ "'") }}
    {%- endif -%}
    {%- set in_col = 'batch_input' if tier == 'batch' else 'input' -%}
    {%- set out_col = 'batch_output' if tier == 'batch' else 'output' -%}
    (
        (
            {{ llm_prices.price(model_col, in_col, provider_col) }} * coalesce({{ input_tokens }}, 0)
            + case
                when coalesce({{ output_tokens }}, 0) = 0 then 0
                else {{ llm_prices.price(model_col, out_col, provider_col) }} * {{ output_tokens }}
              end
            {%- if cache_read_tokens is not none %}
            + case
                when coalesce({{ cache_read_tokens }}, 0) = 0 then 0
                else coalesce(
                    {{ llm_prices.price(model_col, 'cache_read', provider_col) }},
                    {{ llm_prices.price(model_col, 'input', provider_col) }}
                ) * {{ cache_read_tokens }}
              end
            {%- endif %}
            {%- if cache_write_tokens is not none %}
            + case
                when coalesce({{ cache_write_tokens }}, 0) = 0 then 0
                else coalesce(
                    {{ llm_prices.price(model_col, 'cache_write_' ~ cache_write_ttl, provider_col) }},
                    {{ llm_prices.price(model_col, 'input', provider_col) }}
                ) * {{ cache_write_tokens }}
              end
            {%- endif %}
        ) / 1000000
    )
{%- endmacro %}

{#-
    One price in USD per 1M tokens, as a scalar subquery on llm_prices_lookup.
    kind: input, output, cache_read, cache_write_5m, cache_write_1h, cache_write_30m,
    cache_write_12h, batch_input, batch_output, long_context_input, long_context_output.
-#}
{% macro price(model_col, kind='input', provider_col=none) %}
    {{ return(adapter.dispatch('price', 'llm_prices')(model_col, kind, provider_col)) }}
{% endmacro %}

{% macro default__price(model_col, kind, provider_col) %}
    {%- set kinds = ['input', 'output', 'cache_read', 'cache_write_5m', 'cache_write_1h', 'cache_write_30m', 'cache_write_12h', 'batch_input', 'batch_output', 'long_context_input', 'long_context_output'] -%}
    {%- if kind not in kinds -%}
        {{ exceptions.raise_compiler_error("llm_prices.price: unknown kind '" ~ kind ~ "', expected one of " ~ kinds | join(', ')) }}
    {%- endif -%}
    (
        select max(llm_prices_p.llm_prices_{{ kind }}_usd_per_mtok)
        from {{ ref('llm_prices', 'llm_prices_lookup') }} as llm_prices_p
        where llm_prices_p.llm_prices_key = lower(trim({{ model_col }}))
        {%- if provider_col is not none %}
          and llm_prices_p.llm_prices_match_provider = coalesce(lower(trim({{ provider_col }})), '')
        {%- else %}
          and llm_prices_p.llm_prices_match_provider = ''
        {%- endif %}
    )
{%- endmacro %}

{#- Cost of the input side only (uncached input tokens). -#}
{% macro input_cost(model_col, input_tokens, provider_col=none, tier='standard') %}
    {{ return(llm_prices.cost(model_col, input_tokens, '0', provider_col=provider_col, tier=tier)) }}
{% endmacro %}

{#- Cost of the output side only. -#}
{% macro output_cost(model_col, output_tokens, provider_col=none, tier='standard') %}
    {%- set out_col = 'batch_output' if tier == 'batch' else 'output' -%}
    ({{ llm_prices.price(model_col, out_col, provider_col) }} * {{ output_tokens }} / 1000000)
{%- endmacro %}
