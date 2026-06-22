# Three security changes to Curve's core AMM contracts

Three security changes to Curve's core smart contracts, the `stableswap-ng` and `tricrypto-ng` liquidity pools that hold financial assets and let anyone swap one asset for another against them. The changes followed the exploited Vyper compiler vulnerability in July 2023.

## Primer on AMMs

Traditional exchanges run order books where buyers post bids, sellers post asks, and a matching engine pairs. Orderbooks are a data-intensive infrastructure that requires buyers and sellers to be present constantly re-quoting and reactive to the market, at an extremely high throughput (some participants require nanosecond level execution of their orders and the ability to cancel orders quickly). On a distributed ledger such as public blockchains, this is not possible. The ledger is distributed and every write to the global shared state is extremely expensive: every step costs measurable computational units called GAS. 

In such conditions, markets can be replaced by immutable programs (called smart contracts) that exist on the distributed ledger. These special class of immutable smart contracts are called Automatic Market Makers (AMMs), which replaces an orderbook's matching engine with a suite of mathematical formulae that manage asset flow within the market, and an accompanying mathematical invariant that must hold true during an exchange of assets within the market. 

The AMM smart contract holds a reserve of assets (henceforth called a liquidity pool) and prices each trade from how much of each asset the pool currently holds. That pricing function, governed by the invariant, is called a bonding curve. Liquidity providers deposit assets and receive shares they later redeem; traders swap against the pool, and the bonding curve prices each swap based on the local state of the smart contract.

## Summary

