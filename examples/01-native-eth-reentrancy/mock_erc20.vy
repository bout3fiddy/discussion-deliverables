# @version 0.3.10
# Minimal ERC20 for the tests. Not production code.

balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
totalSupply: public(uint256)


@external
def mint(to: address, amount: uint256):
    self.balanceOf[to] += amount
    self.totalSupply += amount


@external
def approve(spender: address, amount: uint256) -> bool:
    self.allowance[msg.sender][spender] = amount
    return True


@external
def transfer(to: address, amount: uint256) -> bool:
    self.balanceOf[msg.sender] -= amount   # reverts on insufficient balance
    self.balanceOf[to] += amount
    return True


@external
def transferFrom(sender: address, to: address, amount: uint256) -> bool:
    self.allowance[sender][msg.sender] -= amount   # reverts on insufficient allowance
    self.balanceOf[sender] -= amount
    self.balanceOf[to] += amount
    return True
