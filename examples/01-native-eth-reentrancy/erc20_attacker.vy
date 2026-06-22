# @version 0.3.10
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# The same attacker logic as attacker.vy, pointed at the ERC20 pool. The re-entry
# in __default__ is never reached, because an ERC20 transfer does not call the
# recipient. So `reentered` stays False and no extra funds are taken.

interface Pool:
    def deposit(amount: uint256): nonpayable
    def withdraw(): nonpayable
    def withdraw_to(recipient: address): nonpayable

interface ERC20:
    def approve(spender: address, amount: uint256) -> bool: nonpayable

pool: public(address)
asset: public(address)
reentered: public(bool)


@external
def __init__(_pool: address, _asset: address):
    self.pool = _pool
    self.asset = _asset


@external
def attack(amount: uint256):
    ERC20(self.asset).approve(self.pool, amount)
    Pool(self.pool).deposit(amount)
    Pool(self.pool).withdraw()


@external
@payable
def __default__():
    if not self.reentered:
        self.reentered = True
        Pool(self.pool).withdraw_to(self)
