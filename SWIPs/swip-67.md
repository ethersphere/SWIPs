---
SWIP: 67
title: Custody separation and fork migration
author: Cardinal (@0xCardiE), Andrew Macpherson (@awmacpherson)
discussions-to: https://github.com/ethersphere/SWIPs/pull/108
status: Draft
type: Standards Track
category: Core
created: 2026-09-07
---

<!-- Two halves of one problem. Storage-incentive contracts today put user funds and
mutable logic in the same contract, so every logic change is a fund migration, and every
shortcut around a fund migration is an admin power over funds. This SWIP separates
custody from policy so that logic can be replaced without moving funds, and specifies
the fork-migration protocol that replacement runs under. -->

## Simple Summary

Swarm's storage-incentive contracts keep user money and changeable rules in the same
place. That single fact causes both of our recurring problems:

- **Security.** To change the rules without asking every user to move their money, we
  gave admins powers over money. The redistributor role can send the entire postage pot
  to any address; the admin role can mint batch state that no one paid for.
- **Migrations.** When we refuse to use those powers, we must instead move everyone's
  money. Every logic change becomes a fund movement for every user and every operator,
  which is why we keep avoiding it, and why no batch migration has ever been completed
  without admin-driven cloning.

This SWIP splits each contract in two. A **core** holds the money, has no admin, is never
upgraded, and enforces its own accounting invariants. A **policy** holds the rules, is
freely replaceable, and can never name a payment destination. It then specifies the
**fork-migration protocol** — how a new policy and a new Redistribution contract are cut
over atomically at a round boundary, so that a protocol upgrade stops being a fund
movement at all.

## Abstract

We specify two coupled changes to the storage-incentive contract suite.

**Part 1 — Custody separation.** `PostageStamp` and `StakeRegistry` are each split into a
frozen custody core (`PostageAccounting`, `StakingCore`) and a replaceable policy contract
(`PostagePolicy`, `StakingPolicy`). Cores hold all BZZ, expose no function that transfers
to a caller-supplied address, enforce token-conservation invariants against their own
recorded state, rate-limit every value-moving primitive a policy can trigger, change their
policy pointer only through a self-enforced timelock, never call into policy, and offer a
permissionless exit that no role can pause. Policies hold batch admissibility, pricing,
overlay derivation, commitment and effective-stake maths, and slashing rules.

**Part 2 — Fork migration.** Every breaking wire-protocol release MUST be accompanied by a
new `Redistribution` deployment, even when its code is unchanged, so that the two branches
of the resulting network fork do not play the same redistribution game. Cutover is
signalled on chain by a `Cutover` contract that publishes *timing only*; contract addresses
are carried in the client binary. Cutover MUST land on a round boundary, with the outgoing
redistributor refusing new commits one round early so the game drains rather than stops.
`PostageAccounting` enforces at most one authorised redistributor at any block.

Together the parts remove admin custody of deposits, bound admin influence over future
rewards, and reduce a protocol upgrade from "everyone moves their money" to "clients point
at a new policy address".

## Motivation

### The two problems are one problem

Two threads have been running in parallel: an upgradeability thread (see
[`storage-incentives#310`][pr310]), and a migration thread about how we roll out new
network versions (see *Forking Swarm*). They are the same problem seen from two sides.

Because state and logic live in the same contract, replacing logic means replacing state.
Replacing state means a migration. Avoiding the migration means giving an admin a shortcut
over state — which is a power over funds. So we oscillate between two bad options:

1. **Use the admin shortcut.** Cheap, but the admin can steal the pot and burn all stake.
2. **Do a full redeployment and migrate everything.** Rug-resistant, but it turns every
   logic change into a fund movement for every user and every operator, and no batch
   migration has ever been completed without admin-driven cloning.

The conclusion drawn in *Forking Swarm* — that phasing out admin powers makes
surgical redeployment impossible, so every upgrade must become a full-suite redeployment
with batch and stake migration — is true of the *current* architecture but is not
architecturally necessary. It is a consequence of the coupling, not of the threat model.
Break the coupling and both options improve at once.

### Where the custody surface actually is, in code

The following are properties of the deployed contracts as of writing, not hypotheticals.

**`PostageStamp.withdraw(address beneficiary)`** is gated on `REDISTRIBUTOR_ROLE` and
transfers the whole of `totalPot()` to a caller-supplied address. One call, entire pot, any
destination.

**`REDISTRIBUTOR_ROLE` is an OpenZeppelin `AccessControl` role**, so any number of addresses
can hold it simultaneously and `DEFAULT_ADMIN_ROLE` can grant it. This is not a theoretical
concern: during the v0.9.3/v0.9.4 rollout two live redistributors were authorised on the
same `PostageStamp` at once, and the resulting race bled roughly 15 BZZ from operators on
the production branch over three weeks (*Forking Swarm*, case study 2).

