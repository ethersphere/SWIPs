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
  - [Redistribution](#redistribution)
  - [Staking](#staking)
  - [PostageStamp](#postagestamp)
  - [PriceOracle](#priceoracle)
  - [Cutover protocol](#cutover-protocol)
- [Rationale](#rationale)
- [Test cases](#test-cases) · [Implementation](#implementation) · [Open questions](#open-questions)

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
replaceable and are redeployed as-is. A new `Redistribution` whenever the on-chain game
must not be shared — a breaking Bee release (even if the Solidity is unchanged) or a
change to Redistribution itself. A new `PriceOracle` when its adjustment rules change.

It then specifies the **cutover protocol** — how clients switch to a new policy and a new
`Redistribution` at a round boundary, so a protocol upgrade stops being a fund movement.

## Abstract

The suite is treated contract by contract.

- **`Redistribution`** is not split. A new contract is deployed whenever the *game*
  must not be shared — a breaking Bee release (old and new Bee nodes cannot connect, so
  they must not share one on-chain game) or a Redistribution code change. Same bytecode
  still gets a new address on a breaking Bee release. Cutover lands on a round boundary;
  at most one redistributor is authorised at any block.
- **`StakeRegistry`** splits into `StakingCore` (deposits, exits) and `StakingPolicy`
  (overlay, height, effective stake, slash/freeze rules). Operators migrate stake once,
  then deposits stay put across later cutovers.
- **`PostageStamp`** splits into `PostageAccounting` (balances, accumulator, pot, expiry
  ordering) and `PostagePolicy` (admissibility, depth rules, price submission). Batches
  are seeded once, treasury-matched; after that they carry across later cutovers.
- **`PriceOracle`** is not split. It is redeployed when adjustment rules change, and
  submits prices through `PostagePolicy` into the core's bounded `setPrice`.

Cores hold all user BZZ. No core function transfers to a caller-supplied address. Pointers
change only after a core-enforced timelock. Exits cannot be paused. A `Cutover` contract
publishes *timing only*; contract addresses are compiled into the client.

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
- `exit` / `refundBatch` have no role check, no pause, and ignore policy locks.

A core with a timelocked pointer is not admin-free. The claim is narrower: no privileged
operation can move a user's deposit, and every privileged operation is announced in
advance with an exit window.

### Redistribution

Not split. It holds no user deposits.

**State.** Commits, reveals, round counters and the last winner. None of it is worth
preserving across a release. Overlay, stake and freeze data live in staking; postage
balances live in postage. Redistribution only *reads* those and *calls* `claimPot` /
`slash` / `lock`.

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
   If Bee's p2p protocol is unchanged this is Type B: operators already running a release
   with both addresses keep earning across cutover.

Do **not** redeploy `Redistribution` for a postage-policy tweak, an oracle adjustment, or
a staking-policy change that does not change how commits are built or verified. Those
replace the other contracts; the game address stays if the game is the same.

**Cutover.** Incoming `Redistribution` accepts commits from `activationBlock` onward.
The postage core authorises at most one redistributor address at a time. The pointer
moves through `proposeRedistributor` / `executeRedistributor` under the timelock and
only inside `[activationBlock, activationBlock + EXECUTION_WINDOW)`. Until execution,
the outgoing contract remains authorised, so a late execution shortens the first new
round rather than orphaning a committed node. `claimPot` reverts for any other caller.

If the previous Bee network still needs to pay for data availability, the outgoing
`Redistribution` MAY keep paying at a reduced, decaying rate. That pot MUST be moved
into the outgoing contract **before** cutover. After cutover it is never the authorised
pointer again.

**Migration.** None. There is no user state to move. Clients switch the address they
call at `activationBlock`. Until `PostageAccounting` exists, singleton authority is
operational (one `REDISTRIBUTOR_ROLE` holder); the type-level guarantee lands with the
postage split.

### Staking

Split. `StakeRegistry` becomes `StakingCore` + `StakingPolicy`.

| Stays in `StakingCore` (frozen, holds BZZ) | Moves to `StakingPolicy` (replaceable) |
|---|---|
| Per-account deposit, `firstDepositBlock`, withdrawal and exit accounting | Overlay derivation, height, committed stake, effective stake, freeze and slash rules |

`StakingCore` MUST NOT store overlays, heights, committed stake or effective stake, and
MUST NOT read `PriceOracle`. Overlay mixes `NetworkId`, so it is redeployed with a
breaking Bee release; deposits are not.

```solidity
interface IStakingCore {
    function deposit(uint256 amount) external;
    function withdraw(uint256 amount) external;
    function requestExit() external;
    function exit() external;
    function slash(address account, uint256 amount) external;
    function lock(address account, uint64 until) external;
    function depositOf(address account) external view returns (uint256);
    function firstDepositBlock(address account) external view returns (uint64);
    function totalDeposited() external view returns (uint256);
}
```

`deposit` credits `msg.sender` and records `firstDepositBlock` on the first credit. No
policy call. `withdraw` pays `msg.sender` only, and `lock` can block it. `exit` cannot
be locked, paused, or routed through policy; it is callable `EXIT_DELAY` blocks after
`requestExit()`. `slash` burns in place and is capped per window.

`exit()` is withdrawable stake. Today only surplus above committed stake can leave.
`EXIT_DELAY` MUST be at least the maximum freeze horizon the game can impose, or exit
dodges penalties.

**Eligibility.** `StakingPolicy` computes participation from
`min(firstDepositBlock, preRegistrationBlock)`. Pre-registration is a zero-value
transaction an operator may send before a deposit or a cutover, so a mass restake does
not open a participation trough.

**Accounts and nodes.** Deposits are per account; overlay mapping is policy-side. One
account may back several nodes. `StakingPolicy` MUST NOT admit overlays whose summed
committed stake exceeds the account's deposit. A slash reduces the account, and therefore
every overlay it backs.

`StakingPolicy` SHOULD take an immutable `predecessor` and lazily inherit overlay and
height on first use, so a later cutover needs no operator transaction.

**Migration (once).** Operators move deposits with today's `migrateStake()` onto
`StakingCore`. The old registry is paused at `activationBlock`, not later. Operators
SHOULD pre-register so they are eligible immediately. After this, stake does not move
again: later cutovers only replace `StakingPolicy`.

**Cutover after the split.** Policy-pointer change on `StakingCore` under
`POLICY_TIMELOCK`. Deposits, withdrawals and exits never change ABI.

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

The outpayment model is therefore frozen: linear per-block accrual against a per-chunk
normalised balance. A different model is not a policy change; it would need a new core.

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

`refundBatch` pays the recorded owner and SHOULD forfeit a fraction to the pot. Nodes
treat a refund as batch invalidation, same as expiry. Introducing `refundBatch` is Type
A: stamp validity is consensus-adjacent.

**Migration (once), treasury-matched genesis.** `PostageStamp` cannot release unexpired
deposits, so the new core is seeded and separately backed:

1. At `activationBlock`, `PostageStamp` is paused (`createBatch`, `topUp`,
   `increaseDepth` freeze; expiry and `withdraw` continue).
2. `PostageAccounting` is deployed in a genesis phase. The deployer seeds the batch set
   as of `activationBlock` and transfers in matching BZZ for the full seeded value. The
   treasury fronts this float.
3. Genesis is sealed in the same ceremony. Until sealed, no other call is accepted;
   after sealing, no seeding path exists.
4. The treasury is reimbursed from the old contract as seeded batches' old-side balances
   expire into the old pot, using `withdraw` with the treasury as beneficiary — the final
   announced use of that primitive. The tail equals the longest remaining batch life.

After this, batches do not migrate again. Later cutovers only replace `PostagePolicy` and
`Redistribution`.

**Cutover after the split.** Redistributor pointer as in [Redistribution](#redistribution).
Policy-pointer change under `POLICY_TIMELOCK`. Balance reads never change ABI.

**Residual trust.** Deposits cannot be stolen or flash-drained. A hostile policy can
still, after the timelock, claim the pot at up to the honest rate and bias who wins.
Custody separation protects deposits, not rewards.

### PriceOracle

Not split. It holds no BZZ and no user state.

**State.** Current price, last adjusted round, redundancy targets, `changeRate` steps.
All of it is replaceable. The postage core stores `lastPrice` and the accumulator; the
oracle does not.

**How it is updated.** Redeployed when adjustment rules change (the rate table, the
redundancy target, the pause behaviour). A Type B cutover if Bee's p2p protocol is
unchanged; Type A if a consensus-critical consumer would need a runtime branch.

Price submission is `PriceOracle` → `PostagePolicy` → `PostageAccounting.setPrice`. The
core enforces `price <= MAX_PRICE` and a maximum step from `lastPrice`. Those bounds
MUST be compatible with the oracle's own steps, or honest adjustments revert.

**Migration.** None. Clients switch the compiled oracle address at `activationBlock`.
In-flight postage balances are unaffected: they are denominated in the core accumulator,
not in the oracle.

### Cutover protocol

Shared by all four. A **breaking Bee release** is a Bee version whose nodes cannot
connect to the previous version, so the p2p network splits in two. A **cutover** is the
coordinated switch of contract addresses at a round boundary. Type A cutovers follow a
breaking Bee release. Type B cutovers change contracts only; old and new Bee nodes can
still peer.

A `Cutover` contract publishes **when**. Addresses live in the client binary.

```solidity
interface ICutover {
    struct Schedule {
        uint32 protocolVersion;  // Bee p2p protocol version this cutover activates
        uint64 activationBlock;  // round boundary of the outgoing game
        bytes32 manifest;        // hash of the release's address set
    }
    function schedule(uint32 protocolVersion) external view returns (Schedule memory);
    function current() external view returns (Schedule memory);
}
```

- Clients MUST NOT learn a contract address from the chain and act on it. `manifest` is
  checked against the compiled address set; mismatch is a hard failure.
- Activation is observed from `Cutover` state, not a height baked into the binary. A
  reschedule MUST be announced at least `CUTOVER_NOTICE` blocks ahead. Inside that
  window a schedule MUST NOT be modified (cancellation counts as rescheduling).
- `activationBlock % ROUND_LENGTH_outgoing == 0`. A mid-round cutover orphans commits.
  A `ROUND_LENGTH` change is Type A; the incoming game starts on an outgoing boundary.
- The `Cutover` contract holds no funds. A hostile scheduler can delay cutovers, never
  redirect money.
- Clients switch the addresses they use at `activationBlock`, not at operator restart,
  and MUST NOT send a fund-moving transaction as an automated consequence of a chain
  signal.

**Type A — breaking Bee release.** Single game ABI. A node that has not upgraded stops
earning, by design. Required whenever a runtime branch would appear in reserve sampling,
commitment hashing, overlay derivation, eligibility, or stamp validity (including
`refundBatch`).

**Type B — contract-only.** Bee's p2p protocol is unchanged. The client carries both
bindings and switches at `activationBlock`. Dual-mode is confined to call sites; cores
never acquire a second ABI.

## Rationale

Upgradeable proxies over fund-holding contracts are rejected. A proxy admin can steal
the funds. Checking a registry on every fallback taxes all calls and can revert
withdrawals on a mistaken deprecation. `pinnedExecute` adds a second delegatecall path
and a permanent selector-collision constraint. That machinery solves "the admin swapped
the implementation under me." If deposits live in a contract that cannot be swapped, the
event is no longer a fund-loss event. A registry-like contract is kept only for cutover
*timing*; it is not a security root. The trust root is the client release either way.

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

## Test cases

Mandatory before any core deployment.

- Conservation after every call, including `resize`, `refundBatch`, expiry and price
  changes. Differentially check postage pot accrual against today's `expireLimited`.
- No transfer to an address not derived from core state (static check on bytecode).
- No core call into the policy address.
- Malicious policy: flash-drain, unbounded slash, over-claim, unbacked fund, value-inflating
  resize, blocked exit, over-max price. All revert; `exit` / `refundBatch` still succeed
  (including policy = 0, pending pointer change, and a locked staking account).
- Genesis: seeding without matching BZZ reverts; any call before seal reverts; seeding
  after seal reverts from every role; conservation holds at the first open block.
- Pointer changes cannot execute before `POLICY_TIMELOCK` or outside the execution
  window; cancellation works only before execution.
- Boundary-aligned cutover does not orphan a commit; off-boundary schedule reverts;
  `manifest` mismatch hard-fails the client.
- Policy replacement does not change `currentTotalOutPayment` or remaining balances.
- Pre-registered operators are eligible at `activationBlock`; others are not.
- Fuzz randomised sequences of deposit, fund, top-up, resize, price, expire, claim,
  slash, refund, withdraw and exit.

## Implementation

Each stage is independently valuable and independently revertible.

| Stage | Content | Depends on |
|---|---|---|
| 1 | New `Redistribution`; round-aligned cutover; one redistributor by operational discipline | — |
| 2 | New `Redistribution` on every breaking Bee release, as standing practice | — |
| 3 | `Cutover` contract and client support. Drop guarded proxies / `pinnedExecute` | 2 |
| 4 | `StakingCore` + `StakingPolicy`. Final stake migration | 3 |
| 5 | `PostageAccounting` + `PostagePolicy`. Treasury-matched genesis | 4 |
| 6 | Multisig scope reduced to policy and redistributor pointers | 5 |

`PriceOracle` has no dedicated stage: redeploy it with the postage or redistribution
release that needs the new adjustment rules.

After stage 5, surgical redeployment and the absence of admin power over deposits
coexist.

## Open questions

1. **Parameter values.** `POLICY_TIMELOCK` (suggested: 14 days in blocks), `EXIT_DELAY`
   (≥ maximum freeze horizon), `EXECUTION_WINDOW`, `CUTOVER_NOTICE`, slash and pot
   windows, `MAX_PRICE` and `MAX_PRICE_CHANGE_PER_UPDATE` (must match the oracle's
   steps). Immutable once deployed.
2. **Refund economics.** `refundBatch` forfeit fraction, and the wind-down decay
   schedule. A forfeit is preferred over a minimum batch age.
3. **Treasury float.** Size of the genesis front, and whether a deadline caps the
   reimbursement tail.
4. **Multi-client discipline.** What conformance looks like if a second client exists.
5. **Frozen outpayment model.** Keep linear per-chunk accrual in the core, or freeze
   remaining-BZZ with rate-capped policy consumption instead, so a later pricing model
   is still a policy change.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
