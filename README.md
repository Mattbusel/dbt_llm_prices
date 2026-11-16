# llm_prices for dbt

A dbt package with LLM API prices: a price table of 146 models (OpenAI, Anthropic, Google, DeepSeek, Mistral, xAI, Cohere, Groq, Together and Fireworks) and a macro that turns token counts into dollars in any model. Every price row carries the provider pricing page it was read from and the date it was checked. Prices come from [llm-prices](https://github.com/Mattbusel/llm-prices). Tested in CI on DuckDB and Postgres.

## Install

```yaml
# packages.yml
packages:
  - git: "https://github.com/Mattbusel/dbt_llm_prices.git"
    revision: v0.1.0
```

```
dbt deps
dbt build --select package:llm_prices
```

## Example

```sql
select
    request_id,
    model,
    input_tokens,
    output_tokens,
    {{ llm_prices.cost('model', 'input_tokens', 'output_tokens') }} as cost_usd
from {{ ref('stg_llm_usage') }}
```

A model that is not in the table gives `null`, not 0, so unpriced usage shows up in your totals. The macro also prices cache reads and writes, batch calls and a provider column.

## Docs and license

- Macros, lookup table and warehouses: [docs/usage.md](https://github.com/Mattbusel/dbt_llm_prices/blob/main/docs/usage.md)
- Changes: [CHANGELOG.md](https://github.com/Mattbusel/dbt_llm_prices/blob/main/CHANGELOG.md)
- MIT license: [LICENSE](https://github.com/Mattbusel/dbt_llm_prices/blob/main/LICENSE)
