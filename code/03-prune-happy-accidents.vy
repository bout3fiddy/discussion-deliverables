# =============================================================================
# Pruning an unintentional "happy accident" in admin-fee claims.
#
# A donation to the pool counts as profit. A public claim_admin_fees() re-synced
# the tracked balances to the real ERC20 asset balanceOf, so any asset sent to
# the pool was swept into the recorded balances and booked as profit. Nothing
# was designed to read donations this way.
#
# The pool spends profit to compress its bid-ask spread and rebalance liquidity
# closer to where the market is trading, so booking a donation as profit let
# anyone hand the pool value to tighten spreads on demand. That made the side
# effect useful enough to be relied on as a feature.
#
# _claim_admin_fees() is now internal and auto-triggered, deriving fees only from
# the xcp_profit invariant counters. balanceOf never redefines the balances, so
# a donation is never counted as profit.
#
# Excerpt for discussion, not a full contract. See ../README.md (change 3).
# `# ...` marks elided lines.
# =============================================================================


# ======================== BEFORE: old tricrypto =============================
# _claim_admin_fees: https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/tricrypto/CurveCryptoSwap.vy#L397
# claim_admin_fees:  https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/tricrypto/CurveCryptoSwap.vy#L965

@internal
def _claim_admin_fees():
    A_gamma: uint256[2] = self._A_gamma()

    xcp_profit: uint256 = self.xcp_profit
    xcp_profit_a: uint256 = self.xcp_profit_a

    # Gulp here                              <-- THE PROBLEM: tracked balances are
    _coins: address[N_COINS] = coins         #   overwritten with the real ERC20 asset
    for i in range(N_COINS):                 #   balance, so any donated asset gets
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
# Internal only (no public wrapper). Fees come from the xcp_profit accounting,
# not from re-reading balanceOf. There is no balance "gulp".
# _claim_admin_fees: https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy#L1099

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
