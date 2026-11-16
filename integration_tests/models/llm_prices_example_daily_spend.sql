{#- Example: daily spend per model over a usage log. -#}
with usage as (

    select
        cast('2026-11-15' as date) as usage_date,
        model,
        provider,
        input_tokens,
        output_tokens,
        cache_read_tokens
    from {{ ref('llm_prices_test_usage') }}

),

priced as (

    select
        usage_date,
        lower(trim(model)) as model_id,
        input_tokens,
        output_tokens,
        {{ llm_prices.cost('model', 'input_tokens', 'output_tokens', cache_read_tokens='cache_read_tokens', provider_col='provider') }} as cost_usd
    from usage

)

select
    usage_date,
    model_id,
    count(*) as calls,
    sum(input_tokens) as input_tokens,
    sum(output_tokens) as output_tokens,
    sum(cost_usd) as cost_usd,
    sum(case when cost_usd is null then 1 else 0 end) as unpriced_calls
from priced
group by usage_date, model_id
