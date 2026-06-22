# @version 0.3.10
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

coins: public(address[2])
stored: public(uint256[2])


@external
def __init__(_coin0: address, _coin1: address):
    self.coins = [_coin0, _coin1]


@external
def seed():
    # record current balances as reserves (test helper; a real pool uses add_liquidity)
    self.stored[0] = ERC20(self.coins[0]).balanceOf(self)
    self.stored[1] = ERC20(self.coins[1]).balanceOf(self)


@internal
def _payout(j: uint256, dy: uint256, receiver: address):
    self.stored[j] -= dy
    assert ERC20(self.coins[j]).transfer(receiver, dy, default_return_value=True)


@external
def swap(i: uint256, j: uint256, dx: uint256, receiver: address = msg.sender) -> uint256:
    assert i != j and i < 2 and j < 2
    # Pull `dx` from the caller. This reverts unless the caller has approved the
    # pool to move at least `dx` of coin i.
    assert ERC20(self.coins[i]).transferFrom(msg.sender, self, dx, default_return_value=True)
    self.stored[i] += dx
    dy: uint256 = dx                       # trivial 1:1 price
    self._payout(j, dy, receiver)
    return dy


@external
def swap_received(i: uint256, j: uint256, receiver: address = msg.sender) -> uint256:
    assert i != j and i < 2 and j < 2
    # The caller already transferred coin i directly to this pool. Detect it as
    # the surplus over the recorded reserve. No approval is involved.
    dx: uint256 = ERC20(self.coins[i]).balanceOf(self) - self.stored[i]
    assert dx > 0, "no assets received"
    self.stored[i] += dx
    dy: uint256 = dx
    self._payout(j, dy, receiver)
    return dy
