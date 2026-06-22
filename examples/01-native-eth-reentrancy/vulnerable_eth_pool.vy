# @version 0.3.10
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# A deposit pool that holds native ETH. It is drainable because two things line up:
#   1. value leaves as NATIVE ETH (a low-level call that runs the recipient's code), and
#   2. the reentrancy lock is misconfigured: the two value-moving functions guard
#      with DIFFERENT keys, so neither blocks re-entry through the other.
#
# In correct, modern Vyper, @nonreentrant('a') and @nonreentrant('b') use separate
# storage slots by design. So splitting the keys here is a real developer mistake,
# and it is the same shape as the July 2023 Vyper bug, where functions that were
# meant to share one lock compiled to separate slots.

deposits: public(HashMap[address, uint256])
total_deposited: public(uint256)


@external
@payable
def deposit():
    self.deposits[msg.sender] += msg.value
    self.total_deposited += msg.value


@external
@nonreentrant('lock_main')
def withdraw():
    amount: uint256 = self.deposits[msg.sender]
    assert amount > 0, "nothing to withdraw"

    # Interaction BEFORE effect (a checks-effects-interactions violation).
    # raw_call forwards all gas and runs the recipient's code, so a contract
    # recipient can re-enter the pool right here, before the ledger is updated.
    raw_call(msg.sender, b"", value=amount)

    self.deposits[msg.sender] = 0
    self.total_deposited -= amount


@external
@nonreentrant('lock_emergency')   # different key: does NOT coordinate with withdraw()
def withdraw_to(recipient: address):
    amount: uint256 = self.deposits[msg.sender]
    assert amount > 0, "nothing to withdraw"
    raw_call(recipient, b"", value=amount)
    self.deposits[msg.sender] = 0
    self.total_deposited -= amount
