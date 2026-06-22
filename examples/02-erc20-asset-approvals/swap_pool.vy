# pragma version ^0.4.0
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# A minimal two-asset pool with a trivial 1:1 price (a real pool prices along a
# curve). It shows two ways to bring assets in:
#   swap()          pulls assets with transferFrom, which REQUIRES an approval.
#   swap_received() reads the surplus the caller already sent in, NO approval.
#
# `stored` is the pool's own record of its reserves, separate from the asset's
# balanceOf. The received path works by comparing the two.

interface ERC20:
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, to: address, amount: uint256) -> bool: nonpayable
    def balanceOf(account: address) -> uint256: view

assets: public(address[2])
stored: public(uint256[2])


@deploy
def __init__(_asset0: address, _asset1: address):
    """
    @notice Create a two-asset pool.
    @param _asset0 The first ERC20 asset.
    @param _asset1 The second ERC20 asset.
    """
    self.assets = [_asset0, _asset1]


@external
def seed():
    """
    @notice Record the current balances as the pool's reserves.
    @dev Test helper; a real pool sets reserves through add_liquidity.
    """
    self.stored[0] = staticcall ERC20(self.assets[0]).balanceOf(self)
    self.stored[1] = staticcall ERC20(self.assets[1]).balanceOf(self)


@internal
def _payout(j: uint256, dy: uint256, receiver: address):
    """
    @notice Send `dy` of asset j to `receiver` and update the reserve.
    @param j Index of the asset to pay out.
    @param dy Amount to pay out.
    @param receiver Address that receives asset j.
    """
    self.stored[j] -= dy
    assert extcall ERC20(self.assets[j]).transfer(receiver, dy, default_return_value=True)


@external
def swap(i: uint256, j: uint256, dx: uint256, receiver: address = msg.sender) -> uint256:
    """
    @notice Swap `dx` of asset i for asset j by pulling asset i from the caller.
    @dev transferFrom reverts unless the caller has approved the pool for `dx`.
    @param i Index of the asset to send in.
    @param j Index of the asset to receive.
    @param dx Amount of asset i to swap in.
    @param receiver Address that receives asset j.
    @return Amount of asset j sent out.
    """
    assert i != j and i < 2 and j < 2

    # Pull `dx` from the caller. This reverts unless the caller has approved the
    # pool to move at least `dx` of asset i.
    assert extcall ERC20(self.assets[i]).transferFrom(msg.sender, self, dx, default_return_value=True)

    self.stored[i] += dx
    dy: uint256 = dx                       # trivial 1:1 price
    self._payout(j, dy, receiver)

    return dy


@external
def swap_received(i: uint256, j: uint256, receiver: address = msg.sender) -> uint256:
    """
    @notice Swap the asset i already sent to the pool, with no approval.
    @dev Reads dx as the surplus of balanceOf over the recorded reserve, so the
         caller must transfer asset i in and call this in the same transaction.
    @param i Index of the asset sent in.
    @param j Index of the asset to receive.
    @param receiver Address that receives asset j.
    @return Amount of asset j sent out.
    """
    assert i != j and i < 2 and j < 2

    # The caller already transferred asset i directly to this pool. Detect it as
    # the surplus over the recorded reserve. No approval is involved.
    bal: uint256 = staticcall ERC20(self.assets[i]).balanceOf(self)
    dx: uint256 = bal - self.stored[i]

    assert dx > 0, "no assets received"

    self.stored[i] += dx
    dy: uint256 = dx
    self._payout(j, dy, receiver)

    return dy
