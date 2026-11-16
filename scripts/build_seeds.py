"""Regenerate the seeds from an llm-prices release.

    python scripts/build_seeds.py                      # the release pinned below
    python scripts/build_seeds.py --tag v1.4.0         # another release
    python scripts/build_seeds.py --prices prices.json # a local file

Writes seeds/llm_prices_models.csv, seeds/llm_prices_keys.csv and the expected
costs used by integration_tests. Standard library only.
"""

from __future__ import annotations

import argparse
import csv
import json
import urllib.request
from decimal import Decimal
from pathlib import Path

DEFAULT_TAG = "v1.3.0"
RAW = "https://raw.githubusercontent.com/Mattbusel/llm-prices/{tag}/prices.json"
ROOT = Path(__file__).resolve().parent.parent

MODEL_COLUMNS = [
    "provider",
    "model",
    "model_name",
    "price_status",
    "input_usd_per_mtok",
    "output_usd_per_mtok",
    "cache_read_usd_per_mtok",
    "cache_write_5m_usd_per_mtok",
    "cache_write_1h_usd_per_mtok",
    "cache_write_30m_usd_per_mtok",
    "cache_write_12h_usd_per_mtok",
    "batch_input_usd_per_mtok",
    "batch_output_usd_per_mtok",
    "long_context_threshold_tokens",
    "long_context_input_usd_per_mtok",
    "long_context_output_usd_per_mtok",
    "source_url",
    "checked_on",
    "note",
]
KEY_COLUMNS = ["model_key", "provider", "model", "is_default"]


def num(value) -> str:
    if value is None:
        return ""
    return format(Decimal(str(value)).normalize(), "f")


