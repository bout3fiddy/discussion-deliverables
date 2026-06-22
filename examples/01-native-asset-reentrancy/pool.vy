# pragma version ^0.4.0
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# Pool implementaions demos three different variations:
#   NATIVE=True,  CEI=False  -> drainable (the bug)
#   NATIVE=False, CEI=False  -> safe: an ERC20 asset transfer has no callback
#   NATIVE=True,  CEI=True   -> safe: the effect is committed before the payout
#
# The reentrancy bug is present in all three: withdraw() and withdraw_to() guard
# with two SEPARATE locks (locked_main, locked_emergency) instead of one shared
# lock, so a call already inside withdraw() is not blocked from re-entering
# withdraw_to(). Only the payout medium and the ordering change between deploys.

interface ERC20:
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, to: address, amount: uint256) -> bool: nonpayable

NATIVE: immutable(bool)     # pay out the native asset (callback) or an ERC20 asset (no callback)
CEI: immutable(bool)        # commit the effect (zero the ledger) before the payout
ASSET: immutable(address)   # the ERC20 asset, or empty for the native-asset pool

deposits: public(HashMap[address, uint256])

locked_main: bool
locked_emergency: bool


@deploy
def __init__(_native: bool, _cei: bool, _asset: address):
    """
    @notice Configure which variant of the pool to deploy.
    @param _native True to pay out the native asset, False to pay out an ERC20 asset.
    @param _cei True to zero the ledger before paying out (checks-effects-interactions).
    @param _asset The ERC20 asset, or the empty address for the native-asset pool.
    """
    NATIVE = _native
    CEI = _cei
    ASSET = _asset


@external
@payable
def deposit(amount: uint256 = 0):
    """
    @notice Deposit into the pool, crediting the caller's balance.
    @dev For the native-asset pool the credit is msg.value; for the ERC20 asset
         pool it is `amount`, pulled with transferFrom (needs a prior approval).
    @param amount Amount to pull for the ERC20 asset pool; ignored when native.
    """
    if NATIVE:
        self.deposits[msg.sender] += msg.value
    else:
        assert extcall ERC20(ASSET).transferFrom(msg.sender, self, amount, default_return_value=True)
        self.deposits[msg.sender] += amount


@external
def withdraw():
    """
    @notice Withdraw the caller's whole balance to the caller.
    @dev Guards with locked_main; the payout happens inside _pay.
    """
    assert not self.locked_main, "reentrant"
    self.locked_main = True
    self._pay(msg.sender)
    self.locked_main = False


@external
def withdraw_to(recipient: address):
    """
    @notice Withdraw the caller's whole balance to another recipient.
    @dev Guards with locked_emergency, a DIFFERENT lock from withdraw(), so a call
         already inside withdraw() is not blocked from re-entering here.
    @param recipient Address that receives the payout.
    """
    assert not self.locked_emergency, "reentrant"
    self.locked_emergency = True
    self._pay(recipient)
    self.locked_emergency = False


@internal
def _pay(recipient: address):
    """
    @notice Pay the caller's balance to `recipient` and zero the ledger.
    @dev With CEI the ledger is zeroed before the payout; otherwise the payout (an
         external call) happens first, which is the re-entrancy window.
    @param recipient Address that receives the payout.
    """
    amount: uint256 = self.deposits[msg.sender]
    assert amount > 0, "nothing to withdraw"
    if CEI:
        self.deposits[msg.sender] = 0   # effect before interaction
        self._send(recipient, amount)
    else:
        self._send(recipient, amount)   # interaction before effect (the bug)
        self.deposits[msg.sender] = 0


@internal
def _send(recipient: address, amount: uint256):
    """
    @notice Send `amount` to `recipient` in the pool's payout medium.
    @dev The native-asset path uses raw_call, which runs the recipient's code; the
         ERC20 asset path uses transfer, which never calls back into the pool.
    @param recipient Address that receives the payout.
    @param amount Amount to send.
    """
    if NATIVE:
        raw_call(recipient, b"", value=amount)   # runs the recipient's code: a callback
    else:
        assert extcall ERC20(ASSET).transfer(recipient, amount, default_return_value=True)   # no callback
