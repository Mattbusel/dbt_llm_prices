# llm_prices for dbt

LLM API prices as a dbt package. You get a price table (146 models across OpenAI,
Anthropic, Google, DeepSeek, Mistral, xAI, Cohere, Groq, Together and Fireworks) and a macro
that turns token counts into dollars in any model:

```sql
select
    request_id,
    model,
    input_tokens,
    output_tokens,
    {{ llm_prices.cost('model', 'input_tokens', 'output_tokens') }} as cost_usd
from {{ ref('stg_llm_usage') }}
```

The prices come from [llm-prices](https://github.com/Mattbusel/llm-prices): every row carries
the provider pricing page it was read from and the date it was checked. Each release of this
package pins one llm-prices release (0.1.0 pins llm-prices v1.3.0, checked 2026-11-15).

## Install

Until the package is on the dbt Package Hub, install it from git:

```yaml
# packages.yml
packages:
  - git: "https://github.com/Mattbusel/dbt_llm_prices.git"
    revision: v0.1.0
```

Then:

```
dbt deps
dbt build --select package:llm_prices
```

That loads two seeds (`llm_prices_models`, `llm_prices_keys`) and builds the
`llm_prices_lookup` table the macros read. Build it before the models that call the macros;
dbt orders this for you because the macros `ref` the lookup.

## Macros

### `llm_prices.cost(model_col, input_tokens, output_tokens, ...)`

A SQL expression for the USD cost of one call. Arguments are column names or SQL expressions.

| argument | default | meaning |
| --- | --- | --- |
| `model_col` | | model id as your logs carry it. `gpt-4.1`, `GPT-4.1 `, `openai/gpt-4.1` and aliases all match |
| `input_tokens` | | uncached input tokens |
| `output_tokens` | | output tokens |
| `cache_read_tokens` | none | prompt-cache reads, priced at the cache read rate |
| `cache_write_tokens` | none | prompt-cache writes, priced at the cache write rate for `cache_write_ttl` |
| `provider_col` | none | provider column, for a model id more than one host sells |
| `tier` | `'standard'` | `'standard'` or `'batch'` |
| `cache_write_ttl` | `'5m'` | `'5m'`, `'1h'`, `'30m'` or `'12h'` |

A model that is not in the table gives `null`, not 0, so unpriced usage shows up in your
totals instead of being counted as free:

```sql
select count(*) as unpriced_calls
from {{ ref('fct_llm_calls') }}
where cost_usd is null
```

Token conventions differ by provider. Anthropic reports `input_tokens` without cache reads
and writes; OpenAI's `prompt_tokens` includes `cached_tokens`. Pass the uncached part as
`input_tokens`, for OpenAI `prompt_tokens - cached_tokens`.

Anthropic, with prompt caching:

```sql
{{ llm_prices.cost(
    'model', 'input_tokens', 'output_tokens',
    cache_read_tokens='cache_read_input_tokens',
    cache_write_tokens='cache_creation_input_tokens'
) }}
```

Batch API usage:

```sql
{{ llm_prices.cost('model', 'input_tokens', 'output_tokens', tier='batch') }}
```

An open-weights model on more than one host:

```sql
{{ llm_prices.cost('model', 'input_tokens', 'output_tokens', provider_col='provider') }}
```

Without `provider_col`, a model id sold by several providers resolves to one default: the
provider named in the id prefix, otherwise the first provider alphabetically. A null or empty
provider falls back to the same default.

### `llm_prices.price(model_col, kind='input', provider_col=none)`

One price in USD per 1M tokens, for your own cost math. `kind` is one of `input`, `output`,
`cache_read`, `cache_write_5m`, `cache_write_1h`, `cache_write_30m`, `cache_write_12h`,
`batch_input`, `batch_output`, `long_context_input`, `long_context_output`.

### `llm_prices.input_cost(...)` and `llm_prices.output_cost(...)`

The two sides of the bill on their own.

## The lookup table

`llm_prices_lookup` has one row per model key and provider, every column prefixed
`llm_prices_` so it never clashes with your own columns. Besides the prices it carries
`llm_prices_status` (`listed` or `retired`), `llm_prices_source_url`,
`llm_prices_checked_on` and `llm_prices_note` (regional surcharges, tiers). You can join
it directly:

```sql
select u.*, p.llm_prices_input_usd_per_mtok, p.llm_prices_output_usd_per_mtok
from {{ ref('stg_llm_usage') }} as u
left join {{ ref('llm_prices', 'llm_prices_lookup') }} as p
    on p.llm_prices_key = lower(trim(u.model))
    and p.llm_prices_match_provider = ''
```

The macros price the base tier. Models with a long-context tier have
`llm_prices_long_context_threshold_tokens` and the long-context prices in the table if you
need them.

## Warehouses

Tested in CI on DuckDB and Postgres. The macros use a correlated scalar subquery
(`select max(...) from llm_prices_lookup where key = ...`), which Snowflake, BigQuery and
Databricks support; they are not yet covered by CI. Redshift does not allow correlated
subqueries in a select list: use the join above.

## Updating prices

`scripts/build_seeds.py` regenerates the seeds from an llm-prices release:

```
python scripts/build_seeds.py --tag v1.3.0
```

New prices ship as a new package release.
