# Native ETH makes a misconfigured lock drainable; ERC20 keeps it safe

A runnable demonstration of why the work removed native-ETH transfers. The same attack drains a pool that pays in native ETH and leaves a pool that pays in an ERC20 asset untouched, even when both carry the identical lock mistake.

This is the teaching version of [change 2 (removing native ETH)](../../README.md#2-disallowing-handing-over-execution-context-to-external-callers) in the root README, and the [July 2023 hack](../../README.md#summary) it followed from.

## The setup

Both pools are the same deposit ledger with the same bug in the lock: the two value-moving functions, `withdraw()` and `withdraw_to()`, guard with different reentrancy keys (`lock_main` and `lock_emergency`). A reentrancy lock only blocks re-entry into functions that share its key, so neither function blocks re-entry through the other. In correct modern Vyper, separate keys really do get separate slots, so this is a genuine developer mistake. It is the same shape as the July 2023 Vyper bug, where functions meant to share one lock compiled to separate slots.

Both `withdraw` functions also pay out before zeroing the ledger (a checks-effects-interactions violation).

The only difference between the two pools is how value leaves:
- `vulnerable_eth_pool.vy` sends native ETH with `raw_call(..., value=amount)`, which runs the recipient's code.
- `safe_erc20_pool.vy` sends an ERC20 asset with `transfer`, which moves a number in the asset's ledger and does not call the recipient.

## The attack

1. The attacker deposits 1 unit.
2. The attacker calls `withdraw()`. The pool pays out before zeroing.
3. The native-ETH payout runs the attacker's `__default__`, which re-enters through `withdraw_to()`. That path is not covered by `lock_main`, so it proceeds and pays a second time while the ledger still reads 1.
4. The attacker walks away with 2 units for a 1-unit deposit. The pool is now short, and an honest depositor cannot be fully repaid.

Against the ERC20 pool, step 3 never happens: the ERC20 `transfer` does not call the attacker, so `__default__` is never reached. The same misconfigured lock is harmless because there is no callback to exploit.

## The point

With native ETH, safety depends on the reentrancy lock being correct. Remove native ETH, and that dependency is gone: an ERC20-only pool is not exploitable this way regardless of the lock. The fix removes the precondition rather than trusting a guard, which is the defense-in-depth argument in the [root README](../../README.md#summary).

A note on scope: both pools here keep the same checks-effects-interactions violation on purpose (they pay out before zeroing the ledger), so the only variable that changes between them is native ETH versus ERC20. The real NG contracts also fix the ordering, updating internal balances before any external call (checks-effects-interactions), which is a second independent defense, the commit-before-handoff book-keeping described in [change 2 of the root README](../../README.md#2-disallowing-handing-over-execution-context-to-external-callers).

## Run it

```bash
# from this directory; uv fetches titanoboa (Vyper 0.3.10 compiler + in-process EVM) and pytest
uv run --with titanoboa --with pytest pytest -q
```

Expected:
- `test_native_eth_pool_is_drained` passes: the attacker ends with 2 units, the pool is insolvent, and the callback re-entered.
- `test_erc20_pool_is_safe` passes: the attacker ends with exactly its deposit, the pool is solvent, and the callback never fired.

## Files

- `vulnerable_eth_pool.vy` native-ETH pool with the split-key lock
- `safe_erc20_pool.vy` same pool, ERC20-only, same split-key lock
- `attacker.vy` re-enters on the ETH callback
- `erc20_attacker.vy` same logic, never gets a callback
- `mock_erc20.vy` minimal ERC20 for the test
- `test_reentrancy.py` runs the attack against both pools
