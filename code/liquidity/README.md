A small, reproducible script that sums the real US-dollar value held by the pools whose core contracts the three changes describe. [`fetch_total_value.py`](./fetch_total_value.py) totals the deposits across those pools from the public [Curve API](https://docs.curve.finance/protocol/api/curve-api). These are the Vyper 0.3.10-era pools carrying `exchange_received`, the ERC20-asset-only transfer path, and the internal `_claim_admin_fees`, as described in the [root README](../../README.md).

```bash
uv run fetch_total_value.py
```

## Snapshot: 2026-06-23

≈ $1.11 B across 1,481 active liquidity pools.

The total value moves with prices and deposits, so re-running on another day gives a slightly different number.
