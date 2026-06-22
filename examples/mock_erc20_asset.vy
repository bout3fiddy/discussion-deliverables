# Minimal ERC20 asset for the demos. Not production code. Shared by examples 01 and 02.
# No version pragma: example 01 compiles it with Vyper 0.3.0, example 02 with 0.4.x.

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
totalSupply: public(uint256)


@external
def mint(to: address, amount: uint256):
    """
    @notice Mint `amount` to `to` (test helper; no access control).
    @param to Address to credit.
    @param amount Amount to mint.
    """
    self.balanceOf[to] += amount
    self.totalSupply += amount


@external
def approve(spender: address, amount: uint256) -> bool:
    """
    @notice Approve `spender` to move `amount` of the caller's balance.
    @param spender Address allowed to spend.
    @param amount Allowance to set.
    @return Always True.
    """
    self.allowance[msg.sender][spender] = amount
    return True


@external
def transfer(to: address, amount: uint256) -> bool:
    """
    @notice Move `amount` from the caller to `to`.
    @param to Recipient.
    @param amount Amount to transfer.
    @return Always True (reverts on insufficient balance).
    """
    self.balanceOf[msg.sender] -= amount   # reverts on insufficient balance
    self.balanceOf[to] += amount
    return True


@external
def transferFrom(sender: address, to: address, amount: uint256) -> bool:
    """
    @notice Move `amount` from `sender` to `to` using the caller's allowance.
    @param sender Address to debit.
    @param to Recipient.
    @param amount Amount to transfer.
    @return Always True (reverts on insufficient allowance or balance).
    """
    self.allowance[sender][msg.sender] -= amount   # reverts on insufficient allowance
    self.balanceOf[sender] -= amount
    self.balanceOf[to] += amount
    return True
