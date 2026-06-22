# ERC20 transfers need an approval, and how to skip it

A runnable demonstration of why approvals exist for ERC20 assets, and how the transfer-then-exchange pattern does the same trade without one. This is the teaching version of [change 1 (optimistic transfers)](../../README.md#1-optimistic-transfers-exchange_received) in the root README.

## Why an approval is needed at all

An ERC20 asset is a ledger inside its own contract. The balances live there, and the user's wallet only holds the right to move them. A pool cannot reach into that ledger on a user's behalf unless the user has first granted it permission. That permission is the approval (the allowance). The standard pull flow is:

1. the user calls `approve(pool, amount)` on the asset,
2. the user calls `pool.swap(...)`,
3. the pool calls `transferFrom(user, pool, dx)`, which the asset allows only up to the approval.

`swap()` in `swap_pool.vy` is that flow. Without step 1, `transferFrom` reverts. The test `test_swap_requires_an_approval` shows the revert, then shows the swap succeeding once the approval is granted.

## How to skip it

The asset's ledger does not need the pool's involvement for a plain `transfer`. So the caller can send the asset to the pool directly, then ask the pool to act on what arrived:

1. the user calls `transfer(pool, dx)` on the asset,
2. the user calls `pool.swap_received(...)`,
3. the pool reads `dx = balanceOf(self) - stored[i]`, the surplus over its recorded reserve, and proceeds.

No approval is ever granted. The test `test_swap_received_needs_no_approval` confirms the allowance stays zero and the trade still completes. This is the pattern behind `exchange_received` in the real pools: it removes the standing permission a pool would otherwise hold over a user's wallet.

## The catch

The two steps must happen together in one transaction. Assets transferred to the pool without the follow-up call sit there as surplus, and the next caller of `swap_received` can claim them. `test_assets_sent_without_the_call_are_claimable_by_anyone` shows exactly that: Alice sends assets and forgets the call, Bob claims the output. This is why the pattern suits routers and other controlled callers that bundle both steps into one atomic transaction, and why landing it safely was as much integrator coordination as code.

## Run it

```bash
# from this directory; uv fetches titanoboa and pytest into an ephemeral env
uv run --with titanoboa --with pytest pytest -q
```

## Files

- `swap_pool.vy` minimal two-asset pool with both `swap` and `swap_received`
- `mock_erc20.vy` minimal ERC20 with `approve` / `transferFrom`
- `test_approvals.py` the three demonstrations above
