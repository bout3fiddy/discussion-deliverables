# Examples

Three small, runnable examples that demonstrate the ideas behind the changes and the lessons. The first two are Vyper contracts, and the third is a short benchmark.

1. [01-native-eth-reentrancy](./01-native-eth-reentrancy/) shows why native asset transfers plus a misconfigured reentrancy lock are drainable, and how moving value as an ERC20-standard asset removes the dependency on the lock being correct. Teaching version of change 2 in the [root README](../README.md#2-removing-native-eth).
2. [02-erc20-approvals](./02-erc20-approvals/) shows why an ERC20-standard asset needs an approval for a transfer, and how the transfer-then-exchange pattern does the same exchange without one. Teaching version of change 1 in the [root README](../README.md#1-optimistic-transfers-exchange_received).
3. [03-branch-prediction](./03-branch-prediction/) shows the same loop running faster on sorted input, because the speed comes from the CPU's branch predictor. The hardware side of lessons 0 and 1 in the [root README](../README.md#engineering-lessons).
