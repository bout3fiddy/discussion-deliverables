# ERC20 asset swaps need an approval, and how to skip it

An ERC20 asset is a ledger inside its own contract, and a pool cannot move a user's balance unless the user first grants it an allowance. The standard flow is `approve(pool, amount)`, then `pool.swap(...)`, then the pool calls `transferFrom(user, pool, dx)`, which the asset allows only up to the approval. `swap()` in `swap_pool.vy` is that flow, and without the approval `transferFrom` reverts.

The asset's own `transfer` needs no allowance, so the caller can send the asset to the pool and then call `pool.swap_received(...)`, which reads `dx = balanceOf(self) - stored[i]`, the surplus over its recorded reserve, and swaps on that. No approval is ever granted, which is how `exchange_received` works in the real pools.

The two steps must happen in one transaction. Assets transferred without the follow-up call sit as surplus that the next caller of `swap_received` can claim, so the pattern suits routers and other controlled callers that bundle both steps atomically.

## Run it

```bash
# from this directory; uv fetches titanoboa into an ephemeral env
uv run --with titanoboa demo.py
```

The script prints each step and checks `transferFrom` reverting without an approval, `swap_received` completing with the allowance still zero, and surplus left by a missing follow-up call being claimable by anyone.

## Files

- `swap_pool.vy` minimal two-asset pool with both `swap` and `swap_received`
- `../mock_erc20_asset.vy` minimal ERC20 asset, shared with example 01
- `demo.py` the three demonstrations above
