This is a small, reproducible script that calculates total real value secured by the code snippets discussed in this repository.

[`fetch-ng-tvl.sh`](./fetch-ng-tvl.sh) sums the total US-dollar value of assets deposited in the pools across all pools utilising the code discussed in this repository. The data is fetched via the public [Curve API](https://docs.curve.finance/protocol/api/curve-api). These are the Vyper 0.3.10-era pools whose core contracts the three changes in the [root README](../../README.md) describe: `exchange_received`, the WETH-only transfer path, and the internal `_claim_admin_fees`.

```bash
# needs: bash, curl, jq
./fetch-ng-tvl.sh
```

## Snapshot: 2026-06-19 (live)

| Contract Type | Total Value (USD) | # Active Liquidity Pools |
|---|---:|---:|
| Stablecoins | $793.7M | 987 |
| 2-asset Volatile Markets | $277.6M | 361 |
| 3-asset Volatile markets | $30.2M | 131 |
| Grand total | ≈ $1.10 B | 1,479 |

The total value moves with prices and deposits, so re-running on another day gives a slightly different number.
