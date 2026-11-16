-- A model key resolves to at most one price per provider to match.
select
    llm_prices_key,
    llm_prices_match_provider,
    count(*) as n
from {{ ref('llm_prices_lookup') }}
group by llm_prices_key, llm_prices_match_provider
having count(*) > 1
