# =============================================================================
# Approval-free ("optimistic") swaps  -  Curve Stableswap-NG
#
# Source : contracts/main/CurveStableSwapNG.vy
# Repo   : github.com/curvefi/stableswap-ng  @ 2abe778
# Lines  : exchange_received L534-565, _transfer_in L356-395
#
# This is an EXCERPT for discussion, not a full contract. See ../README.md -> change 1.
# =============================================================================

# --- Public entry point: swap WITHOUT granting the pool an ERC20 approval ----
# The caller transfers tokens straight to the pool, THEN calls this in the same tx.
@external
@nonreentrant('lock')
def exchange_received(
    i: int128,
    j: int128,
    _dx: uint256,
    _min_dy: uint256,
    _receiver: address = msg.sender,
) -> uint256:
    """
    @notice Perform an exchange between two coins without transferring token in
    @dev The contract swaps tokens based on a change in balance of coin[i]. The
         dx = ERC20(coin[i]).balanceOf(self) - self.stored_balances[i]. Users of
         this method are dex aggregators, arbitrageurs, or other users who do not
         wish to grant approvals to the contract: they would instead send tokens
         directly to the contract and call `exchange_received`.
         Note: This is disabled if pool contains rebasing tokens.
    @param i Index value for the coin to send
    @param j Index value of the coin to receive
    @param _dx Amount of `i` being exchanged
    @param _min_dy Minimum amount of `j` to receive
    @param _receiver Address that receives `j`
    @return Actual amount of `j` received
    """
    assert not pool_contains_rebasing_tokens  # dev: exchange_received not supported if pool contains rebasing tokens
    return self._exchange(
        msg.sender,
        i,
        j,
        _dx,
        _min_dy,
        _receiver,
        True,  # <--------------------------------------- swap optimistically.
    )

# --- The transfer-in logic that makes it possible -----------------------------

@internal
def _transfer_in(
    coin_idx: int128,
    dx: uint256,
    sender: address,
    expect_optimistic_transfer: bool,
) -> uint256:
    """
    @notice Contains all logic to handle ERC20 token transfers.
    @param coin_idx Index of the coin to transfer in.
    @param dx amount of `_coin` to transfer into the pool.
    @param sender address to transfer `_coin` from.
    @param receiver address to transfer `_coin` to.
    @param expect_optimistic_transfer True if contract expects an optimistic coin transfer
    """
    _dx: uint256 = ERC20(coins[coin_idx]).balanceOf(self)

    # ------------------------- Handle Transfers -----------------------------

    if expect_optimistic_transfer:

        _dx = _dx - self.stored_balances[coin_idx]
        assert _dx >= dx

    else:

        assert dx > 0  # dev : do not transferFrom 0 tokens into the pool
        assert ERC20(coins[coin_idx]).transferFrom(
            sender, self, dx, default_return_value=True
        )

        _dx = ERC20(coins[coin_idx]).balanceOf(self) - _dx

    # --------------------------- Store transferred in amount ---------------------------

    self.stored_balances[coin_idx] += _dx

    return _dx

