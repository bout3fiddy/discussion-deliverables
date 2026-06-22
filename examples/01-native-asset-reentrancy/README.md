# A reentrancy drain, and two independent ways to stop it

`pool.vy` is one deposit pool deployed three ways, changing a single variable each time. Its bug is constant: `withdraw()` and `withdraw_to()` guard with two separate locks (`locked_main` and `locked_emergency`) instead of one shared lock, so a call already inside `withdraw()` is not blocked from re-entering `withdraw_to()`.

1. Native asset, interaction before effect: the payout uses `raw_call`, which runs the attacker's `__default__`. It re-enters through `withdraw_to()` while the ledger still shows the old balance, and walks away with 2 units for a 1-unit deposit, leaving the pool insolvent.
2. ERC20 asset, same lock: the payout is an ERC20 `transfer`, which moves a number and never calls the attacker, so `__default__` never fires and the same lock is harmless.
3. Native asset, effect before interaction: the pool zeroes the ledger before paying out, so the re-entrant `withdraw_to()` reads a zeroed balance and reverts. The attack fails even with the broken lock and the native asset.

## Run it

```bash
# from this directory; uv fetches titanoboa (the Vyper compiler and an in-process EVM)
uv run --with titanoboa demo.py
```

The script deploys the pool for each case and prints the outcome: the native-asset pool is drained, the ERC20 asset pool stays safe, and the checks-effects-interactions pool reverts the attack with nothing stolen.

## Files

- `pool.vy` the deposit pool, deployed three ways via its `NATIVE` and `CEI` flags
- `attacker.vy` deposits, calls `withdraw()`, and re-enters on the native-asset callback
- `../mock_erc20_asset.vy` minimal ERC20 asset, shared with example 02
- `demo.py` runs all three cases and prints the outcome
