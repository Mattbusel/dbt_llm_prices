-- Every computed cost matches the cost scripts/build_seeds.py worked out in
-- exact decimals from the same llm-prices release. Null means unpriced and must
-- stay null.
{%- set tol = '0.000000001' %}

with costs as (

    select * from {{ ref('llm_prices_test_costs') }}

)

select *
from costs
where
    (expected_cost_usd is null and cost_usd is not null)
    or (expected_cost_usd is not null and cost_usd is null)
    or abs(cost_usd - expected_cost_usd) > {{ tol }}
    or (expected_batch_cost_usd is null and batch_cost_usd is not null)
    or (expected_batch_cost_usd is not null and batch_cost_usd is null)
    or abs(batch_cost_usd - expected_batch_cost_usd) > {{ tol }}
    or (split_cost_usd is null) <> (cost_no_cache_usd is null)
    or abs(split_cost_usd - cost_no_cache_usd) > {{ tol }}
