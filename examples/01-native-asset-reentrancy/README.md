# A reentrancy drain, and two independent ways to stop it

`pool.vy` is one deposit pool deployed three ways, changing a single variable each time. `withdraw()` and `withdraw_to()` share one `@nonreentrant('lock')` key, written the correct way. Vyper 0.3.0 miscompiles it: two functions that share a key are given separate storage slots, so a call already inside `withdraw()` is not blocked from re-entering `withdraw_to()`.

1. Native asset, interaction before effect: the payout uses `raw_call`, which runs the attacker's `__default__`. It re-enters through `withdraw_to()` while the ledger still shows the old balance, and walks away with 2 units for a 1-unit deposit, leaving the pool insolvent.
2. ERC20 asset, same lock: the payout is an ERC20 `transfer`, which moves a number and never calls the attacker, so `__default__` never fires and the same lock is harmless.
3. Native asset, effect before interaction: the pool zeroes the ledger before paying out, so the re-entrant `withdraw_to()` reads a zeroed balance and reverts. The attack fails even with the broken lock and the native asset.

## Run it

The lock bug lives in the Vyper 0.3.0 compiler, which needs Python 3.10 or earlier, so the toolchain is pinned (uv fetches all of it). The EVM is pyrevm, a Python binding over the revm engine:

```bash
# from this directory
uv run --python 3.10 --with 'vyper==0.3.0' --with pyrevm --with eth-abi --with eth-utils demo.py
```

The script deploys the pool for each case and prints the outcome: the native-asset pool is drained, the ERC20 asset pool stays safe, and the checks-effects-interactions pool reverts the attack with nothing stolen.

## Files

- `pool.vy` the deposit pool, deployed three ways via its `NATIVE` and `CEI` flags
- `attacker.vy` deposits, calls `withdraw()`, and re-enters on the native-asset callback
- `../mock_erc20_asset.vy` minimal ERC20 asset, shared with example 02
- `evm.py` minimal pyrevm harness: compile, deploy, and call a contract by signature
- `demo.py` runs all three cases and prints the outcome
