# @version 0.3.0
# TEACHING EXAMPLE. Do not deploy. See README.md.
#
# One pool implementation, demonstrated three ways:
#
#   1. NATIVE=True,  CEI=False  -> drainable (the bug)
#   2. NATIVE=False, CEI=False  -> safe: an ERC20 asset transfer has no callback
#   3. NATIVE=True,  CEI=True   -> safe: the effect is committed before the payout
#
# withdraw() and withdraw_to() share ONE @nonreentrant('lock') key, which is the
# correct way to write the guard. Vyper 0.3.0 miscompiles it (GHSA-5824-cm3x-3c38):
# two functions that share a key are given SEPARATE storage slots, so a call already
# inside withdraw() is not blocked from re-entering withdraw_to().

interface ERC20:
    def transfer(to: address, amount: uint256) -> bool: nonpayable
    def transferFrom(sender: address, to: address, amount: uint256) -> bool: nonpayable

NATIVE: bool        # pay out the native asset (callback) or an ERC20 asset (no callback)
CEI: bool           # commit the effect (zero the ledger) before the payout
ASSET: address      # the ERC20 asset, or empty for the native-asset pool

deposits: public(HashMap[address, uint256])


@internal
def _send(recipient: address, amount: uint256):
    """
    @notice Send `amount` to `recipient` in the pool's payout medium.
    @dev The native-asset path uses raw_call, which runs the recipient's code; the
         ERC20 asset path uses transfer, which never calls back into the pool.
    @param recipient Address that receives the payout.
    @param amount Amount to send.
    """
    if self.NATIVE:
        raw_call(recipient, b"", value=amount)   # runs the recipient's code: a callback
    else:
        assert ERC20(self.ASSET).transfer(recipient, amount)   # no callback


@internal
def _pay(account: address, recipient: address):
    """
    @notice Pay `account`'s balance to `recipient` and zero the ledger.
    @dev With CEI the ledger is zeroed before the payout; otherwise the payout (an
         external call) happens first, which is the re-entrancy window.
    @param account Address whose ledger balance is spent.
    @param recipient Address that receives the payout.
    """
    amount: uint256 = self.deposits[account]
    assert amount > 0, "nothing to withdraw"
    if self.CEI:
        self.deposits[account] = 0      # effect before interaction
        self._send(recipient, amount)
    else:
        self._send(recipient, amount)   # interaction before effect (the bug)
        self.deposits[account] = 0


@external
def __init__(_native: bool, _cei: bool, _asset: address):
    """
    @notice Configure which variant of the pool to deploy.
    @param _native True to pay out the native asset, False to pay out an ERC20 asset.
    @param _cei True to zero the ledger before paying out (checks-effects-interactions).
    @param _asset The ERC20 asset, or the empty address for the native-asset pool.
    """
    self.NATIVE = _native
    self.CEI = _cei
    self.ASSET = _asset


@external
@payable
def deposit(amount: uint256 = 0):
    """
    @notice Deposit into the pool, crediting the caller's balance.
    @dev For the native-asset pool the credit is msg.value; for the ERC20 asset
         pool it is `amount`, pulled with transferFrom (needs a prior approval).
    @param amount Amount to pull for the ERC20 asset pool; ignored when native.
    """
    if self.NATIVE:
        self.deposits[msg.sender] += msg.value
    else:
        assert ERC20(self.ASSET).transferFrom(msg.sender, self, amount)
        self.deposits[msg.sender] += amount


@external
@nonreentrant('lock')
def withdraw():
    """
    @notice Withdraw the caller's whole balance to the caller.
    @dev Guards with the shared 'lock' reentrancy key; the payout happens in _pay.
    """
    self._pay(msg.sender, msg.sender)


@external
@nonreentrant('lock')
def withdraw_to(recipient: address):
    """
    @notice Withdraw the caller's whole balance to another recipient.
    @dev Guards with the SAME 'lock' key as withdraw(). Written correctly, this
         blocks re-entry from withdraw() into here; Vyper 0.3.0 miscompiles the
         shared key to a separate slot, so the block does not happen.
    @param recipient Address that receives the payout.
    """
    self._pay(msg.sender, recipient)
