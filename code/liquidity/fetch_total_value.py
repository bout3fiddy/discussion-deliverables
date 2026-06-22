#!/usr/bin/env python3
"""Total liquidity (TVL) held by the contracts discussed in this repository.

TVL basis is `data.tvlAll`: the API's sum of each pool's
usdTotalExcludingBasePool. Summing poolData[].usdTotal instead double-counts
metapools, whose base-pool liquidity already shows up in the base pool's entry.

Usage: uv run fetch_total_value.py
"""

import json
from concurrent.futures import ThreadPoolExecutor
from typing import Any
from urllib.request import Request, urlopen

API = "https://api.curve.finance/api"

# The three NG factory registries whose core contracts the README discusses.
REGISTRIES = ["factory-stable-ng", "factory-tricrypto", "factory-twocrypto"]


def fetch(path: str) -> Any:
    """GET one API path and return its `data` payload, or exit if the request fails."""
    req = Request(f"{API}/{path}", headers={"User-Agent": "curl"})

    try:
        with urlopen(req, timeout=150) as r:
            return json.load(r).get("data")
    except Exception as exc:
        raise SystemExit(f"could not reach API: {exc}") from exc


def main():
    # getPlatforms maps each network to the registries it serves, so we fetch
    # only the (registry, network) pairs that actually exist.
    platforms = fetch("getPlatforms")["platforms"]
    jobs = [
        (registry, net)
        for net, served in platforms.items()
        for registry in REGISTRIES
        if registry in served
    ]

    # Fetch every pair concurrently, dropping networks that returned nothing.
    def pool_data(job: tuple[str, str]) -> Any:
        registry, net = job
        return fetch(f"getPools/{net}/{registry}")

    with ThreadPoolExecutor(max_workers=len(jobs)) as thread_pool:
        results = thread_pool.map(pool_data, jobs)
    payloads = [data for data in results if data]

    # Total the per-registry TVL, and count the pools that hold any liquidity.
    total = sum(p.get("tvlAll", 0) for p in payloads)
    active = [
        d for p in payloads for d in p.get("poolData", []) if d.get("usdTotal", 0) > 0
    ]

    print(f"{total:,.0f}")
    print(f"{len(active):,}")


if __name__ == "__main__":
    main()
