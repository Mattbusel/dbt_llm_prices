# Changelog

## [0.1.0] - 2026-11-15

First release.

- Seeds `llm_prices_models` (146 models, 10 providers) and `llm_prices_keys` (model ids,
  aliases and provider/model ids), generated from llm-prices v1.3.0 (prices checked
  2026-11-15) by `scripts/build_seeds.py`.
- Model `llm_prices_lookup`: one row per model key and provider, prices cast to
  `dbt.type_numeric()`, every column prefixed `llm_prices_`.
- Macros `cost`, `price`, `input_cost`, `output_cost`. `cost` handles cache reads, cache
  writes (5m, 1h, 30m, 12h), the batch tier and an optional provider column, and returns null
  for a model it cannot price.
- Integration tests on DuckDB and Postgres compare every macro result with costs worked out
  in exact decimals from the same release.
