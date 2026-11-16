-- Every key has exactly one default row, so lookups without a provider resolve.
with keys as (

    select distinct llm_prices_key
    from {{ ref('llm_prices_lookup') }}

),

defaults as (

    select llm_prices_key, count(*) as n
    from {{ ref('llm_prices_lookup') }}
    where llm_prices_match_provider = ''
    group by llm_prices_key

)

select keys.llm_prices_key, defaults.n
from keys
left join defaults on keys.llm_prices_key = defaults.llm_prices_key
where defaults.n is null or defaults.n <> 1
