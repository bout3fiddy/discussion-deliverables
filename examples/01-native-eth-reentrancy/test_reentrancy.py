"""Run from this directory with:  uv run --with titanoboa --with pytest pytest -q

Demonstrates the same attack against two pools:
  - the native-ETH pool with a misconfigured lock gets drained,
  - the ERC20 pool with the SAME misconfigured lock does not, because there is
    no callback to re-enter through.
"""
import os
import boa

ETH = 10**18
HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, *args):
    return boa.load(os.path.join(HERE, name), *args)


def test_native_eth_pool_is_drained():
    pool = load("vulnerable_eth_pool.vy")

    # an honest depositor puts in 5 ETH
    victim = boa.env.generate_address()
    boa.env.set_balance(victim, 5 * ETH)
    pool.deposit(value=5 * ETH, sender=victim)
    assert boa.env.get_balance(pool.address) == 5 * ETH

    # the attacker deposits 1 ETH, then runs the re-entrancy
    attacker = load("attacker.vy", pool.address)
    eoa = boa.env.generate_address()
    boa.env.set_balance(eoa, 1 * ETH)
    attacker.attack(value=1 * ETH, sender=eoa)

    assert attacker.reentered() is True               # the ETH callback fired and re-entered
    assert boa.env.get_balance(attacker.address) == 2 * ETH   # 1 deposited, 2 paid out: stole 1
    assert boa.env.get_balance(pool.address) == 4 * ETH       # pool paid out 2, holds 4
    # the honest depositor is still owed 5 ETH but the pool holds only 4: insolvent
    assert boa.env.get_balance(pool.address) < pool.deposits(victim)


def test_erc20_pool_is_safe():
    asset = load("mock_erc20.vy")
    pool = load("safe_erc20_pool.vy", asset.address)

    # honest depositor: 5 units
    victim = boa.env.generate_address()
    asset.mint(victim, 5 * ETH)
    asset.approve(pool.address, 5 * ETH, sender=victim)
    pool.deposit(5 * ETH, sender=victim)
    assert asset.balanceOf(pool.address) == 5 * ETH

    # the same attack, now against the ERC20 pool
    attacker = load("erc20_attacker.vy", pool.address, asset.address)
    asset.mint(attacker.address, 1 * ETH)
    attacker.attack(1 * ETH)

    assert attacker.reentered() is False              # no callback, so no re-entry
    assert asset.balanceOf(attacker.address) == 1 * ETH   # got back exactly the deposit
    assert asset.balanceOf(pool.address) == 5 * ETH       # honest funds intact: solvent
