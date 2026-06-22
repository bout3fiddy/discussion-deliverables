"""Run from this directory with:  uv run --with titanoboa --with pytest pytest -q

Shows that an ERC20 swap needs an approval, and that the send-then-call pattern
(swap_received) does the same trade with no approval at all.
"""
import os
import boa

U = 10**18
HERE = os.path.dirname(os.path.abspath(__file__))


def load(name, *args):
    return boa.load(os.path.join(HERE, name), *args)


def setup_pool():
    coin0 = load("mock_erc20.vy")
    coin1 = load("mock_erc20.vy")
    pool = load("swap_pool.vy", coin0.address, coin1.address)
    coin0.mint(pool.address, 100 * U)      # seed reserves so the pool can pay out
    coin1.mint(pool.address, 100 * U)
    pool.seed()
    return coin0, coin1, pool


def test_swap_requires_an_approval():
    coin0, coin1, pool = setup_pool()
    user = boa.env.generate_address()
    coin0.mint(user, 10 * U)

    # No approval: transferFrom inside swap() reverts.
    with boa.reverts():
        pool.swap(0, 1, 10 * U, sender=user)

    # Grant the approval, then the same swap works.
    coin0.approve(pool.address, 10 * U, sender=user)
    dy = pool.swap(0, 1, 10 * U, sender=user)
    assert dy == 10 * U
    assert coin1.balanceOf(user) == 10 * U


def test_swap_received_needs_no_approval():
    coin0, coin1, pool = setup_pool()
    user = boa.env.generate_address()
    coin0.mint(user, 10 * U)

    # The user sends coin0 straight to the pool with a plain transfer, then calls
    # swap_received. No approval is granted anywhere.
    coin0.transfer(pool.address, 10 * U, sender=user)
    assert coin0.allowance(user, pool.address) == 0

    dy = pool.swap_received(0, 1, user, sender=user)
    assert dy == 10 * U
    assert coin1.balanceOf(user) == 10 * U


def test_assets_sent_without_the_call_are_claimable_by_anyone():
    # The sharp edge of the approval-free path: a direct transfer with no
    # follow-up call leaves the assets in the pool for the next caller to claim.
    coin0, coin1, pool = setup_pool()
    alice = boa.env.generate_address()
    coin0.mint(alice, 10 * U)
    coin0.transfer(pool.address, 10 * U, sender=alice)   # alice forgets to call swap_received

    bob = boa.env.generate_address()
    dy = pool.swap_received(0, 1, bob, sender=bob)        # bob claims the surplus
    assert dy == 10 * U
    assert coin1.balanceOf(bob) == 10 * U
    assert coin1.balanceOf(alice) == 0
