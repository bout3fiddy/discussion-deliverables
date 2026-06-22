# Three security changes to Curve's core AMM contracts

This is the story of the recovery efforts following a highly publicised blackhat incident. Three code snippets are chosen. This readme is a general storyline to set the scene.

## Primer on AMMs

Traditional exchanges run order books where buyers post bids, sellers post asks, and a matching engine pairs. Orderbooks are a data-intensive infrastructure that requires buyers and sellers to be present constantly re-quoting and reactive to the market, at an extremely high throughput (some participants require nanosecond level execution of their orders and the ability to cancel orders quickly). On a distributed ledger such as public blockchains, this is not possible. The ledger is distributed and every write to the global shared state is extremely expensive: every step costs measurable computational units called GAS. 

In such conditions, markets can be replaced by immutable programs (called smart contracts) that exist on the distributed ledger. These special classes of immutable smart contracts are called Automated Market Makers (AMMs), which replace an orderbook's matching engine with a suite of mathematical formulae that manage asset flow within the market, and an accompanying mathematical invariant that must hold true during an exchange of assets within the market. 

The AMM smart contract holds a reserve of assets (henceforth called a liquidity pool) and prices each trade from how much of each asset the pool currently holds. That pricing function, governed by the invariant, is called a bonding curve. Liquidity providers deposit assets and receive shares they later redeem; traders swap against the pool, and the bonding curve prices each swap based on the local state of the smart contract.

## Summary

