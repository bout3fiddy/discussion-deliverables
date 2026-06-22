"""Run from this directory:  uv run --with titanoboa demo.py

Shows that an ERC20 asset swap needs an approval, and that the send-then-call
pattern (swap_received) does the same trade with no approval at all.
"""
import os

import boa

UNIT = 10**18
HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, *args):
    return boa.load(os.path.join(HERE, name), *args)


def setup_pool():
    asset0 = load("../mock_erc20_asset.vy")
    asset1 = load("../mock_erc20_asset.vy")
    pool = load("swap_pool.vy", asset0.address, asset1.address)
    asset0.mint(pool.address, 100 * UNIT)      # seed reserves so the pool can pay out
    asset1.mint(pool.address, 100 * UNIT)
    pool.seed()
    return asset0, asset1, pool


def swap_requires_an_approval():
    print("== swap() pulls with transferFrom, so it needs an approval ==")
    asset0, asset1, pool = setup_pool()
    user = boa.env.generate_address()
    asset0.mint(user, 10 * UNIT)

    with boa.reverts():
        pool.swap(0, 1, 10 * UNIT, sender=user)
    print("  swap without an approval reverted, as expected")

    asset0.approve(pool.address, 10 * UNIT, sender=user)
    dy = pool.swap(0, 1, 10 * UNIT, sender=user)
    print(f"  after approve, swap returned {dy // UNIT} and the user received {asset1.balanceOf(user) // UNIT} of asset1")
    assert dy == 10 * UNIT
    assert asset1.balanceOf(user) == 10 * UNIT
    print()


def swap_received_needs_no_approval():
    print("== swap_received() reads the surplus, so it needs no approval ==")
    asset0, asset1, pool = setup_pool()
    user = boa.env.generate_address()
    asset0.mint(user, 10 * UNIT)

    asset0.transfer(pool.address, 10 * UNIT, sender=user)
    print(f"  user transferred 10 of asset0 directly; allowance is {asset0.allowance(user, pool.address)}")
    dy = pool.swap_received(0, 1, user, sender=user)
    print(f"  swap_received returned {dy // UNIT} and the user received {asset1.balanceOf(user) // UNIT} of asset1")
    assert dy == 10 * UNIT
    assert asset1.balanceOf(user) == 10 * UNIT
    print()


def assets_sent_without_the_call_are_claimable_by_anyone():
    print("== the catch: a transfer with no follow-up call is claimable by anyone ==")
    asset0, asset1, pool = setup_pool()
    alice = boa.env.generate_address()
    asset0.mint(alice, 10 * UNIT)
    asset0.transfer(pool.address, 10 * UNIT, sender=alice)
    print("  alice transferred 10 of asset0 but forgot to call swap_received")

    bob = boa.env.generate_address()
    dy = pool.swap_received(0, 1, bob, sender=bob)
    print(f"  bob called swap_received and received {asset1.balanceOf(bob) // UNIT} of asset1; alice got {asset1.balanceOf(alice) // UNIT}")
    assert dy == 10 * UNIT
    assert asset1.balanceOf(bob) == 10 * UNIT
    assert asset1.balanceOf(alice) == 0
    print()


def main():
    swap_requires_an_approval()
    swap_received_needs_no_approval()
    assets_sent_without_the_call_are_claimable_by_anyone()
    print("all three behaved as expected.")


if __name__ == "__main__":
    main()