**`PostageStamp.copyBatch` and `copyBatchBulk`** are gated on `DEFAULT_ADMIN_ROLE` and
create batch state — owner, depth, `normalisedBalance` — while incrementing
`validChunkCount`, **without transferring any BZZ into the contract**. `totalPot()` returns
`min(pot, balance)`, so this cannot directly over-transfer; but unbacked chunks accrue pot
at the same rate as paid ones, so the admin can accelerate pot accrual against the deposits
of real batch owners. Any honest accounting of admin attack surface must include these
functions alongside redistributor assignment. They exist to facilitate exactly the batch
migrations this SWIP aims to make unnecessary.

**`StakeRegistry` is, by contrast, genuinely rug-resistant today.** No code path sends BZZ
anywhere except back to `msg.sender` (`withdrawFromStake`, `migrateStake`), and
`slashDeposit` only decrements the record without transferring, so slashed BZZ is burnt in
place rather than stolen. This property is worth stating precisely because it is the
property any change must preserve: making `StakeRegistry` upgradeable in the ordinary sense
would be a strict increase in attack surface, from "burn" to "steal".

**The existing escape hatch does not survive its own threat model.**
`StakeRegistry.migrateStake()` is `whenPaused`, and `pause()` requires `PAUSER_ROLE`. In
the scenario the hatch exists for — the admin is the adversary — the hatch is closed by the
adversary. An escape hatch gated on a privileged role is not an escape hatch.

### What has actually gone wrong

From *Forking Swarm*:

- **Wire-only fork, v2.8.0 (2026-05-26).** A breaking wire-protocol change shipped without
  a new `Redistribution`. Rounds with a dissenting reveal went from approximately zero per
  week to approximately twenty; 2.8% of rounds in the first week; 44 distinct dissenting
  identities; nine rounds in three weeks (0.38%) in which a dissenter was leader. In round
  306865 a dissenter revealed depth 10, so every node was frozen for twice as long and the
  depth floor blocked all nodes from the following round.
- **Staggered surgical redeployment, v0.9.3/v0.9.4 (2025).** Two redistributors were
  authorised on the same `PostageStamp` at once for three weeks, and the resulting race
  bled roughly 15 BZZ from operators on the production branch. Separately, the pausing of
  the old stake registry was scheduled well after the corresponding client release, so
  operators who had upgraded were unable to earn until it happened.

Neither of these is evidence that migration is inherently slow or expensive. Both are
scheduling failures: overlapping authority that should have been singleton, and a cutover
that was staggered when it should have been atomic. They are cited here because F3 and F4
remove both by construction, not to argue that migrations cost weeks.

The structural point worth keeping from *Forking Swarm* is that **the interval between a
new client release and the pausing of the old stake registry is dead time for everyone who
has upgraded**. Its length in any given rollout is a matter of scheduling; the remedy is to
make the interval zero by construction rather than to try to keep it short.

### Why not simply put everything behind proxies

[`storage-incentives#310`][pr310] proposes upgradeable proxies for all core contracts plus
an on-chain versioned registry, a registry-guarded proxy, and a `pinnedExecute` path that
lets a client pin an expected implementation atomically. The reviewer objections to that
approach are, in our assessment, correct, and this SWIP is the alternative:

- A proxy over a fund-holding contract hands the proxy admin the ability to steal those
  funds. For `StakeRegistry` this converts today's "admin can burn stake" into "admin can
  steal stake".
- Verifying the registry inside the proxy fallback taxes every user call and introduces a
  liveness hazard: a mistaken deprecation or a codehash mismatch reverts *all* user calls,
  including withdrawals. That layers an availability risk on top of the custody risk it is
  trying to mitigate.
- `pinnedExecute` imposes a permanent selector-collision constraint on every future
  implementation ABI and adds a second delegatecall path parallel to the fallback.
- Most importantly, the machinery solves "the admin swapped the implementation under me".
  If user funds live in a contract that cannot be swapped, that event is no longer a
  fund-loss event, and the machinery is not needed.

The on-chain registry does have real value, but it is coordination and observability
value, not security value: the trust root for which contracts a node talks to is the client
release process either way. This SWIP therefore keeps a registry-like contract and gives it
the job it is actually good at — signalling cutover timing (Part 2, F2) — and drops the
guarded proxy and `pinnedExecute`.

### What this SWIP does not claim

Custody separation removes the *on-chain* cost of a migration. It does not remove the fork
itself. Per-batch bucket counters, stamp validity as seen by nodes, and chunk availability
are off-chain, per-branch state, and they still partition on a wire-protocol change exactly
as described in *Forking Swarm*. Batches carry across a fork unchanged under this
proposal; the stamp set still forks. What disappears is the coordination tax that made
forks expensive enough to avoid.

