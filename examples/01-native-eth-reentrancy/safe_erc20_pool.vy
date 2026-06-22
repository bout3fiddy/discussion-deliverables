# @version 0.3.10
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# The same pool, with the SAME misconfigured split-key locks, but value moves as
# an ERC20 asset instead of native ETH. An ERC20 transfer moves a number in the
# asset's ledger and does not call back into the recipient, so there is no
# callback to re-enter through. The attack that drains the native-ETH pool does
# nothing here, even though the lock is just as wrong. Removing native ETH
# removes the dependency on the lock being correct.

interface ERC20:
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, to: address, amount: uint256) -> bool: nonpayable

asset: public(address)
deposits: public(HashMap[address, uint256])
total_deposited: public(uint256)


@external
def __init__(_asset: address):
    self.asset = _asset


@external
def deposit(amount: uint256):
    assert ERC20(self.asset).transferFrom(msg.sender, self, amount, default_return_value=True)
    self.deposits[msg.sender] += amount
    self.total_deposited += amount


@external
@nonreentrant('lock_main')
def withdraw():
    amount: uint256 = self.deposits[msg.sender]
    assert amount > 0, "nothing to withdraw"
    assert ERC20(self.asset).transfer(msg.sender, amount, default_return_value=True)  # no callback
    self.deposits[msg.sender] = 0
    self.total_deposited -= amount


@external
@nonreentrant('lock_emergency')   # still a different key, still wrong, still harmless here
def withdraw_to(recipient: address):
    amount: uint256 = self.deposits[msg.sender]
    assert amount > 0, "nothing to withdraw"
    assert ERC20(self.asset).transfer(recipient, amount, default_return_value=True)
    self.deposits[msg.sender] = 0
    self.total_deposited -= amount
