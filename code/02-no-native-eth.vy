# =============================================================================
# Removing native-ETH transfers: value now moves only through WETH / ERC20
#
# Native ETH moves value with a low-level CALL, which runs the recipient's
# fallback/receive code -> an implicit external callback. That is the exact
# surface the July-2023 Vyper reentrancy-lock bug was exploited through. The NG
# pools delete native ETH entirely; value moves only through ERC20 transfers,
# which never hand control to an arbitrary fallback.
#
# Before/after are the SAME lineage in the tricrypto-ng repo:
#   git shows CurveTricryptoOptimized.vy was created as a 99%-similar copy
#   (C099) of CurveTricryptoOptimizedWETH.vy; PR #23 "remove_eth_transfers"
#   (commit 0ad0764 "feat: no more weth; no more public claim_admin_fees",
#   51 insertions / 172 deletions = -121 lines) stripped the native-ETH path.
#
# Excerpt for discussion, not a full contract. See ../README.md -> change 2.
# `# ...` marks elided lines.
# =============================================================================


# ========================= BEFORE: CurveTricryptoOptimizedWETH.vy ============
# Source: tricrypto-ng/contracts/main/CurveTricryptoOptimizedWETH.vy @ ecaa816
# (the audited June-2023 predecessor; ChainSecurity notes it "Handles native Ether")

# 1) The pool had to be payable just to receive raw ETH:
@payable
@external
def __default__():
    pass


# 2) Transferring out could push NATIVE ETH, which runs the receiver's code:
@internal
def _transfer_out(
    _coin: address, _amount: uint256, use_eth: bool, receiver: address
):
    if use_eth and _coin == WETH20:
        raw_call(receiver, b"", value=_amount)  # <-- native send: hands control to
                                                #     receiver's fallback mid-call
    else:
        if _coin == WETH20:
            WETH(WETH20).deposit(value=_amount)
        assert ERC20(_coin).transfer(
            receiver, _amount, default_return_value=True
        )
        # _transfer_in carried the same use_eth/WETH.withdraw() machinery.


# ========================== AFTER: CurveTricryptoOptimized.vy =================
# Source: tricrypto-ng/contracts/main/CurveTricryptoOptimized.vy @ ecaa816
# No @payable, no __default__, no raw_call(value=...), no use_eth flag.
# Value moves only via ERC20 (grep confirms: 0 occurrences of raw_call here).

@internal
def _transfer_in(
    _coin_idx: uint256,
    _dx: uint256,
    sender: address,
    expect_optimistic_transfer: bool,
) -> uint256:
    # ... (optimistic branch elided; see 01-optimistic-transfers.vy) ...

    # ----------------------------------------------- ERC20 transferFrom flow.
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
    # EXTERNAL CALL  --  a plain ERC20 transfer; never calls back into the pool
    assert ERC20(coins[_coin_idx]).transfer(
        receiver,
        _amount,
        default_return_value=True
    )
