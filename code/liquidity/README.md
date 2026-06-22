A small, reproducible script that sums the real US-dollar value held by the pools whose core contracts the three changes describe. [`fetch-total-value.sh`](./fetch-total-value.sh) totals the deposits across those pools from the public [Curve API](https://docs.curve.finance/protocol/api/curve-api). These are the Vyper 0.3.10-era pools carrying `exchange_received`, the ERC20-asset-only transfer path, and the internal `_claim_admin_fees`, as described in the [root README](../../README.md).

```bash
# needs: bash, curl, jq
./fetch-total-value.sh
```

## Snapshot: 2026-06-19 (live)

| Contract Type | Total Value (USD) | # Active Liquidity Pools |
|---|---:|---:|
| Stablecoins | $793.7M | 987 |
| 2-asset Volatile Markets | $277.6M | 361 |
| 3-asset Volatile markets | $30.2M | 131 |
| Grand total | ≈ $1.10 B | 1,479 |

The total value moves with prices and deposits, so re-running on another day gives a slightly different number.