In [July 2023 a bug in the Vyper compiler](https://hackmd.io/@vyperlang/HJUgNMhs2), introduced in a multi-year (2018-2023) refactor of the Vyper compiler, caused a mutex mechanism to malfunction, therefore allowing external callers to 'reenter' the smart contract in the midst of an execution and exploit stale state to cause financial losses. The result was a lost of about $70M and an exodus of $ 1.5B from the client's smart contracts (despite the fact that they were not affected).

The gist of the attack is as follows:

1. Each mutex can assign its own key, and therefore decorating a function with a mutex and a shared key e.g. `@nonreentrant('shared_key_A')` would 'lock' re-entry for all functions that shared the same key. 
2. The compiler bug introduced caused each shared key to be unique, despite the source code showing different shared key names, therefore disabling cross-function mutex locks. 
3. Consequently, if the decorated functions had the possibility to hand over execution context to an external caller, the external caller would be able to re-enter in-between a transaction, and exploit a stale state (if there was profit to be made or DoS to be caused).

No smart contract audit had looked at the compiler, and the compiler itself had not been scrutinised by external auditors (lack of funding, people, and therefore coordination). Beyond non-technical constraints, the leak also required all of the following conditions to be true:

1. a malfunctioning mutex lock,
2. the smart contract handing over execution context to an external caller, and
3. stale smart contract state existing before execution context is handed over to an external caller.

Following the hack, several post-hack endeavours were put into motion. Vyper went from being not audited to being the most audited smart contract language, and I re-designed all Curve AMM smart contracts with lessons learnt from the incident. This code repository contains, of the many security-related changes introduced, three changes that remain relevant to this day.

---

## The three changes

1. Approval-free swaps via `exchange_received` ([code](./code/01-optimistic-transfers.vy)), therefore reducing 
   exposure to an exploited smart contract that has the authorisation to spend assets on behalf of the owner.
2. Disallowing handing over execution context to external callers ([code](./code/02-no-native-eth.vy)).
3. Removing unintentional 'happy accident' features ([code](./code/03-admin-fees-internal-and-no-gulp.vy)), therefore
   paving the way to approach it more seriously.

### 1. Approval-free swaps via optimistic transfers (`exchange_received`)

In traditional exchange smart-contract designs, the asset-flow transactions are always proceeded by an 'approval' transaction, where the owner of the assets gives permission to the smart contract to spend a certain limit of the user's funds for exchange-related operations. This is now an antiquated design, since superceeded by newer spending-approval approaches. The general risk that approvals carry are:

1. Users generally have a habit of giving smart contracts 'infinite approval', i.e. the authorisation to spend all of their assets (triggered by a user transaction).
2. This leaves open cases where exploited/vulnerable smart contracts expose user funds to the danger of being stolen by hackers.
3. This risk prevents accredited investor parties and regulated entities from safely interacting with the smart contract.

To counteract this issue, a secondary exchange entry point was introduced which did not require approval transactions at all. This secondary entrypoint utilised a novel approach where the smart contract would read 'excess' balances as amounts of the asset to be exchanged, instead of pulling pre-approved assets from the user's balances. The 'excess' balances would arise from the user 'optimistically transferring' funds to the smart contract and immediately calling the public exchange method within the same transaction.

An added advantage of a 'transfer-then-exchange' flow is that it allowed for a GAS optimisation where an aggregator chaining multiple swaps could avoid redundant transfers where cross-contract transactions were involved: initially, an exchange involving markets A and B would require a complex transaction flow: user -> exchange contract -> market A -> exchange contract -> market B -> user. With this new approach the transaction flow becomes user -> exchange contract -> market A -> market B -> user. That one additional transfer is a significant optimisation as it involves removing memory updates, and distributed ledgers price memory updates the highest of all opcodes.

So, the approach not only strengthened security for users, it also unveiled a hidden optimisation that made the AMM contracts more competitive in the open markets. And AMM contracts benefit heavily from hyper-optimised code.

Source: [`CurveStableSwapNG.vy#L358`](https://github.com/curvefi/stableswap-ng/blob/2abe778f40206a6c0fd108a0a53ad3266cbedeee/contracts/main/CurveStableSwapNG.vy#L358).

### 2. Disallowing handing over execution context to external callers

Earlier designs allowed for handing over execution context to external callers for transactions involving specific asset types. These asset types did not require an approval transaction and in general had cheaper transfer costs. The older contracts exploited these characteristics to optimise exchange costs. But the same optimisation also leaves open an attack vector.

These special transactions always call, for whatever reason, the receiver contract's hidden fallback `__default__()` method as a callback after receiving the assets. Which means that if, in the middle of a transaction execution, the sender smart contract invokes a transfer to a malicious smart contract, and the sender smart contract has a vulnerability in the mutex lock, then the malicious receiver smart contract's `__default__()` method containing malicious payload could infiltrate/re-enter the sender smart contract in the middle of a transaction. If the sender smart contract's state was stale, e.g. the sender smart contract initiated a transfer before book-keeping the exchange, the malicious smart contract could re-enter the contract knowing that the sender has not registered the transfer yet, and therefore extract more assets than what it gives in (therefore: breaking the invariant of the exchange's mathematical functions).

This was in fact the very same callback feature (a feature present in special kinds of blockchain implementation called the Ethereum Virtual Machine, or EVM), that the exploiters eventually utilised to steal assets from the exchange on July 2023. 

The gist here is: every point where a contract hands execution to code it does not control is a re-entry opportunity, and increases the chances that one guard failure leads to catastrophic losses. Fewer/No handoffs reduce that attack vector, but also: implementing a new book-keeping approach where the local state is committed before an execution context handoff is initiated also ensures this exploit is not profitable even if the exploiter somehow finds a way to re-enter.

The primary tradeoff made here was that we gave up the optimisation in favor of security, and chose to lobby for deeper security changes in the underlying execution platform itself, for instance by designing and lobbying for the [PAY opcode into the EVM](https://eips.ethereum.org/EIPS/eip-5920) which would allow for the transfer of these special assets without handing over execution context.

Source: [`CurveTricryptoOptimized.vy`](https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy).

### 3. Internal admin fees, no gulp

The old public `claim_admin_fees()` re-read the raw asset balances (the literal `# Gulp here` block), overwrote the tracked ledger with `balanceOf`, recomputed the invariant `D`, and so counted any assets donated to the pool as claimable profit. The new `_claim_admin_fees` is internal only and derives fees from `xcp_profit`, the pool's own running tally of fee profit, which moves only on real swap and deposit fees. A donated asset never turns into profit.

The principle: a side effect must not become load-bearing, and a contract should act only on state it produced on purpose. Reading profit from a raw balance is the same shape as the hack, acting on state the contract never authored. Deposits are now measured as deltas, and donations are refused: `assert dx >= _dx  # dev: user didn't give us coins`.

The nuance, because the gulp was used on purpose. A sophisticated client donated assets to rebalance: the gulp nudged the pool's `price_scale` (its on-chain record of the current price between the pool's assets) toward the market price. "Donate to rebalance" was a real lever, and removing it cost that client something. It is still the right call. The lever depended on an implementation side effect, anyone could pull it through the permissionless claim, and the legitimate intent already has sanctioned interfaces in `add_liquidity` and `exchange`. Landing the change safely meant reaching that client directly.

What an auditor broke: ChainSecurity CS-TRICRYPTO-NG-004, "First Depositor Can Manipulate the Share Value to Steal Future Deposits", through "a direct transfer to the pool followed by calling `claim_admin_fees()`". That is the gulp, exploited. Internal-only claiming plus `xcp_profit`-based fees remove the lever.

Source: old [`CurveCryptoSwap.vy#L397`](https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/tricrypto/CurveCryptoSwap.vy#L397) and new [`CurveTricryptoOptimized.vy#L1099`](https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy#L1099).

One move runs through all three: take a guarantee the old design assumed, and make the contract enforce it by construction, with less standing trust, fewer callbacks, and explicit accounting.

## How correctness is established

### Testing

The contracts are Vyper and the whole test suite is Python, so it checks economic behaviour rather than syntax. [titanoboa](https://github.com/vyperlang/titanoboa) compiles and runs the real contracts in an in-process EVM and exposes each function as a Python method. The core is stateful, property-based fuzzing. A hypothesis `RuleBasedStateMachine` sequences random swaps, deposits, withdrawals, and ramps (gradual changes to the pool's `A` and `gamma` parameters), re-checking the economic invariants after every step:

1. balances reconcile three ways. The stored `self.balances`, the on-chain `balanceOf`, and an independent Python mirror all agree.
2. `virtual_price` and `xcp_profit` only ever rise, so fees accrue to depositors.
3. LP supply stays exact, with no phantom shares minted or burned.
4. a donation cannot be extracted.

Around that sit differential testing against an independent Python model of the curve math (two implementations that agree are far stronger evidence than one asserted alone), a combinatorial matrix that runs every feature across `{basic, meta}` pools by `{plain, oracle, rebasing}` assets by decimal combinations, and a small amount of mainnet-fork integration. This net is what makes an aggressive security change safe to land: the fuzzer does not care which feature moved, it keeps proving the economics hold.

### External audits

Several independent firms reviewed these exact mechanisms and found real, exploitable edge cases. External review pays off because auditors are paid adversaries with different blind spots. The reports are public, so an integrator reads the reasoning behind a change.

Documentation as a software artifact. The technical docs at [docs.curve.finance](https://docs.curve.finance) are a MkDocs Material project, 180 Markdown files, versioned in Git, gated in CI by a `lychee` link checker and the `Vale` prose linter against the Google and GitHub style guides, and deployed to Vercel from `master`. Every external function gets the same reference from one shared template: the full Vyper signature, a prose description, returns and emitted events, a parameter table, a collapsible tab of annotated source, and a runnable example. The whitepaper math renders in-page and links to the exact function that implements it. The contracts are immutable, so the docs were how every behaviour change reached the people who build on the pools: an integrator learns the new behaviour from the reference, since the bytecode cannot be patched and is rarely read. The site started as a private `curve-mkdocs` repo, then opened to outside contributors. The lead maintainer (`mo`, over 92% of around 1,950 commits) was hired, mentored, and carried it for years, so the docs do not rest on one person either.

### Beyond the code

Several of these changes are safe only when integrators build their transactions correctly, which the contract cannot enforce. The work was done once the ecosystem knew how to adopt the change without losing funds, well after the branch compiled and the tests passed. That meant:

1. teaching the routers that chain pools together for the best price (1inch, CowSwap, Paraswap, Curve's own router) the push-then-call flow for `exchange_received`, and to wrap and unwrap WETH themselves once native ETH was gone.
2. reaching arbitrageurs, who profit by evening out price differences between markets and are ordinary expected users, and MEV searchers, who build custom transactions to capture on-chain profit. The `exchange_received` NatSpec names dex aggregators and arbitrageurs as its audience, and searchers are the same kind of approval-free power user.

Shipping a sharper, cheaper, safer primitive carries an obligation to teach people how to hold it.

## Engineering lessons

0. Know the platform that runs the code. The source states the logic; the platform under it, the hardware, the virtual machine, the compiler, is what executes, and it owns both behaviour and speed. The runnable [branch-prediction example](./examples/03-branch-prediction/) shows the speed side: one loop runs faster on sorted input because the CPU's branch predictor handles it better.
1. Verify the compiled output. The July 2023 bug was correct Vyper compiled to wrong bytecode, and reading the source line by line would never have found it. This is why the tests compile and run the real contracts and check them against an independent reference model, instead of trusting the source text.
2. Treat happy accidents as bugs. The gulp let a side effect become a load-bearing feature that nobody designed. An unintended feature is a liability until it is rebuilt on purpose, through an interface designed for it.
3. A bug is a coordination failure. No single mistake shipped the compiler bug: complacent users, a maintainer who was the only person on the compiler, and no process auditing the compiler itself all lined up. Resilience is a property of process, so the fixes were structural, more reviewers and independent audits and no single point of failure.
4. Apply security effort where the consequences are. Rigor should match what happens when the code is wrong. A throwaway script can carry a bug; an immutable contract holding deposits cannot. One cheap practice rules out a whole class of fault: checks-effects-interactions, where internal records update before any external call, so a callback finds finalized state.
5. Every near-duplicate is a liability. Copied logic drifts and multiplies the surface to verify. The redesign collapsed 21 near-duplicate stableswap implementations into 2, with the configuration as runtime parameters, which made audits cheaper and left one source of truth.

## Deposited funds

Instead of asserting a number, [`code/liquidity/fetch-ng-tvl.sh`](./code/liquidity/fetch-ng-tvl.sh) measures the value live from the public Curve API:

| Registry | TVL (USD) | Active pools |
|----------|----------:|-------------:|
| Stableswap-NG | ~$793.7M | 987 |
| Twocrypto-NG | ~$277.6M | 361 |
| Tricrypto-NG | ~$30.2M | 131 |
| Total | ≈ $1.10 B | 1,479 |

Snapshot 2026-06-19. TVL (total value locked, the US-dollar value of assets deposited in the pools) moves with prices and deposits. The methodology and the no-double-counting details are in [code/liquidity/README.md](./code/liquidity/README.md).

## Where to start

The READMEs and the short excerpts hold everything a reader needs.

1. This README, for the whole story.
2. The three excerpts in [`code/`](./code/), short annotated quotes with headers citing the exact source file, commit, and lines. A good order: [`01-optimistic-transfers.vy`](./code/01-optimistic-transfers.vy) for the cleanest security-and-gas win, then [`03-admin-fees-internal-and-no-gulp.vy`](./code/03-admin-fees-internal-and-no-gulp.vy) for the most design judgement, then [`02-no-native-eth.vy`](./code/02-no-native-eth.vy) for the 121-line deletion.
3. The runnable demonstrations in [`examples/`](./examples/), each executable in seconds; the first two use the same titanoboa stack as the real pools.
4. [`code/liquidity/`](./code/liquidity/), the live TVL script and how it avoids double-counting metapools.