## Specification

The key words MUST, MUST NOT, SHOULD, SHOULD NOT and MAY are to be interpreted as in
RFC 2119.

### Part 1 — Custody separation

#### C1. Structure

Each fund-holding contract is split into two deployed contracts.

| Core (frozen, no admin, holds BZZ) | Policy (replaceable, holds no BZZ) |
|---|---|
| `PostageAccounting` — batch ownership, per-batch balance, pot, total deposited, total paid out | `PostagePolicy` — batch admissibility, depth and bucket rules, minimum balances, price ingestion, expiry ordering |
| `StakingCore` — per-address deposit, withdrawal accounting | `StakingPolicy` — overlay derivation, height, committed stake, effective stake, freeze and slash rules |

`Redistribution` and `PriceOracle` are policy-class contracts: they hold no user funds and
are plain redeployments, never proxies (see Part 2).

Cores MUST NOT be deployed behind a proxy. Cores MUST NOT contain `delegatecall`. Policies
MAY be deployed behind a proxy or MAY be plain redeployments; this SWIP does not mandate
either, because C2 makes the choice non-custodial. Given F1, plain redeployment is expected
to be simpler in practice.

#### C2. Core invariants

These are the substance of the proposal. A split that does not satisfy them buys nothing:
it relocates the trust boundary by one hop and leaves it exactly as wide. Note that the
current architecture already has the shape "frozen ledger, swappable policy" — a
`PostageStamp` that never changes, with a replaceable `Redistribution` authorised on it —
and it leaks full custody, because `withdraw(beneficiary)` is an unconstrained primitive.
The shape is not the property. The invariants are.

**C2.1 — No caller-supplied destinations.** No function on a core MAY transfer tokens to an
address supplied by the caller or by policy. Every destination MUST be derived from the
core's own recorded state:

- `PostageAccounting.refundBatch(batchId)` pays `batches[batchId].owner`.
- `StakingCore.withdraw()` pays `msg.sender`.
- `PostageAccounting.claimPot()` pays the single authorised redistributor address, which is
  itself set only via C2.5.

**C2.2 — Conservation, enforced by the core.** Each core MUST track total deposited and
total paid out, and MUST maintain, checked at the end of every state-changing call:

```
sum(recorded claims) + pot <= token.balanceOf(core)
```

The core MUST own exactly enough arithmetic to police this and no more. In particular, pot
growth MUST be bounded by the core independently of policy's accounting: policy may *assert*
an accrual, but the core MUST reject any accrual that would breach the inequality above.
This matters because unbacked-batch creation (`copyBatch`) is precisely a breach of it, and
under C2.2 no policy — honest, buggy, or malicious — can reproduce that behaviour.

**C2.3 — One-way calls.** Calls MUST go policy → core only. A core MUST NOT call, delegate
to, or read from its policy, and MUST NOT expose callbacks or hooks. Core correctness MUST
NOT depend on policy code. A corollary: a core cannot ask policy whether an action is
permitted; every check a core performs is self-contained.

**C2.4 — Bounded authority.** Every value-moving primitive a policy can trigger MUST be
rate-limited by the core:

| Primitive | Bound |
|---|---|
| `claimPot()` | at most `MAX_POT_FRACTION_PER_ROUND` of `pot` per `ROUND_LENGTH` window |
| `slash(node, amount)` | at most `MAX_SLASH_PER_EPOCH` per node and in aggregate per epoch |
| pot accrual | bounded by C2.2, and by `MAX_PRICE` on the ingested price |

