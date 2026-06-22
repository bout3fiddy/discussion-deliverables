# Examples

Three small, runnable examples. The first two are Vyper contracts, the third a short Python benchmark.

1. [01-native-asset-reentrancy](./01-native-asset-reentrancy/): a pool that pays in the native asset is drained when Vyper 0.3.0 miscompiles its reentrancy lock, and the same pool paying an ERC20 asset is not.
2. [02-erc20-asset-approvals](./02-erc20-asset-approvals/): why an ERC20 asset swap needs an approval, and how transferring first and swapping in the same transaction avoids one.
3. [03-branch-prediction](./03-branch-prediction/): the same loop runs faster on sorted input, because the CPU's branch predictor guesses the branch almost perfectly on ordered data.

The two Vyper examples share `mock_erc20_asset.vy` in this folder.
