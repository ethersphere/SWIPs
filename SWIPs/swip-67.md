---
SWIP: 67
title: Custody separation
author: Cardinal (@0xCardiE)
discussions-to: https://github.com/ethersphere/SWIPs/pull/108
status: Draft
type: Standards Track
category: Core
created: 2026-09-07
---

<!-- Separates custody from policy so contract logic can be replaced without moving user
funds. Bee keeps shipping addresses in the binary. Pointers flip at a round boundary. -->

## Contents

- [Simple Summary](#simple-summary) · [Abstract](#abstract)
- [Motivation](#motivation)
- [Rationale](#rationale)
- [Specification](#specification)
  - [Pointers and timelocks](#pointers-and-timelocks)
  - [Redistribution](#redistribution)
  - [Staking](#staking)
  - [PostageStamp](#postagestamp)
  - [PriceOracle](#priceoracle)
  - [Releases](#releases)
- [Test cases](#test-cases) · [Implementation](#implementation)

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
deposits, is never upgraded, and enforces its own accounting invariants. The policy holds
the rules, is freely replaceable, and can never name a payment destination.

`Redistribution` and `PriceOracle` hold no user deposits, so they are not split. They stay
replaceable and are redeployed as-is. A new `Redistribution` whenever the on-chain game
must not be shared — a breaking Bee release (even if the Solidity is unchanged) or a
change to Redistribution itself. A new `PriceOracle` when its adjustment rules change.

It then specifies how those pointers flip after a core-enforced timelock — the
redistributor only at a round start — so a protocol upgrade stops being a fund movement.
Bee keeps shipping contract addresses in the binary, as it does today.

## Abstract

The suite is treated contract by contract.

- **`Redistribution`** is not split. A new contract is deployed whenever the *game*
  must not be shared — a breaking Bee release (old and new Bee nodes cannot connect, so
  they must not share one on-chain game) or a Redistribution code change. Same bytecode
  still gets a new address on a breaking Bee release. The redistributor pointer flips at
  a round boundary; at most one redistributor is authorised at any block.
- **`StakeRegistry`** splits into `StakingCore` (BZZ, the #309 queue, freeze, payouts)
  and `StakingPolicy` (overlay derivation, height / `MIN_STAKE`, eligibility views). The
  staking *lifecycle* is
  [storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309)
  (queued deposit / top-up / height / overlay / withdraw / exit), not a second unbonding
  design. Operators migrate stake once, then deposits stay put across later upgrades.
- **`PostageStamp`** splits into `PostageAccounting` (balances, accumulator, pot, expiry
  ordering) and `PostagePolicy` (admissibility, depth rules, price submission). Batches
  are seeded once, treasury-matched; after that they carry across later upgrades.
- **`PriceOracle`** is not split. It is redeployed when adjustment rules change, and
  submits prices through `PostagePolicy` into the core's bounded `setPrice`.

Cores hold all user BZZ. No core function transfers to a caller-supplied address. Pointers
change only after a core-enforced timelock. There is no admin pause on `refundBatch` or a
matured staking payout; a Redistribution freeze can still delay the latter. Contract
addresses stay compiled into Bee, as they are today.

## Motivation

State and logic live in the same contract, so replacing logic means replacing state;
replacing state means a migration; avoiding the migration means giving an admin a shortcut
over state — which is a power over funds. We oscillate between two bad options:

1. **Use the admin shortcut.** Cheap, but the admin can steal the pot and burn all stake.
2. **Do a full redeployment and migrate everything.** Rug-resistant, but every logic change
   becomes a fund movement for every user and operator, and no batch migration has ever
   been completed without admin-driven cloning.

That deadlock is a consequence of the coupling, not of the threat model. Break the
coupling and both options improve at once.

**Where the money can move today.**
`PostageStamp.withdraw(address beneficiary)` is gated on `REDISTRIBUTOR_ROLE` and sends
the whole pot to a caller-supplied address. That role is an OpenZeppelin `AccessControl`
role, so any number of addresses can hold it at once. `copyBatch` / `copyBatchBulk` mint
batch state without transferring BZZ in. `PostageStamp` has **no path that returns an
unexpired batch deposit** — the only outflow is `withdraw`, and it moves the pot, never
remaining balances. That is why every batch migration to date used `copyBatch`.

`StakeRegistry` is rug-resistant: BZZ only goes back to `msg.sender`, and slashing burns
in place. Making it upgradeable in the ordinary sense would be a strict increase in
attack surface, from burn to steal. Its escape hatch, `migrateStake()`, is `whenPaused`,
and `pause()` requires `DEFAULT_ADMIN_ROLE` — so against the admin it is not an escape
hatch.

Custody separation removes the on-chain cost of a migration. It does not make old and new
Bee nodes share chunks: after a breaking Bee release they cannot peer, so bucket counters
and local chunk state stay on each network. On-chain batches carry across; that local
state does not.

## Rationale

Upgradeable proxies over fund-holding contracts are rejected. A proxy admin can steal
the funds. If deposits live in a contract that cannot be swapped, that event is no
longer a fund-loss event. Bee already compiles addresses into the binary; operators
upgrade Bee, governance flips the pointer at a round boundary, and anyone still on the
old binary stops earning.

Full-suite redeployment at every breaking Bee release is rejected for the same reason the
split exists.
It requires a batch migration every time, leaves that migration undesigned, and relies
on an incentive that does not hold: operators move stake to keep earning, but a user who
fails to move a batch loses availability they may not notice. After the two one-time
migrations in this SWIP, later upgrades replace policy and `Redistribution` only.

An immutable policy pointer is stronger and useless: changing policy would mean a new
core, which is another migration. An external timelock is weaker: whoever replaces its
owner shortens the window. Putting expiry ordering in postage policy would make
conservation depend on policy honesty. User-driven `fund()` as the primary batch
migration is rejected because the backing BZZ is locked in `PostageStamp`.

A policy with no authority over funds cannot slash and cannot pay winners. The
achievable goal is bounded, announced, visible authority with a usable exit. Creation
is policy-gated because admissibility changes per Bee release; exits are not, because a
hostile policy must not trap existing funds.

## Specification

Shared rules for the two cores (`StakingCore`, `PostageAccounting`):

- No proxy, no `delegatecall`.
- No transfer to a caller-supplied address. Destinations come from core state:
  `refundBatch` pays the recorded owner; `withdraw`/`exit` pay `msg.sender`; `claimPot`
  pays the single authorised redistributor.
- Conservation is checked incrementally on every state-changing call:
  `pot + sum(remaining claims) <= balance` on postage; `totalDeposited - totalWithdrawn
  <= balance` on staking (slashed BZZ stays in the contract).
- Calls go policy → core only. The core never reads policy.
- Value-moving primitives policy can trigger are rate-limited by immutable core windows:
  `claimPot`, `slash`, `setPrice`.
- Policy and redistributor pointers change only after `POLICY_TIMELOCK`, enforced by the
  core; a pending change is cancellable.
- `refundBatch` has no role check, no pause, and ignores policy locks. Staking
  payout is [storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309):
  a matured `withdraw` / `exit` pays `msg.sender` via `applyUpdates`. Redistribution freeze
  can delay that payout (`FrozenWithdrawal`). An admin pause or a hostile policy cannot.

A core with a timelocked pointer is not admin-free. The claim is narrower: no privileged
operation can move a user's deposit, and every privileged operation is announced in
advance with an exit window.

### Pointers and timelocks

Two clocks, two jobs. Do not mix them.

**`POLICY_TIMELOCK` is on the cores.** `StakingCore` has one pointer: its `StakingPolicy`.
`PostageAccounting` has two: its `PostagePolicy` and its redistributor (`Redistribution`).
`Redistribution` and `PriceOracle` have neither a pointer nor a timelock; they are
replaced by deploying a new contract and, where needed, flipping a pointer *on a core*.

The governing multisig is the only address that may propose or cancel a pointer change.
The core enforces the delay itself with an immutable block count. Suggested:
`POLICY_TIMELOCK` = 14 days in blocks. The exact value, and the other immutables
(`WAIT_*` from [storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309),
`EXECUTION_WINDOW`, slash and pot windows, `MAX_PRICE` /
`MAX_PRICE_CHANGE_PER_UPDATE`, `refundBatch` forfeit), are decided before the cores
are deployed. No external timelock contract.

There is **no stored `activationBlock`.** Picking the flip date at propose time is what
goes wrong when Bee slips: you miss a one-round window and have to propose again, another
full timelock. The date is chosen at **execute** time, once the binary is actually out.

Sequence:

1. **Propose.** Multisig calls `proposePolicy(next)` or `proposeRedistributor(next)`.
   The core stores `next` and `proposeBlock`, and emits an event. Nothing has switched
   yet. The old `Redistribution` keeps paying.
2. **Wait.** For `POLICY_TIMELOCK` blocks, users who dislike `next` can `exit` or
   `refundBatch`. The multisig MAY cancel during this window; it MUST NOT shorten the
   delay. If Bee is late, **do nothing** — the old game continues, or pause it and
   accept a gap. That gap already happens today. It is not a reason to re-propose.
3. **Execute**, after the delay, when Bee is out. `executePolicy()` has no extra clock.
   `executeRedistributor()` also requires the current block to be in the opening of a
   round: `block.number % ROUND_LENGTH < EXECUTION_WINDOW`. `ROUND_LENGTH` is an
   immutable on `PostageAccounting` (152 today). Any later round start is valid; there
   is no missed date. A mid-round execute reverts, so committed nodes are not orphaned.
   Anyone MAY execute once those checks pass; only the proposed `next` is installed.

Do **not** let the multisig `setRedistributor` in one shot with no propose step. That
drops the exit window, which is the whole point of the timelock. Round alignment
without a pre-committed block is enough to avoid a mid-round flip; a gap with nobody
playing is acceptable.

Until `PostageAccounting` exists, stage 1 honours the same rule by operational
discipline: one `REDISTRIBUTOR_ROLE`, flipped at a round start after Bee is out.

**`WAIT_WITHDRAWAL` is not a governance timelock.** It is the unbonding wait in
[storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309)
before a queued `withdraw` or `exit` can pay `msg.sender`. The staker starts it, not the
multisig. Freeze from Redistribution can delay that payout further (same as #309), so
exit cannot dodge an in-flight penalty. `refundBatch` has no unbonding delay; the forfeit
fraction is the brake.

Worked order for a breaking Bee release:

1. Deploy the new `Redistribution` (and new policy contracts if they change).
2. Multisig `proposeRedistributor(newRedistribution)` (and `proposePolicy` if needed).
3. Ship Bee. Operators upgrade during the timelock. If the release slips, wait; the
   old pointer stays live (or pause the old game).
4. After the timelock, at the next round start, `executeRedistributor` (and
   `executePolicy`). Non-upgraded nodes stop earning.

```solidity
// On both cores
function proposePolicy(address next) external;
function cancelPolicy() external;
function executePolicy() external;

// PostageAccounting only
function proposeRedistributor(address next) external;
function cancelRedistributor() external;
function executeRedistributor() external;
```

### Redistribution

Not split. It holds no user deposits.

**State.** Commits, reveals, round counters and the last winner. None of it is worth
preserving across a release. Overlay, stake and freeze data live in staking; postage
balances live in postage. Redistribution only *reads* those and *calls* `claimPot` /
`slash` / `freezeDeposit`.

**How it is updated.** Redeploy when the incentive game must not be shared. Two triggers:

1. **Breaking Bee release (Type A).** A Bee version whose nodes cannot connect to the
   previous version. The p2p network splits in two. Those two networks see different
   chunks and reserve commitments, but if they keep calling the **same** `Redistribution`
   address they play one on-chain commit / reveal / claim game. The contract cannot tell
   the two networks apart. Divergent reveals look like lying: old-version nodes can win
   the pot, upgraded nodes get frozen for "disagreeing." A new `Redistribution` address
   is what separates the games. The Solidity can be identical — what changed is Bee, not
   the contract. Deploy a new copy, point clients and the postage redistributor pointer
   at it.
2. **`Redistribution` itself changed (Type A or B).** A bugfix, a new claim check, a
   different round length. There is no upgrade path, so that is also a new deployment.
   If Bee's p2p protocol is unchanged this is Type B: operators run the Bee that contains
   the new address, then the pointer flips. Anyone still on the old binary stops earning.

Do **not** redeploy `Redistribution` for a postage-policy tweak, an oracle adjustment, or
a staking-policy change that does not change how commits are built or verified. Those
replace the other contracts; the game address stays if the game is the same.

**Pointer flip.** The postage core holds the only redistributor pointer. See
[Pointers and timelocks](#pointers-and-timelocks).
Incoming `Redistribution` accepts commits once it is the authorised pointer. `claimPot`
reverts for any caller that is not the current pointer.

If the previous Bee network still needs to pay for data availability, the outgoing
`Redistribution` MAY keep paying at a reduced, decaying rate. That pot MUST be moved
into the outgoing contract **before** the pointer flips. After that it is never the
authorised pointer again.

**Migration.** None. There is no user state to move. Operators run the Bee release that
contains the new address. Until `PostageAccounting` exists, singleton authority is
operational (one `REDISTRIBUTOR_ROLE` holder); the type-level guarantee lands with the
postage split.

### Staking

Split. `StakeRegistry` becomes `StakingCore` + `StakingPolicy`.

Today's registry has surplus `withdrawFromStake` and a paused `migrateStake`. It has no
real unstake. Do not invent a second one (`requestExit` / `EXIT_DELAY` /
pre-registration). The staking *lifecycle* is
[storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309):
one queued update per overlay (deposit, top-up, height, overlay, **withdraw**, **exit**),
`WAIT_BASE` before a new deposit can play, `WAIT_OVERLAY_CHANGE` /
`WAIT_WITHDRAWAL` (~28 days on production) before those updates apply, freeze that stays
on the account after unstake, and effective stake = balance unless frozen, else zero.
Views preview the post-apply state; BZZ moves only in `applyUpdates`.

#309 is still one contract. This SWIP only splits that contract. The queue mixes
withdrawals with overlay and height changes, so the queue, `WAIT_*`, `freezeUntilBlock`,
and BZZ stay together in the core. Otherwise a hostile policy can refuse `applyUpdates`
and trap funds, which is the same hatch #309 still has via `pause` / `migrateStake`.

| Stays in `StakingCore` (frozen, holds BZZ) | Moves to `StakingPolicy` (replaceable) |
|---|---|
| Per-account BZZ, the #309 update queue, `WAIT_*`, `freezeUntilBlock`, `applyUpdates` payouts, slash | Overlay derivation (`NetworkId`), height / `MIN_STAKE` rules, effective-stake and lookahead views Redistribution and Bee call |

`StakingCore` MUST NOT read `PriceOracle`. Overlay mixes `NetworkId`, so derivation is
policy and is replaced with a breaking Bee release; deposits are not. The core stores the
overlay *bytes* and height as #309 does, so there is still one FIFO. Policy supplies
derivation and the replaceable view API.

```solidity
interface IStakingCore {
    function createDeposit(bytes32 overlay, uint256 amount, uint8 height) external returns (uint64);
    function addTokens(uint256 amount) external returns (uint64);
    function increaseHeight(uint8 height) external returns (uint64);
    function changeOverlay(bytes32 overlay) external returns (uint64);
    function withdraw(uint256 amount) external returns (uint64);
    function exit() external returns (uint64);
    function applyUpdates(address owner) external;
    function slash(address account, uint256 amount) external;
    function freezeDeposit(address account, uint256 time) external;
    function proposePolicy(address next) external;
    function cancelPolicy() external;
    function executePolicy() external;
    function depositOf(address account) external view returns (uint256);
    function totalDeposited() external view returns (uint256);
}
```

Bee still speaks #309 (`nonce` in, `effectiveFromRound` out). Overlay derivation and
`MIN_STAKE` checks live on the policy, which forwards into the core, so the core never
reads policy. `addTokens`, `exit`, and `applyUpdates` are permissionless. `applyUpdates`
pays the owner only, once `WAIT_WITHDRAWAL` has elapsed, unless `FrozenWithdrawal`.
`freezeDeposit` is `onlyRedistributor` and monotonic; it survives exit on this core
(same as #309). `slash` is `onlyRedistributor` and burns in place. `WAIT_WITHDRAWAL`
MUST be at least the longest Redistribution freeze, or a queued exit lands before the
penalty.

No `pause` on the core. #309's `whenNotPaused` on `withdraw` / `exit` is the admin hatch
this split removes.

**Eligibility.** #309's `WAIT_BASE` after `createDeposit`. No parallel
`firstDepositBlock` / pre-registration clock. Overlay change uses `WAIT_OVERLAY_CHANGE`
and does not reset the deposit. Height still scales `MIN_STAKE`; the token amount in the
core is deposited BZZ, not a committed/potential pair.

**Accounts and nodes.** Deposits are per account. One account may back several nodes
only if policy admits that; summed usable stake MUST NOT exceed the account's deposit.
A slash reduces the account, and therefore every overlay it backs.

`StakingPolicy` SHOULD take an immutable `predecessor` and lazily inherit overlay and
height on first use, so a later upgrade needs no operator transaction.

**Migration (once).** Ship or adopt #309 on the current registry first if that lifecycle
is not live. `migrateStake` (paused in #309, used while paused) is the one jump onto
`StakingCore`. The old registry is paused for that jump, not kept as an admin path on
the core. After this, stake does not move again: later upgrades only replace
`StakingPolicy`. Operators who skip the jump unstake on the old registry with #309's
`withdraw` / `exit`, or take that one-shot `migrateStake` if the registry is being
retired.

**After the split.** Policy-pointer change on `StakingCore` as in
[Pointers and timelocks](#pointers-and-timelocks).
The #309 enqueue / `applyUpdates` ABI is what Bee talks to for deposits and payouts.

### PostageStamp

Split. `PostageStamp` becomes `PostageAccounting` + `PostagePolicy`.

| Stays in `PostageAccounting` (frozen, holds BZZ) | Moves to `PostagePolicy` (replaceable) |
|---|---|
| Batch ownership, depth, normalised balance, outpayment accumulator, `validChunkCount`, expiry ordering, pot | Batch admissibility, bucket-depth rules, minimum balances, price submission |

Depth and the expiry ordering stay in the core because conservation needs them. Pot
accrual is the same identity as today's `expireLimited`: expired batches contribute
`batchSize * (normalisedBalance - lastExpiryBalance)`; live chunks contribute
`validChunkCount * (currentTotalOutPayment() - lastExpiryBalance)`. Live-chunk accrual
MUST NOT settle while an expired batch is still counted — which is why the core, not
policy, owns the minimum-balance index. A policy-side accumulator would rebase every
batch on every policy replacement.

The outpayment model is frozen in the core: linear per-block accrual against a per-chunk
normalised balance. A later pricing model is not a policy change and is not solved here;
it needs a new core.

```solidity
interface IPostageAccounting {
    function fund(
        address originator, bytes32 nonce, address owner,
        uint8 depth, uint256 amountPerChunk
    ) external returns (bytes32 batchId);
    function resize(bytes32 batchId, uint8 newDepth) external;
    function setPrice(uint256 price) external;
    function claimPot(uint256 amount) external;
    function topUp(bytes32 batchId, uint256 amountPerChunk) external;
    function refundBatch(bytes32 batchId) external;
    function expire(bytes32[] calldata batchIds) external;
    function proposePolicy(address next) external;
    function cancelPolicy() external;
    function executePolicy() external;
    function proposeRedistributor(address next) external;
    function cancelRedistributor() external;
    function executeRedistributor() external;
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

There is no `withdraw(address)` and no unbacked creation path.

`fund` and `resize` are policy-gated (admissibility). A dead policy can block new
batches, never `topUp`, `refundBatch`, `expire`, or conservation. New ids derive from
`(originator, nonce)`, same binding as today. Arbitrary ids exist only as genesis-seeded
state; after sealing there is no such path.

`claimPot(amount)` pays the authorised redistributor, not a caller-supplied address, and
is capped per window. The cap limits *acceleration*; the honest game already pays the
whole pot each round. Protection against a hostile redistributor is the timelock plus
`refundBatch`.

`refundBatch` pays the recorded owner **less than** remaining balance. The difference is
a forfeit to the pot — the owner can take funds out, just a bit less, to cover leftover
pot operation and remaining availability. There is no minimum batch age. The forfeit
fraction is an immutable, chosen before deployment. Nodes treat a refund as batch
invalidation, same as expiry. Introducing `refundBatch` is Type A: stamp validity is
consensus-adjacent.

**Migration (once), treasury-matched genesis.** `PostageStamp` cannot release unexpired
deposits, so the new core is seeded and separately backed:

1. When the new core goes live, `PostageStamp` is paused (`createBatch`, `topUp`,
   `increaseDepth` freeze; expiry and `withdraw` continue).
2. `PostageAccounting` is deployed in a genesis phase. The deployer seeds the batch set
   as of that block. Matching BZZ is topped up on the new core by the operators of the
   migration (not a user-by-user movement).
3. Genesis is sealed in the same ceremony. Until sealed, no other call is accepted;
   after sealing, no seeding path exists.
4. After the old contract is stopped, remaining BZZ is withdrawn from it
   (`withdraw` with the migration operators as beneficiary) — the final announced use of
   that primitive. That withdraw, plus the top-up of the new core, is the float. There
   is no open reimbursement-tail problem.

After this, batches do not migrate again. Later upgrades only replace `PostagePolicy` and
`Redistribution`.

**After the split.** Redistributor and policy pointers as in
[Pointers and timelocks](#pointers-and-timelocks).
Balance reads never change ABI.

**Residual trust.** Deposits cannot be stolen or flash-drained. A hostile policy can
still, after the timelock, claim the pot at up to the honest rate and bias who wins.
Custody separation protects deposits, not rewards.

### PriceOracle

Not split. It holds no BZZ and no user state.

**State.** Current price, last adjusted round, redundancy targets, `changeRate` steps.
All of it is replaceable. The postage core stores `lastPrice` and the accumulator; the
oracle does not.

**How it is updated.** Redeployed when adjustment rules change (the rate table, the
redundancy target, the pause behaviour). Ship the new address in Bee; flip nothing on
the postage core except through the existing `setPrice` path. Type A only if a
consensus-critical consumer would need a runtime branch.

Price submission is `PriceOracle` → `PostagePolicy` → `PostageAccounting.setPrice`. The
core enforces `price <= MAX_PRICE` and a maximum step from `lastPrice`. Those bounds
MUST be compatible with the oracle's own steps, or honest adjustments revert.

**Migration.** None. Operators run the Bee release that contains the new oracle
address. In-flight postage balances are unaffected: they are denominated in the core
accumulator, not in the oracle.

### Releases

Bee ships the current addresses and ABIs in the binary, as it does today. Operators
switch by running that Bee. Governance proposes pointer changes on the cores, then
executes them after `POLICY_TIMELOCK`. The redistributor pointer may execute only at a
round start, whichever round comes after Bee is out. Details:
[Pointers and timelocks](#pointers-and-timelocks).

A **breaking Bee release (Type A)** is a Bee version whose nodes cannot connect to the
previous version. Ship a new `Redistribution` in that binary. Non-upgraded nodes stop
earning, by design. Required whenever a runtime branch would appear in reserve sampling,
commitment hashing, overlay derivation, eligibility, or stamp validity (including
`refundBatch`).

A **contract-only release (Type B)** does not change Bee's p2p protocol. Still ship the
new addresses in Bee; still flip the pointer at a round start after the timelock. A node that has not
upgraded is calling the retired address and stops earning once the pointer has moved.

Clients MUST NOT send a fund-moving transaction as an automated consequence of an
upgrade or a chain event.

## Test cases

Mandatory before any core deployment.

- Conservation after every call, including `resize`, `refundBatch`, expiry and price
  changes. Differentially check postage pot accrual against today's `expireLimited`.
- No transfer to an address not derived from core state (static check on bytecode).
- No core call into the policy address.
- Malicious policy: flash-drain, unbounded slash, over-claim, unbacked fund, value-inflating
  resize, blocked exit, over-max price. All revert; a matured staking `applyUpdates`
  and `refundBatch` still succeed (including policy = 0 and a pending pointer change).
  `FrozenWithdrawal` delays a due withdraw/exit until the redistributor freeze ends, then
  payout succeeds.
- Genesis: seeding without matching BZZ reverts; any call before seal reverts; seeding
  after seal reverts from every role; conservation holds at the first open block.
- Pointer changes cannot execute before `POLICY_TIMELOCK`. Redistributor execute
  additionally reverts unless the current block is in the opening of a round.
  Cancellation works only before execution.
- A pointer flip off a round boundary reverts; a boundary-aligned flip does not orphan
  a commit.
- Policy replacement does not change `currentTotalOutPayment` or remaining balances.
- A deposit is eligible after `WAIT_BASE`; overlay change after `WAIT_OVERLAY_CHANGE`;
  withdraw/exit payout after `WAIT_WITHDRAWAL` and not while frozen.
- Fuzz randomised sequences of deposit, fund, top-up, resize, price, expire, claim,
  slash, refund, withdraw and exit.

## Implementation

Each stage is independently valuable and independently revertible.

| Stage | Content | Depends on |
|---|---|---|
| 1 | New `Redistribution`; round-aligned pointer flip; one redistributor by operational discipline | — |
| 2 | New `Redistribution` on every breaking Bee release, as standing practice | — |
| 3 | Adopt [storage-incentives#309](https://github.com/ethersphere/storage-incentives/pull/309) if not live, then `StakingCore` + `StakingPolicy`. Final stake migration. No pause on the core | 2 |
| 4 | `PostageAccounting` + `PostagePolicy`. Treasury-matched genesis | 3 |
| 5 | Multisig scope reduced to policy and redistributor pointers | 4 |

`PriceOracle` has no dedicated stage: redeploy it with the postage or redistribution
release that needs the new adjustment rules.

After stage 4, surgical redeployment and the absence of admin power over deposits
coexist.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
