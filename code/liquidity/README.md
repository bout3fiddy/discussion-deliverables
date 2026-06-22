# Liquidity held by the NG contracts

A small, reproducible script that answers a fair question: how much real value sits behind the code discussed in this repo?

[`fetch-ng-tvl.sh`](./fetch-ng-tvl.sh) sums on-chain TVL (total value locked, the total US-dollar value of assets deposited in the pools) across the three "NG" factory registries (Stableswap-NG, Tricrypto-NG, Twocrypto-NG) over every Curve network, via the public [Curve API](https://docs.curve.finance/protocol/api/curve-api). These are the Vyper 0.3.10-era pools whose core contracts the three changes in the [root README](../../README.md) describe: `exchange_received`, the WETH-only transfer path, and the internal `_claim_admin_fees`.

```bash
# needs: bash, curl, jq
./fetch-ng-tvl.sh
```

## Snapshot: 2026-06-19 (live)

| Registry | TVL (USD) | Active pools |
|---|---:|---:|
| Stableswap-NG (`factory-stable-ng`) | $793.7M | 987 |
| Twocrypto-NG (`factory-twocrypto`) | $277.6M | 361 |
| Tricrypto-NG (`factory-tricrypto`) | $30.2M | 131 |
| Grand total | ≈ $1.10 B | 1,479 |

Largest pools at snapshot time: Spark.fi PYUSD Reserve ($100M), Yield Basis cbBTC ($83M), RLUSD/USDC ($71M), and FRAXUSDe ($50M). Ethereum dominates, with meaningful deployments on Base, Fraxtal, Arbitrum, and Hyperliquid.

TVL moves with prices and deposits, so re-running on another day gives a slightly different number. The figure is measured.

## Correctness notes

1. No double-counting of metapools (a pool that pairs an asset against the deposit-share asset of another "base" pool, so liquidity nests). The script sums `data.tvlAll` (the API's sum of each pool's `usdTotalExcludingBasePool`) rather than a naive sum of `poolData[].usdTotal`. A metapool's base-pool liquidity is already counted in the base pool's own entry, so the naive sum overcounted Ethereum stable-ng by ~$8M.
2. Per-network iteration. The `/getPools/all/<registry>` aggregate endpoint is currently broken for these registries (it returns `success:true` with an empty payload), so the script iterates per network and sums. `api.curve.fi` 301-redirects to the canonical `api.curve.finance`.

## Implementation addresses

Each registry resolves to dedicated NG implementation contracts (uncomment the last block of the script to print them). Twocrypto-NG routes all pools through a single implementation `0x04Fd6beC7D45EFA99a27D29FB94b55c56dD07223`, and Tricrypto-NG's primary implementation is `0x66442B0C5260B92cAa9c234ECf2408CBf6b19a6f`. These addresses confirm a pool runs the current -ng / 0.3.10 code rather than a legacy implementation.
