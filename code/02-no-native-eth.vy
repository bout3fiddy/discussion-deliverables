# =============================================================================
# Removing native-asset transfers: value now moves only through ERC20 assets.
#
# A native-asset transfer uses a low-level CALL that runs the recipient's fallback,
# handing execution context to an external caller. That callback is the exact
# surface the July 2023 Vyper reentrancy-lock bug was exploited through. The NG
# pools remove native-asset transfers entirely; value then moves only through
# ERC20 asset transfers, which never call into an arbitrary fallback.
#
# CurveTricryptoOptimized.vy was created from CurveTricryptoOptimizedWETH.vy by
# PR #23 ("remove_eth_transfers"), which stripped the native-asset path.
#
# Excerpt for discussion, not a full contract. See ../README.md (change 2).
# `# ...` marks elided lines.
# =============================================================================


# ========================= BEFORE: CurveTricryptoOptimizedWETH.vy ============
# The audited June 2023 predecessor.
# __default__:   https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimizedWETH.vy#L307
# _transfer_out: https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimizedWETH.vy#L380

# 1) The pool had to be payable just to receive the raw native asset:
@payable
@external
def __default__():
    pass


# 2) Transferring out could push the NATIVE ASSET, which runs the receiver's code:
@internal
def _transfer_out(
    _coin: address, _amount: uint256, use_eth: bool, receiver: address
):
    if use_eth and _coin == WETH20:
        raw_call(receiver, b"", value=_amount)  # <-- native-asset send: hands control to
                                                #     receiver's fallback mid-call
    else:
        if _coin == WETH20:
            WETH(WETH20).deposit(value=_amount)
        assert ERC20(_coin).transfer(
            receiver, _amount, default_return_value=True
        )
        # _transfer_in carried the same use_eth/WETH.withdraw() machinery.


# ========================== AFTER: CurveTricryptoOptimized.vy =================
# No @payable, no __default__, no raw_call(value=...), no use_eth flag; value
# moves only via ERC20 asset transfers (grep confirms 0 occurrences of raw_call).
# _transfer_in:  https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy#L287
# _transfer_out: https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy#L339

@internal
def _transfer_in(
    _coin_idx: uint256,
    _dx: uint256,
    sender: address,
    expect_optimistic_transfer: bool,
) -> uint256:
    # ... (optimistic branch elided; see 01-optimistic-transfers.vy) ...

    # snapshot the reserve BEFORE the transfer, to measure what actually arrives
    coin_balance: uint256 = ERC20(coins[_coin_idx]).balanceOf(self)

    # ERC20 asset transferFrom flow:
    # EXTERNAL CALL
    assert ERC20(coins[_coin_idx]).transferFrom(
        sender,
        self,
        _dx,
        default_return_value=True
    )
    dx: uint256 = ERC20(coins[_coin_idx]).balanceOf(self) - coin_balance
    self.balances[_coin_idx] += dx
    return dx


@internal
def _transfer_out(_coin_idx: uint256, _amount: uint256, receiver: address):
    # Adjust balances before handling transfers:
    self.balances[_coin_idx] -= _amount
    # EXTERNAL CALL: a plain ERC20 asset transfer; never calls back into the pool
    assert ERC20(coins[_coin_idx]).transfer(
        receiver,
        _amount,
        default_return_value=True
    )
