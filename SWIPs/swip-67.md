---
SWIP: 67
title: Custody separation and cutover
author: Cardinal (@0xCardiE), Andrew Macpherson (@awmacpherson)
discussions-to: https://github.com/ethersphere/SWIPs/pull/108
status: Draft
type: Standards Track
category: Core
created: 2026-09-07
---

<!-- Separates custody from policy so contract logic can be replaced without moving user
funds, and specifies the cutover protocol that replacement runs under. -->

## Contents

- [Simple Summary](#simple-summary) · [Abstract](#abstract)
- [Motivation](#motivation)
- [Specification](#specification)
  - [Key normative requirements at a glance](#key-normative-requirements-at-a-glance)
  - [Part 1 — Custody separation](#part-1--custody-separation) (C1–C5)
  - [Part 2 — Cutover](#part-2--cutover) (F0–F8)
- [Rationale](#rationale)
- [Backwards compatibility](#backwards-compatibility) — the two final migrations
- [Test cases](#test-cases) · [Implementation](#implementation) · [Open questions](#open-questions)
- [References](#references) · [Acknowledgements](#acknowledgements)

## Simple Summary

Swarm's storage-incentive contracts keep user money and changeable rules in the same
place. That single fact causes both of our recurring problems:

- **Security.** To change the rules without asking every user to move their money, we
  gave admins powers over money. The redistributor role can send the entire postage pot
  to any address; the admin role can mint batch state that no one paid for.
- **Migrations.** When we refuse to use those powers, we must instead move everyone's
  money — a fund movement for every user and every operator, every time the rules change.

This SWIP splits the two fund-holding contracts — `PostageStamp` and `StakeRegistry` —
each into a **core** and a **policy**. The core holds the money, has no admin power over
it, is never upgraded, and enforces its own accounting invariants. The policy holds the
rules, is freely replaceable, and can never name a payment destination.

`Redistribution` and `PriceOracle` hold no user deposits, so they are not split. They stay
replaceable contracts and are redeployed as-is: a new `Redistribution` on every breaking
wire release, so forked networks do not share one game; `PriceOracle` whenever its
adjustment rules change.

It then specifies the **cutover protocol** — how clients switch to a new policy and a new
`Redistribution` at a round boundary, so a protocol upgrade stops being a fund movement.

## Abstract

**Part 1 — Custody separation.** `PostageStamp` and `StakeRegistry` are each split into a
frozen custody core (`PostageAccounting`, `StakingCore`) and a replaceable policy contract
(`PostagePolicy`, `StakingPolicy`).

Cores hold all BZZ. They expose no function that transfers to a caller-supplied address;
they enforce token conservation against their own records; they rate-limit every
value-moving primitive a policy can trigger; they change their policy pointer only through
a timelock they enforce themselves; they never call into policy; and they offer a
permissionless exit that no role can pause. Policies hold batch admissibility, price
submission, overlay derivation, commitment and effective-stake maths, and slashing rules.

**Part 2 — Cutover.** Every breaking wire-protocol release MUST be accompanied by a
new `Redistribution` deployment, even when its code is unchanged, so that the two branches
of the resulting network fork do not play the same redistribution game. Cutover is
signalled on chain by a `Cutover` contract that publishes *timing only*; contract addresses
are carried in the client binary. Cutover MUST land on a round boundary and execute within
a bounded window. `PostageAccounting` enforces at most one authorised redistributor at any
block.

Together the parts remove admin custody of deposits, bound admin influence over future
rewards, and reduce a protocol upgrade from "everyone moves their money" to "clients point
at a new policy address".

## Motivation

### The two problems are one problem

Two threads have been running in parallel: an upgradeability thread
([`storage-incentives#310`][pr310]) and a migration thread (*Forking Swarm*). They are the
same problem seen from two sides. Because state and logic live in the same contract,
replacing logic means replacing state; replacing state means a migration; avoiding the
migration means giving an admin a shortcut over state — which is a power over funds. So we
oscillate between two bad options:

1. **Use the admin shortcut.** Cheap, but the admin can steal the pot and burn all stake.
2. **Do a full redeployment and migrate everything.** Rug-resistant, but every logic change
   becomes a fund movement for every user and operator, and no batch migration has ever
   been completed without admin-driven cloning.

*Forking Swarm* concludes that phasing out admin powers makes surgical redeployment
impossible, so every upgrade must become a full-suite redeployment with batch and stake
migration. That is true of the *current* architecture but is a consequence of the
coupling, not of the threat model. Break the coupling and both options improve at once.

### Where the custody surface is, in code

These are properties of the deployed contracts as of writing.

**`PostageStamp.withdraw(address beneficiary)`** is gated on `REDISTRIBUTOR_ROLE` and
transfers the whole of `totalPot()` to a caller-supplied address.

**`REDISTRIBUTOR_ROLE` is an OpenZeppelin `AccessControl` role**, so any number of
addresses can hold it simultaneously and `DEFAULT_ADMIN_ROLE` can grant it. Two were in
fact authorised at once during the v0.9.3/v0.9.4 rollout (see below).

**`PostageStamp.copyBatch` and `copyBatchBulk`** are gated on `DEFAULT_ADMIN_ROLE` and
create batch state — owner, depth, `normalisedBalance` — while incrementing
`validChunkCount`, **without transferring any BZZ into the contract**. `totalPot()` returns
`min(pot, balance)`, so unbacked state cannot directly over-transfer; but unbacked chunks
accrue pot at the same rate as paid ones, against the deposits of real batch owners.

**`PostageStamp` has no path that returns an unexpired batch deposit to anyone.** The only
outflow is `withdraw`, and it moves the pot, never batch balances. Remaining prepaid
storage is locked until it expires into the pot. This is why every batch migration to date
has used `copyBatch`: the funds for an honest re-purchase cannot be extracted. Any
migration plan that bans unbacked minting must therefore also say where the backing BZZ
comes from — see [Backwards compatibility](#backwards-compatibility).

**`StakeRegistry` is, by contrast, rug-resistant today.** No code path sends BZZ anywhere
except back to `msg.sender` (`withdrawFromStake`, `migrateStake`), and `slashDeposit` only
decrements the record, so slashed BZZ is burnt in place rather than stolen. Any change must
preserve this: making `StakeRegistry` upgradeable in the ordinary sense would be a strict
increase in attack surface, from "burn" to "steal".

**The existing escape hatch does not survive its own threat model.**
`StakeRegistry.migrateStake()` is `whenPaused`, and `pause()` requires `DEFAULT_ADMIN_ROLE`
(the contract declares no `PAUSER_ROLE`; the `OnlyPauser()` error name is misleading). In
the scenario the hatch exists for — the admin is the adversary — the hatch stays shut
unless the adversary opens it.

### What has gone wrong

From *Forking Swarm*:

- **Wire-only fork, v2.8.0 (2026-05-26).** A breaking wire-protocol change shipped without
  a new `Redistribution`. Rounds with a dissenting reveal went from approximately zero per
  week to approximately twenty; 2.8% of rounds in the first week; 44 distinct dissenting
  identities; nine rounds in three weeks (0.38%) in which a dissenter was leader. In round
  306865 a dissenter revealed depth 10, so nodes were frozen for longer and the depth floor
  blocked all nodes from the following round.
- **Staggered surgical redeployment, v0.9.3/v0.9.4 (2025).** Two redistributors were
  authorised on the same `PostageStamp` at once for three weeks, and the resulting race
  bled roughly 15 BZZ from operators on the production branch. Separately, the pausing of
  the old stake registry was scheduled well after the corresponding client release, so
  operators who had upgraded were unable to earn until it happened.

Neither is evidence that migration is inherently slow or expensive. Both are scheduling
failures: overlapping authority that should have been singleton, and a cutover that was
staggered when it should have been atomic. F3 and F4 remove both by construction. The
structural point worth keeping is that **the interval between a client release and the
pausing of the old registry is dead time for everyone who has upgraded**; the remedy is to
make the interval zero by construction.

### Why not put everything behind proxies

[`storage-incentives#310`][pr310] proposes upgradeable proxies for all core contracts plus
an on-chain versioned registry, a registry-guarded proxy, and a `pinnedExecute` path. The
objections raised in its review hold, and this SWIP is the alternative:

- A proxy over a fund-holding contract hands the proxy admin the ability to steal those
  funds.
- Verifying the registry inside the proxy fallback taxes every user call and introduces a
  liveness hazard: a mistaken deprecation or codehash mismatch reverts *all* user calls,
  including withdrawals.
- `pinnedExecute` imposes a permanent selector-collision constraint on every future
  implementation ABI and adds a second delegatecall path parallel to the fallback.
- The machinery solves "the admin swapped the implementation under me". If user funds live
  in a contract that cannot be swapped, that event is no longer a fund-loss event, and the
  machinery is not needed.

This SWIP keeps a registry-like contract for the job it is good at — signalling cutover
timing (F2) — and drops the guarded proxy and `pinnedExecute`.

### What this SWIP does not claim

Custody separation removes the *on-chain* cost of a migration. It does not remove the fork
itself. Per-batch bucket counters, stamp validity as seen by nodes, and chunk availability
are off-chain, per-branch state, and they still partition on a wire-protocol change exactly
as described in *Forking Swarm*. Batches carry across a fork unchanged under this proposal;
the stamp set still forks. What disappears is the coordination tax that made forks
expensive enough to avoid.

## Specification

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in
RFC 2119.

### Key normative requirements at a glance

| | Requirement |
|---|---|
| **C1** | Each fund-holding contract splits into a frozen core and a replaceable policy. Cores are never deployed behind a proxy and contain no `delegatecall`. |
| **C2.1** | No core function transfers to a caller-supplied address. Every destination derives from core state. |
| **C2.2** | The core enforces token conservation itself, incrementally, on every call, including pot accrual over live chunks. |
| **C2.3** | Calls go policy → core only. No callbacks, no core reads of policy, no dependence of core correctness on policy code. |
| **C2.4** | The core rate-limits every value-moving primitive policy can trigger. |
| **C2.5** | Pointers change only after a timelock the core enforces with an immutable constant; a pending change is cancellable, never extendable. |
| **C2.6** | Each core offers an exit with no role check, no pause, and no dependence on policy state. |
| **C2.7** | Cores have no upgrade path, so they MUST stay minimal. The outpayment accumulator, batch sizes, and the expiry ordering live in the core; the outpayment model is thereby frozen. |
| **C3.1** | Participation eligibility counts from `min(firstDepositBlock, preRegistrationBlock)`; the core records `firstDepositBlock`. |
| **C3.2** | Deposits are recorded per account. An account's deposit MUST cover the sum of committed stakes of the nodes it backs. |
| **C4** | Batch creation is policy-gated; ids bind to the originating account; `claimPot` takes no destination; `expire` is permissionless and self-verifying; `setPrice` is bounded. |
| **F1** | Every breaking wire release deploys a new `Redistribution`, even if the bytecode is unchanged. |
| **F2.1** | The chain signal carries timing. Contract addresses are compiled into the client. |
| **F2.2** | Clients determine activation by observing `Cutover` state, never by a height baked into the binary. |
| **F3** | `activationBlock` falls on a round boundary of the outgoing game, and authority changes execute within a bounded window from it. |
| **F4** | At most one redistributor is authorised at any block, enforced by type rather than by role hygiene. |
| **F5** | Any old-branch wind-down is pre-funded before cutover; a retired `Redistribution` never regains pot access. |
| **F6** | Clients read timing from chain, addresses from the binary, and send no fund-moving transaction in response to a chain signal. |
| **F7.1** | A cutover needing a runtime branch in consensus-critical computation is wire-breaking, and ships a single game ABI. |

### Part 1 — Custody separation

#### C1. Structure

The two fund-holding contracts, `PostageStamp` and `StakeRegistry`, are each split into a
frozen core and a replaceable policy.

| Core (frozen, holds BZZ, no admin power over held funds) | Policy (replaceable, holds no user deposits) |
|---|---|
| `PostageAccounting` — batch ownership, depth, per-batch normalised balance, the outpayment accumulator, valid-chunk count, expiry ordering, pot | `PostagePolicy` — batch admissibility, depth and bucket rules, minimum balances, price submission |
| `StakingCore` — per-account deposit, first-deposit block, withdrawal accounting | `StakingPolicy` — overlay derivation, height, committed stake, effective stake, freeze and slash rules |

`Redistribution` and `PriceOracle` are not split. They hold no user deposits, so they are
policy-class contracts: plain redeployments, never proxies (see Part 2). `Redistribution`
MAY transiently hold pot funds between `claimPot` and winner payout (C4). `PriceOracle` is
redeployed when its adjustment rules change.

Cores MUST NOT be deployed behind a proxy and MUST NOT contain `delegatecall`. Policies MAY
be proxied or plainly redeployed; C2 makes the choice non-custodial, and given F1 plain
redeployment is expected in practice.

#### C2. Core invariants

The split is not the security property; the invariants are. The current architecture
already has the shape "frozen ledger, swappable policy" — a `PostageStamp` that never
changes with a replaceable `Redistribution` authorised on it — and it leaks full custody
anyway, because `withdraw(beneficiary)` is an unconstrained primitive.

**C2.1 — No caller-supplied destinations.** A core MUST NOT transfer tokens to an address
supplied by the caller or by policy. Every destination MUST be derived from the core's own
recorded state:

- `PostageAccounting.refundBatch(batchId)` pays `ownerOf(batchId)`.
- `StakingCore.withdraw(amount)` pays `msg.sender`.
- `PostageAccounting.claimPot(amount)` pays the single authorised redistributor address,
  which is itself set only via C2.5.

**C2.2 — Conservation, enforced by the core.** Each core MUST maintain, checked at the end
of every state-changing call:

```
pot + sum(remaining batch claims) <= token.balanceOf(core)      (PostageAccounting)
totalDeposited - totalWithdrawn  <= token.balanceOf(StakingCore)
```

maintained incrementally, never by iterating balances. For `PostageAccounting` this
requires the core to own the accrual identity that today lives in
`PostageStamp.expireLimited`:

- the core records each batch's **depth** at creation, and maintains `validChunkCount`
  and `lastExpiryBalance` as its own aggregates;
- before any `claimPot` and before conservation is checked, accrued outpayment MUST be
  settled: expired batches contribute `batchSize * (normalisedBalance -
  lastExpiryBalance)`, live chunks contribute `validChunkCount * (currentTotalOutPayment()
  - lastExpiryBalance)`;
- settlement of live-chunk accrual MUST NOT run while an expired batch is still counted in
  `validChunkCount`, since that would credit the pot beyond the batch's backing.

The last bullet is why the expiry **ordering structure stays in the core** (C2.7): the core
can only know that no expired batch remains counted by knowing the minimum normalised
balance. An ordering index in policy would make conservation depend on policy honesty,
violating C2.3.

Unbacked batch creation (`copyBatch`) is precisely a breach of the first inequality, and
under C2.2 no policy — honest, buggy, or malicious — can reproduce it.

**C2.3 — One-way calls.** Calls MUST go policy → core only. A core MUST NOT call, delegate
to, or read from its policy, and MUST NOT expose callbacks or hooks. A corollary: a core
cannot ask policy whether an action is permitted; every check a core performs is
self-contained.

**C2.4 — Bounded authority.** Every value-moving primitive a policy can trigger MUST be
rate-limited by the core:

| Primitive | Bound |
|---|---|
| `claimPot(amount)` | at most `MAX_POT_FRACTION_PER_WINDOW` of `pot` per `CLAIM_WINDOW` blocks |
| `slash(account, amount)` | at most `MAX_SLASH_PER_WINDOW` in aggregate per `SLASH_WINDOW` blocks |
| `setPrice(price)` | `price <= MAX_PRICE`, step from `lastPrice` at most `MAX_PRICE_CHANGE_PER_UPDATE` |

The windows are core-owned block counts, not the redistribution game's round length, which
is per-branch and replaceable (F1). The parameters are immutable once set; values are an
open question.

Be precise about what the pot bound buys. The honest game already pays the whole pot to a
winner every round, so a `claimPot` cap at or above the honest rate does not slow a
malicious redistributor below normal outflow — it caps *acceleration*. The protections
against a hostile policy are the C2.5 timelock (it cannot be installed silently) and the
C2.6 exit (users can leave during the announcement window); the C2.4 bounds exist so that
even an installed hostile policy cannot flash-drain what has accrued between exits.

**C2.5 — Timelocked pointers, enforced by the core.** A core MAY allow its policy pointer
or its redistributor pointer to change, and if it does:

- the change MUST be proposed and then executed no earlier than `POLICY_TIMELOCK` blocks
  later, with both proposal and execution emitting events;
- the proposer (the governing address) MAY cancel a pending change at any time before
  execution; cancellation MUST NOT extend or shorten any other pending change;
- the timelock MUST be enforced by the core itself, not by an external timelock contract a
  role could replace, and `POLICY_TIMELOCK` MUST be immutable.

A core with a timelocked pointer **has a privileged operation** and is not admin-free. The
claim is narrower and checkable: *no privileged operation can move a user's deposit, and
every privileged operation is announced in advance with a guaranteed exit window*.

**C2.6 — Permissionless exit.** Each core MUST provide an exit that:

- any principal can call for their own funds, with no role check;
- has no pause modifier and cannot be disabled by any role;
- does not route through any replaceable contract;
- ignores any lock set by policy when computing the exit amount, using only core-recorded
  claims.

Concretely: `StakingCore.exit()` returns the caller's recorded deposit, and
`PostageAccounting.refundBatch(batchId)` returns the batch's remaining balance to its
owner. `exit()` MUST be preceded by `requestExit()` and callable `EXIT_DELAY` blocks later
— a fixed unbonding period, not a role-gated pause — so it cannot be used to dodge
in-flight slashing.

Two consequences are acknowledged rather than hidden:

- **`exit()` is withdrawable stake.** Today's `StakeRegistry` only returns surplus above
  the committed stake; a general unbonding exit is a change to staking economics, aligned
  with the ongoing withdrawable-stake discussion, and `EXIT_DELAY` MUST be at least the
  maximum freeze horizon the game can impose, or exit dodges penalties.
- **`refundBatch` changes the storage promise.** Today a batch balance is a commitment no
  one can retract; under this SWIP a mutable batch is revocable mid-life. Nodes MUST treat
  a refund event as batch invalidation (the same handling as expiry, on a new trigger), and
  clients MUST observe refund events. Because stamp validity is consensus-adjacent, the
  cutover that introduces `refundBatch` MUST be treated as Type A (F7). `refundBatch`
  SHOULD forfeit a fixed fraction of the remaining balance to the pot so that
  top-up/upload/refund is not free storage; the fraction is an open question. Immutable
  batches (`immutableFlag`) are not refundable.

**C2.7 — Frozen means frozen.** Cores have no upgrade path. This is the risk the proposal
takes on, and it MUST be managed by keeping cores minimal. A core with a bug and no admin
is worse than an upgradeable contract. Therefore:

- Cores hold balances, ownership, batch depth, the outpayment accumulator, the expiry
  ordering, the pointers and bounds their own invariants need, and the conservation check.
- Batch admissibility rules, effective-stake curves, commitment maths, overlay derivation
  live in policy, where they can be fixed.
- Cores MUST be formally specified and MUST have full invariant and fuzz coverage before
  deployment (see [Test cases](#test-cases)).

The outpayment accumulator cannot live in the replaceable half. A batch's
`normalisedBalance` is denominated *in the accumulator of the contract that issued it*:

```
currentTotalOutPayment() = totalOutPayment + lastPrice * (block.number - lastUpdatedBlock)
remainingBalance(id)     = max(0, normalisedBalance[id] - currentTotalOutPayment())
```

A fresh contract starts the accumulator at zero, so every balance must be *rebased*, not
re-pointed — which is what today's `copyBatch` does. If the accumulator lived in policy,
every policy replacement would rebase every batch: wrong expiry and premature reserve
eviction, once per upgrade instead of once per migration.

The cost is that **the outpayment model itself is frozen**: linear per-block accrual
against a per-chunk normalised balance. Moving to non-linear or per-neighbourhood pricing
is not a policy change and would still require a migration. This is the largest single
thing the proposal gives up; the one considered alternative is recorded in
[Open questions](#open-questions).

The expiry ordering structure in the core is the second-largest C2.7 risk: it is the most
edge-case-heavy component in the current contract, and under this SWIP it becomes
unfixable. It stays in the core because C2.2 requires it (see above); the compensation is
the mandatory adversarial and differential test burden in [Test cases](#test-cases).

#### C3. `StakingCore` interface

Staking is the easier case and SHOULD be done first: its only funds-out direction is
already "pay `msg.sender`", so C2.1 is satisfiable without changing any user's economics.

```solidity
interface IStakingCore {
    // ---- user ----
    /// @notice Deposit BZZ. Credited to msg.sender. No policy call.
    ///         Records firstDepositBlock on the account's first deposit.
    function deposit(uint256 amount) external;

    /// @notice Withdraw up to `amount` of the caller's unlocked deposit. Pays msg.sender only.
    function withdraw(uint256 amount) external;

    /// @notice Permissionless exit (C2.6). Not pausable, ignores policy locks.
    ///         exit() callable EXIT_DELAY blocks after requestExit().
    function requestExit() external;
    function exit() external;

    // ---- policy, bounded (C2.4) ----
    /// @notice Reduce a deposit. Burnt in place; never transferred out.
    ///         Reverts if the aggregate slash cap for the window is exceeded.
    function slash(address account, uint256 amount) external;

    // ---- policy, unbounded but exit-safe ----
    /// @notice Prevent withdraw() (but never exit()) for `until`.
    function lock(address account, uint64 until) external;

    // ---- views ----
    function depositOf(address account) external view returns (uint256);
    function firstDepositBlock(address account) external view returns (uint64);
    function totalDeposited() external view returns (uint256);
}
```

`StakingCore` MUST NOT store overlays, heights, committed stake, or effective stake, and
MUST NOT read `PriceOracle`. Those are per-branch, consensus-critical values and belong in
`StakingPolicy`. Overlay derivation mixes `NetworkId`, so it is redeployed with a fork;
deposits are not.

`StakingPolicy` SHOULD accept an immutable `predecessor` address and lazily inherit overlay
and height from it on first use, so a fork requires no operator transaction and no
eligibility delay.

**C3.1 — Eligibility clock.** `StakingPolicy` MUST compute participation eligibility from
`min(firstDepositBlock, preRegistrationBlock)`, where `firstDepositBlock` is the
core-recorded value above and pre-registration is a zero-value transaction an operator MAY
send in advance of a deposit or a cutover.

`Redistribution` requires a stake record older than `2 * ROUND_LENGTH` before a node may
participate. Without a pre-registration clock, any event that makes many operators
establish stake records at similar times produces a rolling participation trough, during
which a single dissenter's chance of being leader rises sharply — the v2.8.0 failure mode,
self-inflicted. Staggering the event lengthens the trough rather than fixing it;
pre-registration lets the settling period elapse beforehand.

**C3.2 — Accounts and nodes.** `StakingCore` records deposits per *account*; mapping an
account to one or more node overlays is `StakingPolicy`'s responsibility. Consequences:
fleet operations scale with accounts rather than nodes; withdrawal authority is separated
from the node's operational signer, so a compromised node key cannot move funds; and the
final stake migration's cost falls sharply.

Shared-account slashing is resolved by a **coverage requirement**: `StakingPolicy` MUST NOT
admit a set of overlays for an account whose summed committed stake exceeds the account's
core-recorded deposit, and a slash reduces the account's deposit (and therefore, at the
policy layer, the eligibility of all overlays it backs). Per-node sub-allocations were
considered and rejected as policy-side complexity the core cannot verify.

#### C4. `PostageAccounting` interface

```solidity
interface IPostageAccounting {
    // ---- policy-gated: batch admissibility lives in PostagePolicy ----
    /// @notice Create and fund a batch. The core derives the id from
    ///         (originator, nonce), records depth, transfers the total in from
    ///         the policy's caller, and credits the normalised balance.
    function fund(
        address originator, bytes32 nonce, address owner,
        uint8 depth, bool immutableFlag, uint256 amountPerChunk
    ) external returns (bytes32 batchId);

    /// @notice Change a batch's depth. The core preserves total remaining value,
    ///         recomputing the per-chunk balance and validChunkCount.
    function resize(bytes32 batchId, uint8 newDepth) external;

    /// @notice Submit a new price. The core folds it into its own accumulator.
    ///         Bounded by MAX_PRICE and MAX_PRICE_CHANGE_PER_UPDATE (C2.4).
    function setPrice(uint256 price) external;

    /// @notice Pay out to the single authorised redistributor. Capped per
    ///         window (C2.4). Destination is not a parameter.
    function claimPot(uint256 amount) external;

    // ---- user, direct on the core ----
    /// @notice Add funds to an existing batch. Owner and depth unchanged.
    function topUp(bytes32 batchId, uint256 amountPerChunk) external;

    /// @notice Owner-only exit, no role check (C2.6). Pays ownerOf(batchId).
    ///         Forfeits a fixed fraction to the pot. Reverts for immutable batches.
    function refundBatch(bytes32 batchId) external;

    /// @notice Retire batches whose remaining balance the core verifies as zero,
    ///         settling accrual per C2.2. Permissionless; ids are hints.
    function expire(bytes32[] calldata batchIds) external;

    // ---- redistributor pointer (C2.5, F4) ----
    function proposeRedistributor(address next) external;
    function cancelRedistributor() external;
    function executeRedistributor() external;

    // ---- views ----
    function remainingBalance(bytes32 batchId) external view returns (uint256);
    function normalisedBalanceOf(bytes32 batchId) external view returns (uint256);
    function depthOf(bytes32 batchId) external view returns (uint8);
    function ownerOf(bytes32 batchId) external view returns (address);
    function currentTotalOutPayment() external view returns (uint256);
    function validChunkCount() external view returns (uint256);
    function pot() external view returns (uint256);
    function redistributor() external view returns (address);
}
```

There is no `withdraw(address)` and no unbacked creation path. The redistributor pointer is
singleton by construction, which is the direct fix for the v0.9.3 double-redistributor
race.

**Call topology.** `fund` and `resize` are policy-gated: admissibility (minimum balance,
bucket-depth rules, mutability) is checked in `PostagePolicy` before it forwards to the
core, so a dead or hostile policy can block *creation* — a liveness cost bounded by the
C2.5 timelock — but never block `topUp`, `refundBatch`, `expire`, or conservation, which
are direct on the core. Price submission flows `PriceOracle` → `PostagePolicy` →
`setPrice`, and the C2.4 price bounds MUST be compatible with the oracle's adjustment
steps.

**Batch identity.** New batch ids MUST derive from `(originator, nonce)`, preserving
today's `keccak256(sender, nonce)` binding so an announced id cannot be front-run by a
third party. Ids not derived this way exist only as genesis-seeded state (see
[Backwards compatibility](#backwards-compatibility)); after genesis is sealed there is no
path that accepts an arbitrary id.

**Pot custody in `claimPot`.** The winner payout becomes two hops: the core pays the
authorised `Redistribution`, which pays the winner. `Redistribution` therefore transiently
holds pot funds; its claim path SHOULD complete both hops in one transaction, and any BZZ
stranded in a `Redistribution` by a failed payout is governance-recoverable there — it is a
policy-class contract holding protocol funds, not user deposits.

#### C5. Residual trust after Part 1

| Capability | Today | After Part 1 |
|---|---|---|
| Steal all staked BZZ | No (burn only) | No |
| Burn all staked BZZ | Yes (redistributor role) | No — capped per window (C2.4) |
| Steal the entire pot in one call | Yes (`withdraw(beneficiary)`) | No — no such primitive (C2.1) |
| Drain the pot over time | Yes | At most the honest payout rate, timelocked and announced (C2.4, C2.5) |
| Create unbacked batch state | Yes (`copyBatch`) | No (C2.2) |
| Misdirect *future* rewards | Yes | Yes, after `POLICY_TIMELOCK`, announced |
| Close the user escape hatch | Yes (`DEFAULT_ADMIN_ROLE`) | No (C2.6) |

Two capabilities survive: claiming the pot at up to the honest rate through a hostile
redistributor, and misdirecting future rewards after `POLICY_TIMELOCK`. **Custody
separation protects deposits, not rewards.** Bounding reward direction further would
require freezing redistribution verification itself, which conflicts with F1.

### Part 2 — Cutover

#### F0. Definitions

A **fork** of the Swarm network is a second network whose initial state is a clone of a
subset of the first's — canonically, of the stamp set. A **fork-migration** is a fork in
which the old branch is intended to be wound down. Every breaking change to the Swarm wire
protocol to date has been a fork-migration.

The **cutover protocol** is how this SWIP runs a fork-migration on the incentive contracts:
timing on chain, addresses in the client, authority change at a round boundary. It is
specified by F1–F8. It is not itself a fork, and it is also used for Type B (contract-only)
releases that do not fork the network.

A **breaking wire release** is a client release whose peer-negotiated protocol version
differs from its predecessor's, so that mismatched peers disconnect and at least two
disjoint p2p networks result.

#### F1. A new `Redistribution` per breaking wire release

Every breaking wire release MUST be accompanied by the deployment of a new `Redistribution`
contract, **even if its bytecode is unchanged**.

Contract identity, not the wire version, is what partitions the incentive game. Without a
new `Redistribution`, both branches play the same game with divergent views of the stamp
set — a negative-sum outcome in which stragglers claim payments intended for the new
branch, upgraded nodes earn less, and honest nodes are frozen for disagreeing with a
non-upgraded leader. This is the measured v2.8.0 failure mode.

`Redistribution` holds no state worth preserving, so this is close to free. It is the
cheapest recommendation in this SWIP and SHOULD be adopted as standing practice
independently of everything else here.

#### F2. Cutover signalling: timing on chain, addresses in the binary

A `Cutover` contract publishes the schedule:

```solidity
interface ICutover {
    struct Schedule {
        uint32 wireVersion;      // client protocol version this cutover activates
        uint64 activationBlock;  // MUST satisfy F3 alignment
        bytes32 manifest;        // hash of the release's address set
    }

    function schedule(uint32 wireVersion) external view returns (Schedule memory);
    function current() external view returns (Schedule memory);

    event CutoverScheduled(uint32 wireVersion, uint64 activationBlock, bytes32 manifest);
    event CutoverExecuted(uint32 wireVersion, uint64 atBlock);
}
```

**F2.1 — The signal carries timing; the binary carries addresses.** A client MUST NOT learn
a contract address from the chain and act on it. Contract addresses MUST be compiled into
the client release. The `Cutover` contract may tell a client *when* to switch; it MUST NOT
be able to tell it *where*. The `manifest` field is a hash the client checks against its
own compiled address set, and a mismatch MUST be a hard failure. The alternative — a client
that reads a destination from chain and moves funds toward it — reproduces, inside the
client, exactly the admin power this SWIP removes from the contracts.

**F2.2 — Schedules are event-driven, not height-hardcoded.** Clients MUST determine
activation by observing `Cutover` state, not by a height baked into the binary, so a
slipped date does not require an emergency release. A rescheduled `activationBlock` MUST be
re-announced at least `CUTOVER_NOTICE` blocks before the new activation.

**F2.3 — `Cutover` governance.** Schedules are written by the governing multisig. The
`Cutover` contract holds no funds and no fund-moving authority, so its failure mode is
liveness, not custody: a hostile or absent scheduler can delay cutovers, never redirect
money. Scheduling and rescheduling MUST emit events, and a schedule inside its
`CUTOVER_NOTICE` window MUST NOT be modified — cancellation counts as rescheduling.

#### F3. Round-aligned cutover with a bounded execution window

`activationBlock` MUST fall on a round boundary **of the outgoing game**:
`activationBlock % ROUND_LENGTH_outgoing == 0`. A cutover landing mid-round orphans nodes
that have committed: they lose their reveal window and may be frozen for a phase violation
they did not cause. If a release changes `ROUND_LENGTH`, that change is Type A (F7), and
the incoming game starts at a boundary of the outgoing one.

Exact-block execution cannot be demanded of a multisig, and "not before" (a bare timelock)
is not "at". Therefore:

- `executeRedistributor()` MUST be valid only within
  `[activationBlock, activationBlock + EXECUTION_WINDOW)` for the scheduled cutover, where
  `EXECUTION_WINDOW` is a core constant well under one round;
- the incoming `Redistribution` MUST accept commits from `activationBlock` onward;
- until execution, the outgoing redistributor remains authorised, so a late execution
  inside the window shortens the first new round's claim rather than orphaning anyone.

A gap in redistributor coverage and an orphaned round are distinct failures; the rules
above prevent both without demanding single-block inclusion.

#### F4. Exactly one redistributor, by construction

`PostageAccounting` MUST authorise at most one redistributor address at any block. The
pointer changes only through `proposeRedistributor` / `executeRedistributor` under
`POLICY_TIMELOCK` (C2.5) and the F3 window, and `claimPot` reverts for any caller that is
not the current pointer.

This replaces `REDISTRIBUTOR_ROLE`, under which multiple simultaneous holders are
representable and were in fact simultaneously authorised in 2025. Here singleton authority
is a property of the type, not of operational discipline. (Until `PostageAccounting`
exists, F4 can only be honoured operationally — see stage 1 in
[Implementation](#implementation).)

#### F5. Old-branch wind-down

Immediately zeroing rewards on the old branch is correct for incentive alignment and wrong
for data availability: old-branch data stays retrievable only while old-branch nodes stay
online.

Where a fork leaves user-side action with a tail, the schedule MAY include a wind-down
window during which the outgoing `Redistribution` continues paying at a reduced, decaying
rate. Its funding MUST be transferred into the outgoing `Redistribution` **before**
cutover — from the treasury or from a final pre-cutover `claimPot` — because after
cutover the retired contract is no longer the authorised pointer and MUST NOT regain pot
access. This is a payment overlap, never an authority overlap; F4 is not relaxed. Funds
left in a retired `Redistribution` after wind-down are governance-recoverable (it is
policy-class and holds no user deposits).

#### F6. Client requirements

A conforming client:

1. MUST compile in the full address set for each protocol version it supports, and the
   `manifest` hash for each.
2. MUST read `Cutover` for timing only, and MUST hard-fail on `manifest` mismatch (F2.1).
3. MUST switch the `Redistribution` address it uses at `activationBlock`, not when the
   operator restarts.
4. MUST NOT send any fund-moving transaction as an automated consequence of a chain
   signal. Under Part 1 no such transaction is required at cutover.
5. SHOULD expose the pending cutover in its status API and log a warning when running a
   version whose cutover has passed.

#### F7. Cutover types and dual-ABI scope

**Type A — wire-breaking.** The release changes the p2p protocol version, so vN and vN+1
nodes cannot peer. The client ships a *single* game ABI. A node that has not upgraded by
`activationBlock` stops earning — intended, and the entire content of F1. No dual-mode code
is required, because a non-upgraded node is on the other branch and must not be paid from
this branch's pot.

**Type B — contract-only.** The wire protocol is unchanged: a `Redistribution` bugfix, a
policy parameter change, a new `PostagePolicy`. Continuity is expected — operators running
a release that carries both bindings MUST keep earning across `activationBlock` — so the
client MUST carry both bindings and switch at `activationBlock`. The legacy binding MAY be
removed in the first release after the cutover.

**F7.1 — Consensus-path rule.** A cutover that would require a runtime branch in
consensus-critical computation — reserve sampling, commitment hashing, overlay derivation,
depth or eligibility determination, stamp-validity rules — MUST be Type A. A dual-mode
sampler is itself a source of dissent: two nodes disagreeing about which mode they are in
produce divergent reserve commitments, the exact failure F1 exists to prevent. This applies
even when the wire version would not otherwise change: a change to overlay derivation, the
eligibility clock, or the stamp-validity view (such as introducing `refundBatch`, C2.6)
MUST ship as Type A. F7.1 confines Type B's dual-mode surface to contract call sites.

Under Part 1 the frozen cores never acquire a second ABI, so deposits, withdrawals and
balance reads never branch in either type. Only policy and `Redistribution` bindings do.

#### F8. Relationship between the parts

Part 2 alone still requires a stake migration at every fork, and therefore an interval in
which upgraded operators cannot earn. Part 1 alone leaves the fork boundary undefined, so
wire-only forks keep commingling incentives. Together: deposits never move at cutover
(F6.4); `Redistribution` identity still changes per fork (F1); batches carry across, so
there is no batch migration; and the interval "between release and pausing the old
registry" collapses to zero, because there is nothing to pause and nothing to move.

## Rationale

**Why not "always full redeploy".** *Forking Swarm*'s proposal requires a batch migration
at every breaking wire release, leaves batch migration undesigned, and relies on an
incentive asymmetry that does not hold: operators migrate stake to keep earning, but a user
who fails to migrate a batch loses availability they may not notice until they need the
data. Part 1 removes the requirement rather than solving the coordination problem.

**Why the registry survives as a cutover signal.** For *security* an on-chain registry adds
nothing: the trust root is the client release process either way. For *coordination* it
adds something real: every client switches at the same block regardless of when its
operator restarted. F2 keeps the coordination; F2.1 removes the security temptation.

**Why batch creation is policy-gated but exits are not.** Admissibility rules change per
branch and per policy generation; they cannot be frozen. Exits are the security property
and must not depend on any replaceable contract. The asymmetry is deliberate: a hostile
policy can stop new business, never trap existing funds.

**Why bounds rather than prohibitions.** A policy with no authority over funds cannot
slash and cannot pay winners, and is therefore not an incentive system. The achievable goal
is *bounded, announced, visible* authority with a usable exit — C2.4 through C2.6 made
concrete.

**Alternatives considered and rejected.**

- *Immutable policy pointer in the core.* Strictly stronger, but changing policy then means
  a new core, which reintroduces migration and defeats the purpose.
- *External timelock contract owning the pointer.* Weaker than C2.5: whoever can replace
  the timelock's owner can shorten the window.
- *Expiry ordering in policy.* Rejected: C2.2's accrual settlement requires the core to
  know the minimum normalised balance (see C2.2); an ordering index the core cannot trust
  would make conservation depend on policy honesty.
- *User-driven batch migration through `fund()`.* Rejected as the primary path: the BZZ
  backing existing batches is locked inside `PostageStamp`, which has no extraction path,
  so "user-driven" means users pay twice. See Backwards compatibility.
- *Governance vote on policy changes.* Orthogonal and compatible; this SWIP specifies the
  contract-level constraints that hold regardless of how the governing address is
  constituted.

## Backwards compatibility

This is a breaking change to the contract suite and requires a coordinated release. It is
also, by design, intended to be the **last** such change that moves user funds.

**Final stake migration.** Operators move deposits from `StakeRegistry` to `StakingCore`
via the existing `migrateStake()` path. It MUST be run under the F2/F3 protocol, and —
unlike 2025 — the old registry MUST be paused at `activationBlock`, so the interval between
the client release and the pause is zero. Operators SHOULD pre-register (C3.1) so no
eligibility trough opens.

**Final batch migration: treasury-matched genesis.** `PostageStamp` cannot release
unexpired deposits (see Motivation), so the batch state must be seeded and separately
backed:

1. At `activationBlock`, `PostageStamp` is paused (freezing `createBatch`, `topUp`,
   `increaseDepth`; expiry and `withdraw` continue to operate).
2. `PostageAccounting` is deployed in a **genesis phase**: the deployer seeds the batch set
   — id, owner, depth, bucket depth, immutability, remaining per-chunk balance — exactly as
   of `activationBlock`, and MUST transfer in matching BZZ for the full seeded value. The
   treasury fronts this float.
3. Genesis is **sealed** in the same ceremony. Until sealed, the core accepts no other
   call; after sealing, no seeding path exists and C2.2 holds from the first open block.
   Seeding MUST NOT be possible after sealing under any role.
4. The treasury is reimbursed from the old contract as seeded batches' old-side balances
   expire into the old pot, using the existing `withdraw(beneficiary)` with the treasury as
   beneficiary. This is the final, announced use of the unconstrained withdraw, and it
   moves only money the treasury already fronted. The reimbursement horizon equals the
   longest remaining batch life; the required float size is an open question.

`PostageAccounting` contains **no unbacked creation function at any point** — the genesis
seed is deposit-matched by construction, which is the difference from `copyBatch`.

**Client ABI.** Clients learn a two-contract layout per subsystem: consensus-critical reads
(overlay, effective stake, batch admissibility) from policy; balances, deposits, batch
depth and expiry from the core. A read-only compatibility view of the old
`batches(...)`/`stakes(...)` shapes MAY be deployed for integrators; clients MUST NOT
depend on it for consensus-critical values.

## Test cases

Cores are unupgradeable, so the following are mandatory before any core deployment.

**Invariant tests (must hold after every call, under all orderings).**

- `pot + sum(remaining claims) <= token.balanceOf(PostageAccounting)` (C2.2), including
  across expiry, `resize`, `refundBatch` and price changes.
- `totalDeposited - totalWithdrawn <= token.balanceOf(StakingCore)` (slashing burns in
  place, so balance exceeds claims).
- Pot accrual identity: settled pot equals the sum over batches of
  `batchSize * min(normalisedBalance, currentTotalOutPayment) - initial credit`,
  differentially checked against `PostageStamp.expireLimited` over historical batch data.
- No execution path transfers to an address not derived from core state (C2.1) — enforced
  by a static check over core bytecode as well as by tests.
- No core function reaches an external call into the policy address (C2.3).

**Adversarial-policy tests.** Instantiate each core with a malicious policy attempting, at
minimum: draining the pot in one call; slashing every account to zero; claiming beyond the
window cap; creating a batch whose transfer-in does not match the credited value; resizing
a batch to inflate remaining value; blocking a user's exit; setting a price beyond the
C2.4 bounds. Each MUST revert, and `exit()`/`refundBatch()` MUST succeed throughout.

**Exit tests.** `exit()` and `refundBatch()` MUST succeed while the policy is malicious,
while the policy address is zero, while a pointer change is pending, and — for
`StakingCore` — while the account is policy-locked.

**Genesis tests.** Seeding MUST revert without a matching deposit; any call before sealing
MUST revert; seeding after sealing MUST revert from every role; conservation MUST hold at
the first open block.

**Timelock and window tests.** A pointer change MUST NOT execute before `POLICY_TIMELOCK`
nor outside `[activationBlock, activationBlock + EXECUTION_WINDOW)`; cancellation works
only before execution; the pending change is readable throughout.

**Cutover tests.** A boundary-aligned cutover MUST NOT orphan a committed node (F3); an
off-boundary schedule MUST revert; a `manifest` mismatch MUST hard-fail the client.

**Accumulator continuity tests.** A policy replacement MUST NOT change
`currentTotalOutPayment()`, `normalisedBalanceOf()` or `remainingBalance()` for any batch,
tested across a pending price update and mid-expiry.

**Expiry self-verification tests.** `expire()` MUST credit the pot only for ids the core
independently computes as expired, MUST be safe under arbitrary, duplicated, non-existent
or unexpired ids, and live-chunk accrual MUST NOT settle while an expired batch remains
counted.

**Eligibility clock tests.** A pre-registered operator MUST be eligible at
`activationBlock` without settling delay (C3.1); a non-pre-registered one MUST NOT be.

**Fuzz and differential.** Fuzz conservation across randomised sequences of deposit,
fund, top-up, resize, price update, expire, claim, slash, refund, withdraw and exit.
Differentially test core accounting against the current `PostageStamp` over historical
data to confirm identical remaining-balance and expiry results.

## Implementation

Staged so that each stage is independently valuable and independently revertible.

| Stage | Content | Depends on |
|---|---|---|
| 1 | Surgical `Redistribution` redeployment with security fixes; round-aligned cutover; singleton redistributor *by operational discipline* (one role holder; the type-level guarantee lands in stage 5) | — |
| 2 | F1 adopted as standing practice: new `Redistribution` on every breaking wire release | — |
| 3 | `Cutover` contract and client support (F2, F3, F6, F7). `storage-incentives#310` reduced to a plain release registry; guarded proxy and `pinnedExecute` dropped | 2 |
| 4 | `StakingCore` + `StakingPolicy`. Final stake migration | 3 |
| 5 | `PostageAccounting` + `PostagePolicy`. Treasury-matched genesis; `copyBatch` retired | 4 |
| 6 | Governing multisig scope reduced to policy pointers | 5 |

Stage 1 addresses measured harm and is the immediate next upgrade. Stage 2 is available
today at no cost. Stages 4 and 5 are where the custody property lands. After stage 5,
surgical redeployment and the absence of admin power over deposits coexist — the two things
currently treated as mutually exclusive.

## Open questions

1. **Parameter values.** `POLICY_TIMELOCK` (suggested: 14 days in blocks), `EXIT_DELAY`
   (MUST be ≥ the maximum freeze horizon, `penaltyMultiplier * ROUND_LENGTH * 2^depth` at
   plausible depths), `EXECUTION_WINDOW`, `CUTOVER_NOTICE`, `MAX_SLASH_PER_WINDOW`,
   `SLASH_WINDOW`, `MAX_POT_FRACTION_PER_WINDOW`, `CLAIM_WINDOW`, `MAX_PRICE`,
   `MAX_PRICE_CHANGE_PER_UPDATE` (MUST be compatible with `PriceOracle`'s adjustment
   steps). Immutable once deployed; each needs a written derivation, not a suggestion.
2. **Refund economics.** The `refundBatch` forfeit fraction, and the wind-down decay
   schedule (F5). A forfeit fraction is preferred over a minimum batch age: age penalises
   exactly the long-lived honest batches C2.6 exists for.
3. **Treasury float.** The genesis migration requires the treasury to front the full
   remaining batch value and be reimbursed over the longest batch life. What float is
   acceptable, and should a deadline cap the reimbursement tail?
4. **Multi-client discipline.** F2, F3 and F6 assume every client implements cutover
   identically. What is the conformance mechanism if a second client exists?
5. **Frozen outpayment model.** The accumulator in the core freezes linear per-block
   accrual (C2.7). The considered alternative is to stop denominating in a global
   accumulator: store each batch's remaining BZZ explicitly and let policy consume it into
   the pot under a C2.4 rate cap. That keeps pricing-model changes policy-side and lets
   users refund under a hostile consumption schedule, at the cost of a larger core and a
   harder expiry index. Is linear accrual the model to commit to indefinitely, or is
   remaining-BZZ-plus-capped-consumption the better thing to freeze?

## References

- [`ethersphere/storage-incentives#310`][pr310] — Versioned Registry Router + Upgradeable
  Proxies for All Core Contracts, and the review discussion that motivated this SWIP.
- *Forking Swarm: A migration guide* — Andrew Macpherson, Shtuka Research (presentation,
  2026).
- Deployed contracts referenced throughout: `src/PostageStamp.sol`, `src/Staking.sol`,
  `src/Redistribution.sol` in `ethersphere/storage-incentives`.

[pr310]: https://github.com/ethersphere/storage-incentives/pull/310

## Acknowledgements

Part 2 is substantially derived from Andrew Macpherson's *Forking Swarm* presentation
(Shtuka Research) and his review of [`storage-incentives#310`][pr310]: the fork and
fork-migration framing (F0); the argument that contract identity, not wire version,
partitions the incentive game (F1); the v2.8.0 dissent measurements and the v0.9.3/v0.9.4
case study; the assessment that upgradeable staking is a strict increase in attack surface;
and the observation that the interval between a client release and the pausing of the old
registry is dead time for upgraded operators.

Review of the first draft materially changed Part 1: the outpayment accumulator cannot live
in the replaceable half (C2.7), and the dual-ABI maintenance argument answered by F7.1
(Mark Bliss). A subsequent review pass established that batch sizes and the expiry
ordering must also be core-side for C2.2 to be enforceable, that `PostageStamp` has no
deposit-extraction path — forcing the treasury-matched genesis design — and the F3
execution-window form of cutover.

This SWIP departs from *Forking Swarm* on one conclusion, set out in
[Motivation](#motivation).

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
