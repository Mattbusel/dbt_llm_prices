select
    usage_id,
    expected_cost_usd,
    expected_batch_cost_usd,
    {{ llm_prices.cost(
        'model', 'input_tokens', 'output_tokens',
        cache_read_tokens='cache_read_tokens',
        cache_write_tokens='cache_write_tokens',
        provider_col='provider'
    ) }} as cost_usd,
    {{ llm_prices.cost(
        'model', 'input_tokens', 'output_tokens',
        cache_read_tokens='cache_read_tokens',
        cache_write_tokens='cache_write_tokens',
        provider_col='provider',
        tier='batch'
    ) }} as batch_cost_usd,
    {{ llm_prices.input_cost('model', 'input_tokens', provider_col='provider') }}
        + coalesce({{ llm_prices.output_cost('model', 'output_tokens', provider_col='provider') }}, 0)
        as split_cost_usd,
    {{ llm_prices.cost('model', 'input_tokens', 'output_tokens', provider_col='provider') }} as cost_no_cache_usd
from {{ ref('llm_prices_test_usage') }}
