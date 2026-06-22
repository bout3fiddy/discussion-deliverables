# Examples

Three small, runnable examples that demonstrate the ideas behind the changes and the lessons. The first two are Vyper contracts tested with titanoboa (the same stack the real pools use); the third is a short benchmark. Each example is self-contained, with its own README.

1. [01-native-eth-reentrancy](./01-native-eth-reentrancy/) shows why native ETH transfers plus a misconfigured reentrancy lock are drainable, and how moving value as an ERC20 asset removes the dependency on the lock being correct. Teaching version of change 2 in the [root README](../README.md#2-removing-native-eth).
2. [02-erc20-approvals](./02-erc20-approvals/) shows why an ERC20 transfer needs an approval, and how the send-then-call pattern does the same trade without one. Teaching version of change 1 in the [root README](../README.md#1-optimistic-transfers-exchange_received).
3. [03-branch-prediction](./03-branch-prediction/) shows the same loop running faster on sorted input, because the speed comes from the CPU's branch predictor. The hardware side of lessons 0 and 1 in the [root README](../README.md#engineering-lessons).

The first two are teaching contracts, deliberately minimal.

## Run

```bash
# uv fetches dependencies into an ephemeral env; no manual venv or install step.
# titanoboa brings the Vyper 0.3.10 compiler and an in-process EVM (for examples 1 and 2).
cd 01-native-eth-reentrancy && uv run --with titanoboa --with pytest pytest -q
cd ../02-erc20-approvals && uv run --with titanoboa --with pytest pytest -q
cd ../03-branch-prediction && python3 branch_bench.py    # no dependencies
```
