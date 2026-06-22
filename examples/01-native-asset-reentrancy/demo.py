"""Run from this directory:  uv run --with titanoboa demo.py

One pool (pool.vy) deployed three ways, isolating one variable each time:
  - native asset, interaction before effect -> drained,
  - ERC20 asset, same lock -> safe, because the transfer has no callback,
  - native asset, effect before interaction (CEI) -> safe, the attack reverts.
"""
import os

import boa

UNIT = 10**18
ZERO = "0x0000000000000000000000000000000000000000"
HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, *args):
    return boa.load(os.path.join(HERE, name), *args)


def native_asset_pool_is_drained():
    print("== native-asset pool (interaction before effect) ==")
    pool = load("pool.vy", True, False, ZERO)

    victim = boa.env.generate_address()
    boa.env.set_balance(victim, 5 * UNIT)
    pool.deposit(value=5 * UNIT, sender=victim)
    print(f"  honest depositor puts in 5 units; pool holds {boa.env.get_balance(pool.address) // UNIT} units")

    attacker = load("attacker.vy", pool.address, ZERO)
    eoa = boa.env.generate_address()
    boa.env.set_balance(eoa, 1 * UNIT)
    print("  attacker deposits 1 unit and calls withdraw() ...")
    attacker.attack(value=1 * UNIT, sender=eoa)

    drained = boa.env.get_balance(attacker.address)
    pool_left = boa.env.get_balance(pool.address)
    print(f"  attacker re-entered through the native-asset callback: {attacker.reentered()}")
    print(f"  attacker now holds {drained // UNIT} units for a 1 unit deposit")
    print(f"  pool holds {pool_left // UNIT} units but owes the depositor {pool.deposits(victim) // UNIT}: insolvent")
    assert attacker.reentered() is True
    assert drained == 2 * UNIT and pool_left == 4 * UNIT
    print("  -> drained, as expected\n")


def erc20_asset_pool_is_safe():
    print("== ERC20 asset pool (same lock, no callback) ==")
    asset = load("../mock_erc20_asset.vy")
    pool = load("pool.vy", False, False, asset.address)

    victim = boa.env.generate_address()
    asset.mint(victim, 5 * UNIT)
    asset.approve(pool.address, 5 * UNIT, sender=victim)
    pool.deposit(5 * UNIT, sender=victim)

    attacker = load("attacker.vy", pool.address, asset.address)
    asset.mint(attacker.address, 1 * UNIT)
    print("  attacker deposits 1 unit and runs the same attack ...")
    attacker.attack(1 * UNIT)

    print(f"  attacker re-entered: {attacker.reentered()} (no callback to re-enter through)")
    print(f"  attacker holds {asset.balanceOf(attacker.address) // UNIT} unit; pool holds {asset.balanceOf(pool.address) // UNIT} units: solvent")
    assert attacker.reentered() is False
    assert asset.balanceOf(attacker.address) == 1 * UNIT and asset.balanceOf(pool.address) == 5 * UNIT
    print("  -> safe, as expected\n")


def cei_pool_defeats_the_attack():
    print("== native-asset pool with checks-effects-interactions (effect first) ==")
    pool = load("pool.vy", True, True, ZERO)

    victim = boa.env.generate_address()
    boa.env.set_balance(victim, 5 * UNIT)
    pool.deposit(value=5 * UNIT, sender=victim)

    # an honest user can still deposit and withdraw normally: CEI keeps the happy path
    alice = boa.env.generate_address()
    boa.env.set_balance(alice, 3 * UNIT)
    pool.deposit(value=3 * UNIT, sender=alice)
    pool.withdraw(sender=alice)
    print(f"  honest user withdrew normally and holds {boa.env.get_balance(alice) // UNIT} units again")
    assert boa.env.get_balance(alice) == 3 * UNIT

    attacker = load("attacker.vy", pool.address, ZERO)
    eoa = boa.env.generate_address()
    boa.env.set_balance(eoa, 1 * UNIT)
    print("  attacker runs the same re-entrancy ...")
    with boa.reverts():
        attacker.attack(value=1 * UNIT, sender=eoa)
    print(f"  the re-entrant withdraw_to() reads a zeroed balance and reverts; pool still holds {boa.env.get_balance(pool.address) // UNIT} units")
    assert boa.env.get_balance(pool.address) == 5 * UNIT
    print("  -> CEI defeats the attack even with the broken lock and the native asset\n")


def main():
    native_asset_pool_is_drained()
    erc20_asset_pool_is_safe()
    cei_pool_defeats_the_attack()
    print("all three scenarios behaved as expected.")


if __name__ == "__main__":
    main()