Suggested initial values are given in [Open questions](#open-questions); they are
parameters of the deployment, immutable in the core once set. The purpose of the bounds is
not to make theft impossible in the limit — it is to make it *slow and visible*, so that the
exit in C2.6 has a usable window.

**C2.5 — Timelocked policy pointer, enforced by the core.** A core MAY allow its policy
pointer to change, and if it does:

- the change MUST be proposed and then executed no earlier than `POLICY_TIMELOCK` blocks
  later, with both proposal and execution emitting events;
- the timelock MUST be enforced by the core itself, not by an external timelock contract
  that a role could replace;
- `POLICY_TIMELOCK` MUST be immutable.

We state plainly what this is and is not. A core with a timelocked policy pointer **has a
privileged operation**; it is not literally admin-free. The claim being made is narrower and
checkable: *no privileged operation can move a user's deposit, and every privileged
operation is announced in advance with a guaranteed exit window*. Proposals that describe
this as "no admins" should be corrected to this formulation.

**C2.6 — Permissionless exit.** Each core MUST provide an exit that:

- any principal can call for their own funds, with no role check;
- has no pause modifier and cannot be disabled by any role;
- does not route through any replaceable contract;
- ignores policy-supplied state (commitments, freezes, height) when computing the exit
  amount, using only core-recorded claims.

Concretely: `StakingCore.exit()` returns the caller's recorded deposit, and
`PostageAccounting.refundBatch(batchId)` returns the batch's remaining balance to its owner.
`StakingCore.exit()` SHOULD be subject to an `EXIT_DELAY` (a fixed unbonding period, not a
role-gated pause) so that it cannot be used to dodge in-flight slashing.

The postage exit needs an economic guard, because a batch owner could otherwise top up,
upload, and immediately refund, obtaining storage for free. `refundBatch` SHOULD forfeit a
fixed fraction of the remaining balance to the pot, or be subject to a minimum batch age.
This is an economic parameter, not a security one, and is listed as an open question.

**C2.7 — Frozen means frozen.** Cores have no upgrade path. This is the risk the proposal
takes on, and it MUST be managed by keeping cores minimal. A core with a bug and no admin is
worse than an upgradeable contract. Therefore:

- Cores hold balances, ownership, monotone accumulators, and the conservation check. Nothing
  else.
- Everything with interesting edge cases — the expiry ordering structure, batch selection,
  depth and bucket rules, effective-stake curves, commitment maths — lives in policy, where
  it can be fixed.
- Cores MUST be formally specified and MUST have full invariant and fuzz coverage before
  deployment (see [Test cases](#test-cases)).

#### C3. `StakingCore` interface

Staking is the easier of the two cases and SHOULD be done first: its only funds-out
direction is already "pay `msg.sender`", so C2.1 is satisfiable without changing any user's
economics, and today's rug-resistance is preserved exactly rather than approximated.

```solidity
interface IStakingCore {
    // ---- user ----
    /// @notice Deposit BZZ. Credited to msg.sender. No policy call.
    function deposit(uint256 amount) external;

    /// @notice Withdraw up to `amount` of the caller's unlocked deposit. Pays msg.sender only.
    function withdraw(uint256 amount) external;

    /// @notice Permissionless exit (C2.6). Not pausable, ignores policy state.
    ///         Callable EXIT_DELAY blocks after requestExit().
    function requestExit() external;
    function exit() external;

    // ---- policy, bounded (C2.4) ----
    /// @notice Reduce a deposit. Burnt in place; never transferred out.
    ///         Reverts if per-node or per-epoch slash caps are exceeded.
    function slash(address node, uint256 amount) external;

    /// @notice Prevent withdraw() (but never exit()) for `until`.
    function lock(address node, uint64 until) external;

    // ---- views ----
    function depositOf(address node) external view returns (uint256);
    function totalDeposited() external view returns (uint256);
}
```

`StakingCore` MUST NOT store overlays, heights, committed stake, or effective stake, and
MUST NOT read `PriceOracle`. Those are per-branch, consensus-critical values, and belong in
`StakingPolicy` for a reason that matters at fork time: **overlay derivation is bound to the
wire protocol** (it mixes `NetworkId`), so it is exactly the kind of value that should be
redeployed with a fork, while deposits are exactly the kind that should not.

`StakingPolicy` SHOULD accept an immutable `predecessor` address and lazily inherit overlay
and height from it on first use, so that a fork requires no operator transaction at all.
Note that `Redistribution` requires a stake record older than `2 * ROUND_LENGTH` before
participation; inheriting predecessor state avoids re-triggering that delay, whereas a
fresh declaration would cost operators roughly two rounds (~25 minutes at
`ROUND_LENGTH = 152` on Gnosis).

#### C4. `PostageAccounting` interface

```solidity
interface IPostageAccounting {
    // ---- user ----
    /// @notice Fund a batch id. Amount is transferred in; credited to `owner`.
    function fund(bytes32 batchId, address owner, uint256 amount) external;

    /// @notice Add funds to an existing batch. Owner unchanged.
    function topUp(bytes32 batchId, uint256 amount) external;

    /// @notice Permissionless exit (C2.6). Pays batches[batchId].owner only.
    ///         May forfeit a fixed fraction to the pot (see C2.6).
    function refundBatch(bytes32 batchId) external;

    // ---- policy, bounded (C2.4) ----
    /// @notice Debit a batch and credit the pot. Reverts if the conservation
    ///         invariant (C2.2) or MAX_PRICE would be breached.
    function accrue(bytes32 batchId, uint256 amount) external;

    /// @notice Pay out to the single authorised redistributor. Capped per round (C2.4).
    ///         Destination is not a parameter.
    function claimPot(uint256 amount) external;

    // ---- redistributor pointer (C2.5, F4) ----
    function proposeRedistributor(address next) external;
    function executeRedistributor() external;

    // ---- views ----
    function balanceOf(bytes32 batchId) external view returns (uint256);
    function ownerOf(bytes32 batchId) external view returns (address);
    function pot() external view returns (uint256);
    function redistributor() external view returns (address);
}
```

`claimPot` takes an amount but not a destination. There is no `withdraw(address)`. The
redistributor pointer is singleton by construction rather than by role hygiene, which is
the direct fix for the v0.9.3 double-redistributor race.

Batch *identity and semantics* — bucket depth validity, immutability flags, minimum initial
balance, depth-increase rules — live in `PostagePolicy`. `PostageAccounting` records only
that a batch id is owned by an address and holds a balance. The expiry ordering structure
(today `HitchensOrderStatisticsTreeLib`) lives in policy; the core does not need it, because
under C2.2 it bounds pot growth by conservation rather than by recomputing expiry.

#### C5. Residual trust after Part 1

Stated explicitly so it can be argued with:

| Capability | Today | After Part 1 |
|---|---|---|
| Steal all staked BZZ | No (burn only) | No |
| Burn all staked BZZ | Yes (redistributor role) | No — capped per epoch (C2.4) |
| Steal the entire pot in one call | Yes (`withdraw(beneficiary)`) | No — no such primitive (C2.1) |
| Drain the pot over time | Yes | Bounded, visible, timelocked (C2.4, C2.5) |
| Create unbacked batch state | Yes (`copyBatch`) | No (C2.2) |
| Misdirect *future* rewards | Yes | Yes, after `POLICY_TIMELOCK`, announced |
| Close the user escape hatch | Yes (`PAUSER_ROLE`) | No (C2.6) |

The row that does not go away is the last-but-one: whoever controls policy can still bias
who wins the pot, which is an indirect claim on future revenue. **Custody separation protects
deposits, not rewards.** Bounding reward direction further would require freezing
redistribution verification itself, which conflicts directly with Part 2's requirement that
`Redistribution` be redeployed per fork. We consider the trade correct and name it rather
than paper over it.

### Part 2 — Fork migration

#### F0. Definitions

A **fork** of the Swarm network is a second network whose initial state is a clone of a
subset of the first's — canonically, of the stamp set. A **fork-migration** is a fork in
which the old branch is intended to be wound down. Every breaking change to the Swarm wire
protocol to date has been a fork-migration (*Forking Swarm*).

A **breaking wire release** is a client release whose peer-negotiated protocol version
differs from its predecessor's, such that a version mismatch causes disconnection. Because
mismatch causes disconnection, a breaking wire release always produces at least two disjoint
p2p networks.

#### F1. A new `Redistribution` per breaking wire release

Every breaking wire release MUST be accompanied by the deployment of a new `Redistribution`
contract, **even if its bytecode is unchanged**.

Rationale: contract identity, not the wire version, is what partitions the incentive game.
Without a new `Redistribution`, both branches play the same game with divergent views of the
stamp set — a negative-sum outcome in which stragglers claim a share of payments intended
for the new branch, upgraded nodes earn less, and honest nodes can be frozen for
disagreeing with a non-upgraded leader. This is the measured v2.8.0 failure mode.

`Redistribution` holds no state worth preserving, so this is close to free. It is the
cheapest recommendation in this SWIP and SHOULD be adopted as standing practice
independently of everything else here.

#### F2. Cutover signalling: timing on chain, addresses in the binary

A `Cutover` contract publishes the schedule:

```solidity
interface ICutover {
    struct Schedule {
        uint32 wireVersion;      // client protocol version this cutover activates
        uint64 activationBlock;  // MUST be a multiple of ROUND_LENGTH (F3)
        bytes32 manifest;        // hash of the release's address set
    }

    function schedule(uint32 wireVersion) external view returns (Schedule memory);
    function current() external view returns (Schedule memory);

    event CutoverScheduled(uint32 wireVersion, uint64 activationBlock, bytes32 manifest);
    event CutoverExecuted(uint32 wireVersion, uint64 atBlock);
}
```

Two normative rules govern its use.

**F2.1 — The signal carries timing; the binary carries addresses.** A client MUST NOT learn
a contract address from the chain and act on it. Contract addresses MUST be compiled into
the client release. The `Cutover` contract may tell a client *when* to switch; it MUST NOT
be able to tell it *where*. The `manifest` field is a hash the client checks against its
own compiled address set, and a mismatch MUST be a hard failure, not a warning.

This rule exists because the alternative is an automated fund-redirection trigger. A client
that reads a destination address from chain and then moves the operator's stake to it has
reproduced, inside the client, exactly the admin power this SWIP removes from the contracts.

**F2.2 — Schedules are event-driven, not height-hardcoded.** Clients MUST determine
activation by observing `Cutover` state, not by a height baked into the binary. A hardcoded
height fixes the date at release-engineering time; if the date must slip — a bug is found,
the multisig cannot assemble, the chain has an incident — every client in the field holds
the wrong height and an emergency release is required. A rescheduled `activationBlock` MUST
be re-announced at least `CUTOVER_NOTICE` blocks before the new activation.

#### F3. Round-aligned atomic cutover

`activationBlock` MUST satisfy `activationBlock % ROUND_LENGTH == 0`.

Cutover is not instantaneous with respect to the redistribution game. A round spans
`ROUND_LENGTH` blocks (152 at present) and is divided into commit, reveal and claim phases.
A cutover landing mid-round orphans nodes that have already committed: they lose their
reveal window and may be frozen for a phase violation they did not cause.

Therefore:

- The outgoing `Redistribution` MUST stop accepting new commits from the start of the round
  preceding `activationBlock`, so the final round drains through reveal and claim normally.
- The incoming `Redistribution` MUST accept commits from `activationBlock` onward.
- The authority change on `PostageAccounting` (F4) MUST execute at `activationBlock`.

"No gap" and "no orphaned round" are distinct properties. This SWIP requires both.

#### F4. Exactly one redistributor, by construction

`PostageAccounting` MUST authorise at most one redistributor address at any block. The
pointer changes only through `proposeRedistributor` / `executeRedistributor` under
`POLICY_TIMELOCK` (C2.5), and `claimPot` reverts for any caller that is not the current
pointer.

This replaces `REDISTRIBUTOR_ROLE` as an `AccessControl` role, under which multiple holders
are representable and were in fact simultaneously authorised in 2025. Singleton-ness becomes
a property of the type, not of operational discipline.

Cutover execution is therefore: `executeRedistributor()` on `PostageAccounting`, plus the
policy pointer update if policy changed, in a single transaction from the governing
multisig. It MUST be a single transaction. "Atomic" is not satisfied by several transactions
sent close together — the v0.9.3 incident is what several transactions close together looks
like.

#### F5. Old-branch wind-down

Immediately zeroing rewards on the old branch is correct for incentive alignment and wrong
for data availability: old-branch data remains retrievable only while old-branch nodes stay
online, which is precisely when they have stopped being paid.

Where a fork requires user-side action with a tail — a wire-protocol change, since batches
themselves now carry across — the schedule SHOULD include a wind-down window during which
the old `Redistribution` continues to pay at a reduced rate, decaying to zero. This is a
deliberate exception to "no overlap", and it is safe under F4 in a way it was not in 2025:
the two redistributors are authorised against *different* postage cores only if a postage
migration is happening at all, and in the normal case there is one core, one pointer, and
the wind-down is paid from a fixed, pre-funded allocation rather than from the live pot.

The residual pot in any retired core MUST have a defined destination. This SWIP does not
fix one; see [Open questions](#open-questions).

#### F6. Client requirements

A conforming client:

1. MUST compile in the full address set for each protocol version it supports, and the
   `manifest` hash for each.
2. MUST read `Cutover` for timing only, and MUST hard-fail on `manifest` mismatch (F2.1).
3. MUST switch the `Redistribution` address it uses at `activationBlock`, not when the
   operator restarts.
4. MUST NOT send any fund-moving transaction as an automated consequence of a chain signal.
   Under Part 1 no such transaction is required at cutover, which is the point.
5. SHOULD expose the pending cutover in its status API and log a warning when it is running a
   version whose cutover has passed.

#### F7. Relationship between the parts

Part 2 alone still requires stake migration at every fork, which is the ten-day outage. Part
1 alone leaves the fork boundary undefined, so wire-only forks keep commingling incentives.
Together:

- Deposits never move, so cutover involves no user or operator fund transaction (F6.4).
- `Redistribution` identity still changes per fork, so branches never share a game (F1).
- Batches carry across, so there is no batch migration and `copyBatch` can be retired.
- The interval "between release and pausing the old registry" collapses to zero, because
  there is nothing to pause and nothing to move.

## Rationale

**Why not proxies over the fund-holding contracts.** Covered in [Motivation](#motivation).
Briefly: a proxy over a vault is a custody grant; per-call registry verification is an
availability risk; and if the vault cannot be swapped, the anti-swap machinery is
unnecessary.

**Why not "always full redeploy".** *Forking Swarm*'s proposal is coherent but
expensive, and its cost is not bounded in the document. It requires a batch migration at
every breaking wire release, and it leaves batch migration undesigned. It also relies on an
incentive asymmetry that does not hold: operators follow money and will migrate stake to
keep earning, but a user who fails to migrate a batch loses availability they may not notice
until they need the data. Operators follow money; users follow nothing. Part 1 removes the
requirement rather than solving the coordination problem.

**Why the registry survives as a cutover signal.** The reviewer question on
[`storage-incentives#310`][pr310] — who benefits from an on-chain registry, and how does it
compare to publishing under ENS or on GitHub — has a straight answer: for *security* it adds
nothing, because the trust root is the client release process either way. For *coordination*
it adds something real, because it lets every client switch at the same block regardless of
when its operator restarted. F2 keeps the coordination and F2.1 removes the security
temptation.

**Why staking first.** It is the case where the target property is cleanest (funds already
only flow to `msg.sender`), it is the case where the objection to upgradeability was
strongest, and demonstrating a frozen core there earns the standing to freeze the postage
ledger afterwards.

**Why bounds rather than prohibitions.** A design in which policy has no authority at all
over funds cannot slash, cannot pay winners, and is therefore not an incentive system. The
achievable goal is not zero authority but *bounded, announced, visible* authority with a
usable exit. C2.4 through C2.6 are that goal made concrete.

**Alternatives considered and rejected.**

- *Immutable policy pointer in the core.* Strictly stronger, but then changing policy means
  a new core, which reintroduces migration and defeats the purpose.
- *External timelock contract owning the pointer.* Weaker than C2.5, because whoever can
  replace the timelock's owner can shorten the window. Self-enforcement in the core with an
  immutable constant is the point.
- *Governance vote on policy changes.* Orthogonal and compatible; this SWIP specifies the
  contract-level constraints that hold regardless of how the governing address is
  constituted.
- *Keeping the expiry tree in the core.* Rejected under C2.7: it is the most edge-case-heavy
  component and the one most likely to need a fix.

## Backwards compatibility

This is a breaking change to the contract suite and requires a coordinated release. It is
also, by design, intended to be the **last** such change that moves user funds.

**Two migrations, once.**

1. *Final stake migration.* Operators move deposits from `StakeRegistry` to `StakingCore`.
   This is the last time. It SHOULD be run under the F2/F3 protocol, and — unlike 2025 — the
   old registry MUST be paused at `activationBlock` rather than at an unrelated later date,
   so that no window exists in which an upgraded operator cannot earn.
2. *Final batch migration.* Batches move from `PostageStamp` to `PostageAccounting`. This is
   the last time. It is the harder of the two and SHOULD be user-driven wherever possible; if
   an admin-assisted path is used for the tail, that path MUST be time-limited by an
   immutable deadline in `PostageAccounting` after which it cannot be called, and MUST require
   a matching BZZ transfer so that C2.2 holds during migration. That last requirement is the
   specific defect in today's `copyBatch`.

**Retirement of `copyBatch`.** `PostageAccounting` MUST NOT include an unbacked
batch-creation function. After migration, `copyBatch` and `copyBatchBulk` cease to exist as
a capability.

**Client ABI.** Clients must learn a two-contract layout per subsystem: reads that are
consensus-critical (overlay, effective stake, batch validity) come from policy; balances and
deposits come from the core. Clients SHOULD read policy for anything that can change per
fork and core for anything that must not.

**Integrators.** Anything reading `PostageStamp.batches(...)` or `StakeRegistry.stakes(...)`
directly must be updated. A compatibility view contract MAY be deployed to preserve the
current read ABI; it MUST be read-only and MUST NOT be depended on by clients for
consensus-critical values.

## Test cases

Cores are unupgradeable, so their test burden is qualitatively different from ordinary
contract tests. The following are mandatory before any core deployment.

**Invariant tests (must hold after every call, under all orderings).**

- `sum(recorded claims) + pot <= token.balanceOf(core)` (C2.2).
- `totalDeposited - totalWithdrawn - totalSlashed == token.balanceOf(StakingCore)`.
- No execution path transfers to an address not derived from core state (C2.1) — enforced by
  a static check over the core's bytecode as well as by tests.
- No core function reaches an external call into the policy address (C2.3).

**Adversarial-policy tests.** Instantiate each core with a deliberately malicious policy
that attempts, at minimum: draining the pot in one call; slashing every node to zero;
claiming more than the per-round cap; accruing pot beyond conservation; blocking a user's
exit; setting a price above `MAX_PRICE`. Each MUST revert, and `exit()` MUST succeed
throughout.

**Exit tests.** `exit()` and `refundBatch()` MUST succeed while the policy is malicious,
while the policy address is zero, while a policy change is pending in the timelock, and — for
`StakingCore` — while the node is locked or frozen by policy.

**Timelock tests.** A policy or redistributor change MUST NOT take effect before
`POLICY_TIMELOCK`; the pending change MUST be readable throughout the window.

**Cutover tests.** A cutover at a round boundary MUST NOT orphan a committed node (F3); a
cutover proposed off-boundary MUST revert; the old redistributor MUST reject commits in the
final round and MUST still accept reveals and claims for the round already committed; a
`manifest` mismatch MUST cause client hard-failure.

**Fuzz and differential.** Fuzz the conservation invariant across randomised sequences of
deposit, top-up, accrue, claim, slash, withdraw and exit. Differentially test
`PostagePolicy` accrual against the current `PostageStamp` expiry logic over historical
batch data, to confirm the split preserves today's accounting.

## Implementation

Staged so that each stage is independently valuable and independently revertible.

| Stage | Content | Depends on |
|---|---|---|
| 1 | Surgical `Redistribution` redeployment with security fixes; round-aligned atomic cutover; single redistributor; stake and batches untouched | — |
| 2 | F1 adopted as standing practice: new `Redistribution` on every breaking wire release | — |
| 3 | `Cutover` contract and client support (F2, F3, F6). `storage-incentives#310` reduced to a plain release registry; guarded proxy and `pinnedExecute` dropped | 2 |
| 4 | `StakingCore` + `StakingPolicy`. Final stake migration | 3 |
| 5 | `PostageAccounting` + `PostagePolicy`. Final batch migration. `copyBatch` retired | 4 |
| 6 | `POLICY_TIMELOCK` extended; governing multisig scope reduced to policy pointers only | 5 |

Stage 1 addresses measured harm and is the immediate next upgrade. Stage 2 is a process
decision available today at no cost. Stages 4 and 5 are where the custody property lands.
After stage 5, surgical redeployment and the absence of custody admin powers coexist — the
two things currently treated as mutually exclusive.

## Open questions

1. **Parameter values.** `POLICY_TIMELOCK` (suggested: 14 days in blocks), `EXIT_DELAY`
   (suggested: aligned with the current freeze horizon), `MAX_SLASH_PER_EPOCH`,
   `MAX_POT_FRACTION_PER_ROUND`, `MAX_PRICE`, `CUTOVER_NOTICE`. These are immutable once
   deployed and so need their own analysis.
2. **Postage exit economics.** What forfeit fraction or minimum batch age makes
   `refundBatch` non-abusable without making it useless as an escape hatch?
3. **Stranded pot.** Where does the residual pot in a retired core go, given that by
   construction no one can direct it to an arbitrary address?
4. **Wind-down funding.** Should the F5 reduced-rate window be pre-funded from the treasury,
   or is a fixed fraction of the live pot acceptable?
5. **Tail of the final batch migration.** Is a deadline-limited, deposit-matched
   admin-assisted path acceptable, or must the final migration be fully user-driven even at
   the cost of abandoning some batches?
6. **Multi-client discipline.** F1–F3 assume every client implements cutover identically.
   What is the conformance mechanism if a second client exists?

## References

- [`ethersphere/storage-incentives#310`][pr310] — Versioned Registry Router + Upgradeable
  Proxies for All Core Contracts, and the review discussion that motivated this SWIP.
- *Forking Swarm: A migration guide* — Andrew Macpherson, Shtuka Research (presentation,
  2026). Source of the fork framing, the v2.8.0 dissent measurements, and the
  v0.9.3/v0.9.4 case study. Not yet published at a stable URL; to be linked or mirrored
  under `SWIPs/assets/swip-67/` with the author's consent.
- Deployed contracts referenced throughout: `src/PostageStamp.sol`, `src/Staking.sol`,
  `src/Redistribution.sol` in `ethersphere/storage-incentives`.

[pr310]: https://github.com/ethersphere/storage-incentives/pull/310

## Acknowledgements

Part 2 is substantially derived from Andrew Macpherson's *Forking Swarm* presentation
(Shtuka Research) and from his review of [`storage-incentives#310`][pr310]. Specifically
his: the fork and fork-migration framing (F0); the argument that contract identity rather
than wire version is what partitions the incentive game, and hence F1; the v2.8.0 dissent
measurements and the v0.9.3/v0.9.4 case study; the assessment that upgradeable staking is a
strict increase in attack surface, from burn to steal; and the observation that the interval
between a client release and the pausing of the old stake registry is dead time for
upgraded operators.

Note that this SWIP departs from *Forking Swarm* on one conclusion: that document argues
that phasing out admin powers makes surgical redeployment impossible and therefore requires
full-suite redeployment with batch and stake migration at every fork. Part 1 argues the
coupling that makes this true is removable, and Part 2 is adapted accordingly. Co-authorship
is listed on the strength of the derived material; @awmacpherson should feel free to ask for
his name to be removed if he does not want to be associated with that departure.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