In [July 2023 a bug in the Vyper compiler](https://hackmd.io/@vyperlang/HJUgNMhs2), introduced in a multi-year (2018-2023) refactor of the Vyper compiler, caused a mutex mechanism to malfunction, therefore allowing external callers to 'reenter' the smart contract in the midst of an execution and exploit stale state to cause financial losses. The result was a loss of about $70M and an exodus of $1.5B from the client's smart contracts (despite the fact that they were not affected).

The gist of the attack is as follows:

1. Each mutex can assign its own key, and therefore decorating a function with a mutex and a shared key e.g. `@nonreentrant('shared_key_A')` would 'lock' re-entry for all functions that shared the same key. 
2. The compiler bug gave each function its own separate lock even when they shared the same key, so functions that were meant to share one lock did not, therefore disabling cross-function mutex locks. 
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

In traditional exchange smart-contract designs, asset-flow transactions are always preceded by an 'approval' transaction, where the owner of the assets gives permission to the smart contract to spend a certain limit of the user's funds for exchange-related operations. The general risk that approvals carry are:

1. Users generally have a habit of giving smart contracts 'infinite approval', i.e. the authorisation to spend all of their assets (triggered by a user transaction), because they do not like the overhead of doing an approval transaction each time.
2. This leaves open cases where exploited/vulnerable smart contracts expose user funds to the danger of being stolen by hackers.
3. This risk prevents accredited investor parties and regulated entities from safely interacting with the smart contract.

To counteract this issue, a secondary exchange entry point was introduced which did not require approval transactions at all, while preserving legacy approaches that were more used to the older style. This secondary entrypoint utilised a novel approach where the smart contract would read 'excess' balances as amounts of the asset to be exchanged, instead of pulling pre-approved assets from the user's balances. The 'excess' balances would arise from the user 'optimistically transferring' funds to the smart contract and immediately calling the public exchange method within the same transaction.

An added advantage of a 'transfer-then-exchange' flow is that it allowed for a GAS optimisation where an aggregator chaining multiple swaps could avoid redundant transfers where cross-contract transactions were involved: initially, an exchange involving markets A and B would require a complex transaction flow: user -> exchange contract -> market A -> exchange contract -> market B -> user. With this new approach the transaction flow becomes user -> exchange contract -> market A -> market B -> user. That one additional transfer is a significant optimisation as it involves removing storage writes, and distributed ledgers price storage writes very high (see [evm.codes](https://www.evm.codes/?fork=osaka#55) for a simulator for SSTORE costs).

So, the approach not only strengthened security for users, it also unveiled a hidden optimisation that made the AMM contracts more competitive in the open markets. And AMM contracts benefit heavily from hyper-optimised code.

Source: [`CurveStableSwapNG.vy#L534`](https://github.com/curvefi/stableswap-ng/blob/2abe778f40206a6c0fd108a0a53ad3266cbedeee/contracts/main/CurveStableSwapNG.vy#L534).

### 2. Disallowing handing over execution context to external callers

Earlier designs allowed for handing over execution context to external callers for transactions involving specific asset types. These asset types did not require an approval transaction and in general had cheaper transfer costs. Older contracts exploited these characteristics to optimise exchange costs. But the same optimisation also leaves open an attack vector.

These special transactions always call, for some (not sufficiently justifiable) reasons, the receiver contract's hidden fallback `__default__()` method as a callback after receiving the assets. Which means that if, in the middle of a transaction execution, the sender smart contract invokes a transfer to a malicious smart contract, and the sender smart contract has a vulnerability in the mutex lock, then the malicious receiver smart contract's `__default__()` method containing malicious payload could infiltrate/re-enter the sender smart contract in the middle of a transaction. If the sender smart contract's state was stale, e.g. the sender smart contract initiated a transfer before book-keeping the exchange, the malicious smart contract could re-enter the contract knowing that the sender has not registered the transfer yet, and therefore extract more assets than what it gives in (therefore: breaking the invariant of the exchange's mathematical functions).

This was in fact the very same callback feature (a feature present in special kinds of blockchain implementation called the Ethereum Virtual Machine, or EVM), that the exploiters eventually utilised to steal assets from the exchange on July 2023. 

The gist here is: every point where a contract hands execution to code it does not control is a re-entry opportunity, and increases the chances that one guard failure leads to catastrophic losses. Fewer/No handoffs reduce that attack vector, but also: implementing a new book-keeping approach where the local state is committed before an execution context handoff is initiated also ensures this exploit is not profitable even if the exploiter somehow finds a way to re-enter.

The primary tradeoff made here was that we gave up the optimisation in favor of security, and chose to lobby for deeper security changes in the underlying execution platform itself, for instance by designing and lobbying for the [PAY opcode into the Virtual Machine itself](https://eips.ethereum.org/EIPS/eip-5920) which would allow for the transfer of these special assets without handing over execution context.

Source: [`CurveTricryptoOptimized.vy`](https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy).

### 3. Pruning unintentional 'happy accident' features (hiding underlying attack vectors)

Every exchange charges a fee, and the fee is harvested periodically. This approach to charge fees and harvest them can be designed in several ways. The older approach exposed the ability to do so publicly, allowing anyone to call the `claim_admin_fees()` method. The book-keeping set it out in a way such that any 'excess' assets that were not accounted for were effectively fees, therefore fees could be harvested by checking the actual asset balances (via calling `asset.balanceOf(market)`) against the accounted-for asset balances (via `self.balances[asset_index]`).

The market also had a feature where it could dynamically compress the bid-ask spread if there were sufficient profits it could spend (you need to spend assets to move positions and compress spreads). This was the whole value-proposition of the market: effectively to build a positive feedback loop where more exchanges would result in more revenue, some of which would be spent to compress spreads, therefore making the market more lucrative for exchanges, leading to more revenue ... But the same feature + the exposed `claim_admin_fees()` also allowed for 'donating' profits externally and in-organically to compress spreads. So, we have a situation where the function `claim_admin_fees()` does more things than what it advertises. In fact, ironically the unintentional feature was used by both [the blackhat to steal funds](https://hackmd.io/@LlamaRisk/BJzSKHNjn?stext=16191%3A351%3A0%3A1782162480%3Ax3DJ-c) and by the whitehat  rescue funds during the July 2023 exploit. [See White-hat 2, bout3fiddy's role](https://addison.is/posts/curve-whitehat).

It was clear that the function was overloaded and was doing too many things as a side-effect. External auditors had been flagging this feature-hotspot as potentially dangerous as it wasn't clear what side-effects were in the unknown-unknowns. After discussions, it was decided to strip the possibility of side-effect features entirely, and pursue it more seriously and deliberately after deep research.

Source: old [`CurveCryptoSwap.vy#L397`](https://github.com/curvefi/curve-crypto-contract/blob/d7d04cd9ae038970e40be850df99de8c1ff7241b/contracts/tricrypto/CurveCryptoSwap.vy#L397) and new [`CurveTricryptoOptimized.vy#L1099`](https://github.com/curvefi/tricrypto-ng/blob/ecaa8161c240f21dd7c3712eefc5637e1dac742b/contracts/main/CurveTricryptoOptimized.vy#L1099).

The work done to make the donate-to-compress-spreads feature is an ongoing research endeavour, by newer colleagues building upon the core work done in this step [Twocrypto.vy](https://github.com/curvefi/twocrypto-ng/blob/1ca3d7cd636d035cca620b1cd110864f18775305/contracts/main/Twocrypto.vy#L576).

## Code correctness, review and integrations

### Testing

The core testing suite is based on stateful, property-based fuzzing using python's `hypothesis` library. A hypothesis `RuleBasedStateMachine` sequences random state-changing actions, and checks economic invariants at each step. [Example Stateful Tests](https://github.com/curvefi/twocrypto-ng/blob/5cbe558902402e8fcb331463089db65fc56c11f9/tests/stateful/stateful_base.py#L7). [Example Fuzzing](https://github.com/curvefi/twocrypto-ng/blob/5cbe558902402e8fcb331463089db65fc56c11f9/tests/fuzzing/test_exchange_fuzzing.py).

Beyond property-based tests, differential tests were also employed against python implementations of the exchange mathematics versus the smart-contract implementation. [Example test for cube root implementation](https://github.com/curvefi/twocrypto-ng/blob/5cbe558902402e8fcb331463089db65fc56c11f9/tests/fuzzing/test_cbrt.py). 

Finally: unit tests and integration tests.

### External audits

The open source nature of financial software exposes bugs to adversarial attacks, as they are out in the open before smart contracts are even deployed to public blockchains. It is considered common practice to hire bespoke auditing firms that stress-test the software before or even after deployment. Specifically for the code mentioned in this repository, each codebase was assessed by at least two independent auditing firms, with public reports patching any discovered issues before production deployment.

Integrators and asset managers generally seek external reviewers they trust / read audit reports to ascertain the security of the infrastructure that their assets are deployed to.

### Documentation

The technical docs at [docs.curve.finance](https://docs.curve.finance), starting out as a private repository and now available publicly on [Github](https://github.com/CurveDocs/curve-docs).

### Beyond the code

Several of these changes are safe only when integrators build their transactions correctly, which requires reaching out and educating parties interacting with these smart contracts, on top of documentation. This involves:

1. teaching integrators and arbitrageurs to use new features that are security-preserving (e.g. the approval-free transactions were welcomed by exchange integrators).
2. writing jupyter notebooks showing different examples of how to use new features.

Shipping critical infrastructure holding several hundred millions to billions of dollars requires end-to-end engagement with its users.

## Engineering lessons

The three changes mentioned are a small part of larger set of lessons learnt during the refactoring and rebuilding process, some of which are summarised below.

The core, hard-earned lesson is this: the actual platform is the underlying hardware / virtual machine that runs the code produced by the compiler, and not the source code that is written by a programmer. The compiler can introduce unintuitive / unexpected artifacts, which are not visible in the source code, the hardware can run code in mysterious ways. A couple of examples:

a. The July 2023 Vyper compiler vulnerability exploit is one example. 
b. A python [branch-prediction example](./examples/03-branch-prediction/) is another one that shows how the underlying hardware can run code in unintuitive ways, where simply sorting inputs leads to faster code.
c. Apple M-series chips split their cores between performance and efficiency types, in ratios that vary by chip. These are specialised processors which handle different kinds of tasks: performance cores handle heavy parallel compute and consume more power, efficiency cores do simpler calculations and consume less power. Therefore a source code's performance increase by adding more workers is not linear, and drops sharply after exhausting performance threads. This is not visible in the compiler or the source code, and requires telemetry and some debugging to figure out what's actually happening.

Based on this core premise, here are the lessons learnt:

1. Verify the compiled output.
2. In mission critical software, treat unintentional features as bugs. 
3. A bug is a coordination failure. A post-hack analysis revealed that no single mistake caused the compiler bug. It was a mix of complacent users trusting compiler output, a complex smart contract language framework with a bus factor of 1 (due to lack of funding), and no processes involving audits.
4. Listen and empathise to users, and find out their true needs. Quite a lot of work was done to reduce transaction costs, but the most important users cared the most about not giving approvals to smart contracts, less so on transaction costs: they'd only transact if there was a profit to be made (including cost of profit).

## Numbers: Deposited funds post-hack and post security-first refactor

A consequence of the exploit was an exodus of billions of dollars of liquidity from the exchange. A consequence of pursuing security resulted in the following liquidity staying. These are numbers fetched live from the public blockchain, from contracts that were deployed post-hack, using [`code/liquidity/fetch-ng-tvl.sh`](./code/liquidity/fetch-ng-tvl.sh):

| Contract Type | Total Value (USD) | # Active Liquidity Pools |
|---|---:|---:|
| Stablecoins | $793.7M | 987 |
| 2-asset Volatile Markets | $277.6M | 361 |
| 3-asset Volatile markets | $30.2M | 131 |
| Grand total | ≈ $1.10 B | 1,479 |

The most consequential read of the efficacy of post-hack refactoring endeavours was a direct quote from a major asset manager stating verbatim that the smart contracts were "rock solid infra" and they felt "comfortable holding 8-9 figures in curve smart contracts".

## Further reading

Compiler, security, and incident writeups that document the July 2023 exploit:

1. [Vyper nonreentrancy lock post-mortem](https://hackmd.io/@vyperlang/HJUgNMhs2) (Vyper team): the official compiler-side root cause and timeline; affected versions 0.2.15, 0.2.16, and 0.3.0, patched in 0.3.1.
2. [Security advisory GHSA-5824-cm3x-3c38 / CVE-2023-39363](https://github.com/vyperlang/vyper/security/advisories/GHSA-5824-cm3x-3c38) (Vyper): the advisory with affected versions and exploit conditions.
3. [Fortune Article](https://fortune.com/crypto/2023/07/31/curve-finance-52-million-hack-hacker-helps-return-funds/) Fortune.com news article on recovery efforts from whitehats.
4. [Compiler error produces faulty bytecode from innocent source code](https://blocksec.com/blog/curve-incident-compiler-error-produces-faulty-bytecode-from-innocent-source-code) (BlockSec): how the source compiled to mis-allocated lock slots.
5. [Curve pool reentrancy exploit post-mortem](https://hackmd.io/@LlamaRisk/BJzSKHNjn) (LlamaRisk): the pool-side impact and the donate plus `claim_admin_fees` rescue, described independently.
6. [Curve Finance pools exploited due to code vulnerabilities](https://www.chainalysis.com/blog/curve-finance-liquidity-pool-hack/) (Chainalysis): the on-chain fund-flow analysis.
7. [White-hatting Curve Finance for $6m](https://addison.is/posts/curve-whitehat) (Addison Spiegel): the whitehat rescue, including the donate plus `claim_admin_fees` technique from change 3.

## Where to start

The READMEs and the short excerpts hold everything a reader needs.

1. This README, for the whole story.
2. The three excerpts in [`code/`](./code/), short annotated quotes with headers citing the exact source file, commit, and lines.
3. The runnable demonstrations in [`examples/`](./examples/).