def load(args) -> dict:
    if args.prices:
        return json.loads(Path(args.prices).read_text(encoding="utf-8"))
    with urllib.request.urlopen(RAW.format(tag=args.tag), timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def model_row(m: dict) -> dict:
    cw = m.get("cache_write") or {}
    lc = m.get("long_context") or {}
    return {
        "provider": m["provider"].lower(),
        "model": m["model"],
        "model_name": m.get("name") or "",
        "price_status": m.get("status") or "",
        "input_usd_per_mtok": num(m.get("input")),
        "output_usd_per_mtok": num(m.get("output")),
        "cache_read_usd_per_mtok": num(m.get("cache_read")),
        "cache_write_5m_usd_per_mtok": num(cw.get("5m")),
        "cache_write_1h_usd_per_mtok": num(cw.get("1h")),
        "cache_write_30m_usd_per_mtok": num(cw.get("30m")),
        "cache_write_12h_usd_per_mtok": num(cw.get("12h")),
        "batch_input_usd_per_mtok": num(m.get("batch_input")),
        "batch_output_usd_per_mtok": num(m.get("batch_output")),
        "long_context_threshold_tokens": num(lc.get("threshold_tokens")),
        "long_context_input_usd_per_mtok": num(lc.get("input")),
        "long_context_output_usd_per_mtok": num(lc.get("output")),
        "source_url": m.get("source_url") or "",
        "checked_on": m.get("checked") or "",
        "note": " ".join((m.get("note") or "").split()),
    }


def key_rows(models: list[dict]) -> list[dict]:
    """Every id a usage log may carry: the model id, each alias, provider/model.

    A key priced by more than one provider (an open-weights model on two hosts)
    gets one default: the provider named in the key prefix if there is one,
    otherwise the first provider alphabetically. Pass provider_col to the
    macros to pick a host explicitly.
    """
    seen: dict[tuple[str, str], dict] = {}
    for m in models:
        provider = m["provider"].lower()
        keys = [m["model"], *m.get("aliases", []), f"{provider}/{m['model']}"]
        for key in keys:
            k = key.strip().lower()
            seen.setdefault((k, provider), {"model_key": k, "provider": provider, "model": m["model"]})
    by_key: dict[str, list[dict]] = {}
    for row in seen.values():
        by_key.setdefault(row["model_key"], []).append(row)
    out = []
    for key, rows in sorted(by_key.items()):
        prefix = key.split("/", 1)[0] if "/" in key else None
        rows.sort(key=lambda r: (r["provider"] != prefix, r["provider"]))
        for i, row in enumerate(rows):
            out.append({**row, "is_default": "true" if i == 0 else "false"})
    return out


def write(path: Path, columns: list[str], rows: list[dict]) -> None:
    with path.open("w", encoding="utf-8", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=columns, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def cost(m: dict, inp: int, out: int, cache_read: int = 0, cache_write: int = 0,
         batch: bool = False):
    i = m.get("batch_input" if batch else "input")
    o = m.get("batch_output" if batch else "output")
    if i is None:
        return None
    total = Decimal(str(i)) * inp
    if out:
        if o is None:
            return None
        total += Decimal(str(o)) * out
    if cache_read:
        cr = m.get("cache_read")
        total += Decimal(str(cr if cr is not None else i)) * cache_read
    if cache_write:
        cw = (m.get("cache_write") or {}).get("5m")
        total += Decimal(str(cw if cw is not None else i)) * cache_write
    return format((total / Decimal(1_000_000)).normalize(), "f")


def write_test_usage(models: list[dict]) -> None:
    def find(provider, model):
        return next(m for m in models if m["provider"] == provider and m["model"] == model)

    claude = next(m for m in models if m["provider"] == "anthropic" and m["status"] == "listed"
                  and m.get("cache_read") is not None and m.get("batch_input") is not None)
    gpt = find("openai", "gpt-4.1")
    deepseek = next(m for m in models if m["provider"] == "deepseek" and m.get("aliases"))
    groq = find("groq", "openai/gpt-oss-120b")
    together = find("together", "openai/gpt-oss-120b")
    embed = next(m for m in models if m.get("output") is None and m.get("input") is not None)

    cases = [
        (1, claude["model"], "", 12000, 800, 0, 0, claude),
        (2, "  " + claude["model"].upper() + " ", "", 5000, 1000, 40000, 2000, claude),
        (3, f"openai/{gpt['model']}", "", 1_000_000, 250_000, 0, 0, gpt),
        (4, deepseek["aliases"][0], "", 7000, 3000, 0, 0, deepseek),
        (5, "openai/gpt-oss-120b", "", 100000, 50000, 0, 0, groq),
        (6, "openai/gpt-oss-120b", "together", 100000, 50000, 0, 0, together),
        (7, embed["model"], "", 20000, 0, 0, 0, embed),
        (8, "not-a-real-model-xyz", "", 1000, 1000, 0, 0, None),
        (9, gpt["model"], "openai", 3000, 400, 1000, 0, gpt),
        (10, gpt["model"], "anthropic", 3000, 400, 0, 0, None),
    ]
    rows = []
    for cid, model, provider, inp, out, cr, cw, m in cases:
        rows.append({
            "usage_id": cid,
            "model": model,
            "provider": provider,
            "input_tokens": inp,
            "output_tokens": out,
            "cache_read_tokens": cr,
            "cache_write_tokens": cw,
            "expected_cost_usd": "" if m is None else (cost(m, inp, out, cr, cw) or ""),
            "expected_batch_cost_usd": "" if m is None else (cost(m, inp, out, cr, cw, batch=True) or ""),
        })
    write(ROOT / "integration_tests" / "seeds" / "llm_prices_test_usage.csv",
          list(rows[0].keys()), rows)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--tag", default=DEFAULT_TAG)
    ap.add_argument("--prices", help="local prices.json instead of the release")
    args = ap.parse_args()
    data = load(args)
    models = data["models"]
    write(ROOT / "seeds" / "llm_prices_models.csv", MODEL_COLUMNS,
          sorted((model_row(m) for m in models), key=lambda r: (r["provider"], r["model"])))
    write(ROOT / "seeds" / "llm_prices_keys.csv", KEY_COLUMNS, key_rows(models))
    write_test_usage(models)
    print(f"{len(models)} models, generated {data.get('generated')}")


if __name__ == "__main__":
    main()
