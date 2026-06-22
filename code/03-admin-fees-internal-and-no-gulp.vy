# =============================================================================
# Internalizing admin-fee claims and removing the "gulp"
#
# OLD: a PUBLIC claim_admin_fees() re-synced tracked balances to the real ERC20
#      balanceOf (the literal "# Gulp here" block) -> any tokens donated to the
#      pool were silently swept in and counted as profit. A side effect that
#      became a feature.
# NEW: _claim_admin_fees() is @internal, auto-triggered, and derives fees ONLY
#      from the xcp_profit invariant counters. balanceOf is never used to redefine
#      balances, so donations are never monetized as profit.
#
# Excerpt for discussion, not a full contract. See ../README.md -> change 3.
# `# ...` marks elided lines.
# =============================================================================


# ======================== BEFORE: old tricrypto =============================
# Source: curve-crypto-contract/contracts/tricrypto/CurveCryptoSwap.vy @ d7d04cd

@internal
def _claim_admin_fees():
    A_gamma: uint256[2] = self._A_gamma()

    xcp_profit: uint256 = self.xcp_profit
    xcp_profit_a: uint256 = self.xcp_profit_a

    # Gulp here                              <-- THE PROBLEM: tracked balances are
    _coins: address[N_COINS] = coins         #   overwritten with the real ERC20
    for i in range(N_COINS):                 #   balance, so any donated tokens get
        self.balances[i] = ERC20(_coins[i]).balanceOf(self)  # absorbed into "profit".

    vprice: uint256 = self.virtual_price

    if xcp_profit > xcp_profit_a:
        fees: uint256 = (xcp_profit - xcp_profit_a) * self.admin_fee / (2 * 10**10)
        if fees > 0:
            receiver: address = self.admin_fee_receiver
            if receiver != ZERO_ADDRESS:
                frac: uint256 = vprice * 10**18 / (vprice - fees) - 10**18
                claimed: uint256 = CurveToken(token).mint_relative(receiver, frac)
                xcp_profit -= fees*2
                self.xcp_profit = xcp_profit
                log ClaimAdminFee(receiver, claimed)

    total_supply: uint256 = CurveToken(token).totalSupply()

    # Recalculate D b/c we gulped          <-- the donation now changes the invariant
    D: uint256 = Math(math).newton_D(A_gamma[0], A_gamma[1], self.xp())
    self.D = D
    self.virtual_price = 10**18 * self.get_xcp(D) / total_supply
    # ...


# ...and it was exposed publicly, so anyone could trigger the gulp on demand:
@external
@nonreentrant('lock')
def claim_admin_fees():
    self._claim_admin_fees()


# ========================== AFTER: tricrypto-ng ==============================
# Source: tricrypto-ng/contracts/main/CurveTricryptoOptimized.vy @ ecaa816
# @internal only (no public wrapper). Fees come from the xcp_profit accounting,
# NOT from re-reading balanceOf. There is no balance "gulp".

@internal
def _claim_admin_fees():
    """
    @notice Claims admin fees and sends it to fee_receiver set in the factory.
    """
    # Skip if claimed too recently, or while pool parameters are ramping:
    last_claim_time: uint256 = self.last_admin_fee_claim_timestamp
    if (
        unsafe_sub(block.timestamp, last_claim_time) < MIN_ADMIN_FEE_CLAIM_INTERVAL or
        self.future_A_gamma_time > block.timestamp
    ):
        return

    xcp_profit: uint256 = self.xcp_profit      # <- current pool profits (invariant-based)
    xcp_profit_a: uint256 = self.xcp_profit_a  # <- profits at the previous claim
    current_lp_token_supply: uint256 = self.totalSupply

    # No new invariant profit => nothing to claim. A donation cannot create profit
    # here, because profit is (xcp_profit - xcp_profit_a), not balanceOf - balances.
    if xcp_profit <= xcp_profit_a or current_lp_token_supply < 10**18:
        return

    balances: uint256[N_COINS] = self.balances  # read, never overwritten from balanceOf
    # ... admin's share is minted from (xcp_profit - xcp_profit_a) only ...


# It is never public. It runs only as an internal side effect of normal
# operations (add_liquidity / exchange / remove_liquidity), e.g.:
    self._claim_admin_fees()  # <--------- Auto-claim admin fees occasionally.
