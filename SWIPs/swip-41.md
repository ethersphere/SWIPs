---
SWIP: 41
title: Stake registry update queue
author: Andrew Macpherson (@awmacpherson)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord)
status: WIP
category: Core
created: 2025-10-10
requires: SWIP-40
---

# Stake registry update queue

## Abstract

Introduce per-owner parallel FIFO queues that add parametrised delays to all updates to stake balances and metadata (i.e. height and overlay address). This replaces the 2-round thaw imposed on stakers after any change to stake balance or metadata.

## Motivation

### Advance signalling of service changes

Currently, the following operations are possible on a stake balance:

* Create or destroy.
* Deposit or withdraw excess.
* Update height up or down.
* Update overlay address.

Some of these operations — for example, height reduction — result in a node's exit from or reduced financial commitment to a neighbourhood, negatively affecting the storage service. In an ideal world, any reduction of service commitment from one node would be compensated by another node arriving to take its place. However, since there is currently no reliable way to predict changes in service commitment, this hand-over cannot happen without at least a short service disruption. Introducing a mandatory "unwinding" delay before such changes come into effect, during which nodes continue to participate under their previous commitments, would provide a reliable signal allowing for smoother handoff of responsibilities between outgoing and incoming nodes.

This issue becomes particularly pertinent if stake withdrawals are enabled (cf. SWIP-40), allowing nodes to completely exit their commitment to the network. A mandatory wait period to exit a stake position would be familiar from many types of risky investment, where delays are a standard measure to facilitate orderly unwinding of positions.

### Stake record update induced freeze

The current system design imposes a 2-round "thaw" on nodes, during which they may not participate, after any change to their stake record. The intention of this freeze is to prevent consensus manipulation attacks that are possible if the node can change their stake record mid-round, after the round anchor is revealed.

The system decides when to apply this block using an inline check in `Redistribution.commit()`, which also doubles up as checking for the "frozen" status which is applied as a penalty for consensus faults. This design has a number of flaws:

* It is inflexible, being based on anonymous logic and a hardcoded "magic number" value;
* Overloads the `lastUpdatedBlockNumber` variable which is also used to track frozen state and record initialisation;
* Breaks the obvious semantic meaning of freeze penalty lengths by adding 2 to the number of rounds in which the node cannot participate;
* Splits responsibility for imposing "freeze-like" penalties between the `Redistribution` and `StakeRegistry` contracts;
* Blocking the node from participating and earning rewards during this time could lead to service disruptions.

Moving the logic into a flexible, carefully designed delay system would address the first four complaints. The fifth point, an economic impact, is also easily addressed. Indeed, the defensive effect of preventing nodes from switching commitments mid-round is still achieved if the node is allowed to continue participating during the delay, but under their old balance and metadata. We find no reason to prevent the node from participating entirely.

## Specification

### Overview

Requests to update registered information (committed stake, height, and overlay address) are placed on a FIFO queue parallelised by owner, maintained by a new UpdateQueue subsystem, and executed lazily on calls to getter methods in the Stake Registry contract. An update is not processed unless a certain number of complete rounds has elapsed since it was placed on the queue. The number of rounds depends on the nature of the update; updates that allow stake balances to be reduced or nodes to remove neighbourhoods from their area of responsibility are subjected to longer delays.

The 2-round participation freeze currently imposed on stakers who update their stake data is removed and replaced with a 2 round delay managed by the queue introduced here. 

### Architecture

The proposal calls for the deployment of a new UpdateQueue contract that manages a queue of calls to setter methods in the Stake Registry. The Stake Registry maintains a reference to the UpdateQueue contract so that it can push requests to and pop from the queue. No other contracts or entities need to access the UpdateQueue contract directly. 

### Parameters

#### Queue parameters

| Name                      | Value | Description                                         |
| ------------------------- | ----- | --------------------------------------------------- |
| `UPDATE_QUEUE_MAX_LENGTH` | `10`  | Maximum number of enqueued request items per owner. |

Embedded in the update queue at deployment time.

#### Delay lengths

| Name                       | Value | Description                                                  |
| -------------------------- | ----- | ------------------------------------------------------------ |
| `CAPACITY_REDUCTION_DELAY` |       | Minimum delay in rounds to impose for height reduction.      |
| `OVERLAY_CHANGE_DELAY`     |       | Minimum delay in rounds to impose for change of overlay address. |
| `BASE_UPDATE_DELAY`        | `2`   | Minimum delay in rounds to impose for all operations.        |

Malicious changes to these variables could have the effect of trapping nodes in their positions indefinitely, so we propose that their values be embedded into the `StakeRegistry` contract at deployment time and not be modifiable by the admin.

To change these parameters, a new `StakeRegistry` must be deployed with the new parameters passed into the constructor. The usual flow for deploying a new `StakeRegistry` applies: the old registry paused, stake migrated, a new `Redistribution` deployed with a reference to the new `StakeRegistry`, and the Redistributor role on the `Postage` contract moved from the old `Redistribution` contract to the new one.

The values for `CAPACITY_REDUCTION_DELAY` and `OVERLAY_CHANGE_DELAY` are specified in a separate SWIP.

### StakeRegistry

Line numbers in this section refer to version 0.9.4.

#### Interface

The contract must maintain a reference `updateQueue` to a unique `UpdateQueue` contract. The getter for this reference may be `private`, as it is not intended that users will call the queue directly.

We introduce two new functions:

```solidity
function applyUpdates(address _owner) public {
	// pop and apply all items from _owner's update queue
	// then write to storage
}

function minimumUpdateDelay(address _owner, bytes32 _setNonce, uint256 _addAmount, uint8 _height) public view returns uint64 {
    // calculate and return the minimum delay in rounds that
    // would be applied for this update called by the given owner
    // (owner could be replaced by msg.sender)
}
```

A new enum `DelayType` is introduced to semantically classify operations in terms of the commitment change they induce.

The constructor method gets a new parameter where a mapping of delay types to delay lengths is embedded.

```solidity
enum DelayType { CapacityReductionDelay, TransferDelay, BaseDelay };

// constructor(address _bzzToken, uint64 _NetworkId, address _oracleContract)
constructor(
    address _bzzToken, 
    uint64 _NetworkId, 
    address _oracleContract, 
    mapping(DelayType => uint64) delays,
);
```

Otherwise, the interface of `StakeRegistry` is unchanged.

#### Events

The function served by the events `StakeUpdated` and `OverlayChanged` are taken over by the `UpdateEnqueued` event emitted by the `UpdateQueue` contract, so these event types may be removed from the `StakeRegistry` contract. 

#### Semantics

The semantics of the newly introduced methods are as follows:

* `applyUpdates` — iteratively get updates from the sender's update queue until `noEffectiveUpdate` error is raised. Apply updates to stake table.

* `minimumUpdateDelay` — classifies updates into delay types. Updates are classified as follows:

  * If the new height is less than the old height, the update is a *capacity reduction*.
  * If the new overlay differs from the old overlay, the update is a *commitment transfer*.

  Capacity reduction and commitment transfer have associated `DelayType`s. If more than one condition applies, the longest delay type is selected. If no conditions apply, or if this update creates a new stake record, `BaseDelay` is selected.

  In Solidity:

  ```solidity
  if new_height < old_height
      return DelayType.CapacityReductionDelay
  else if old_overlay != 0 && new_overlay != old_overlay
      return DelayType.TransferDelay
  else
      return DelayType.BaseDelay
  ```

The semantics of the following setter methods of `StakeRegistry` are affected:

```solidity
function manageStake(bytes32 _setNonce, uint256 _addAmount, uint8 _height) external whenNotPaused;
function withdrawFromStake() external; // REMOVED in SWIP-40
function migrateStake() external whenPaused;
```

As follows:

+ `manageStake` — does not write to the `stakes` table. Instead, the change to be applied is recorded in an `Update` object, a suitable `DelayType` is selected, and the data are pushed to the update queue. Because this proposal replaces the 2-round freeze after updates to stake metadata with a delay managed by the queue, the field `lastUpdatedBlockNumber` is not modified on calls to `manageStake`. This logic replaces lines 152–158 (https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L152C1-L158C12).

  Event emission responsibilities are delegated to the `UpdateQueue`, so the top-level logic of this call does not emit any events. Lines [163–170](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L163C4-L170C15) and [174–176](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L174C1-L176C1) are removed.

+ `withdrawFromStake()` — REMOVED in SWIP-40. [This function should use the getters that apply updates before returning in its calculation of `potentialStake`, `committedStake`, and `height`.]

+ `migrateStake()` — SHOULD clean up the update queue as well as deleting the stake registry entry.

The semantics of getter methods of `StakeRegistry` that read from the stake table, other than `lastUpdatedBlockNumberOfAddress`, are affected. There are five such methods:

```solidity
function nodeEffectiveStake(address _owner) public view returns (uint256);
function withdrawableStake() public view returns (uint256); // REMOVED in SWIP-40
function overlayOfAddress(address _owner) public view returns (bytes32);
function heightOfAddress(address _owner) public view returns (uint8);
function stakes(address _owner) public view returns (Stake); // implicitly defined
```

Instead of returning the current values registered in the `stakes` table, these methods must pop and apply updates from an in-memory copy of the referenced `UpdateQueue` before returning a value. To maintain the `view` status of these methods, the updates are not written to storage.

### Redistribution

The interface to the redistribution contract is unchanged.

Since the semantics of the `StakeRegistry` getter functions has changed, so too have the semantics of the three `Redistribution` functions that call them: `commit`, `reveal`, and `isParticipatingInUpcomingRound`. Note that the latter is a `view` function, so the calls it makes to fetch `overlay` and `height` records must also be `view` (i.e. they cannot apply updates in place first).

Since the 2 round cool-off after a call to `manageStake` has been replaced with a delay managed by `UpdateQueue`, the following check in the logic of `commit()` is no longer needed and should be removed:

```solidity
        if (_lastUpdate >= block.number - 2 * ROUND_LENGTH) {
            revert MustStake2Rounds();
        }
```

(see https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Redistribution.sol#L303). 

Since `nodeEffectiveStake` is zero for a frozen node, frozen nodes cannot participate even when this check is removed. Nonetheless, the implementer MAY wish to add a freeze status check to `commit()` so that participation fails early for a frozen node, saving on computation.

Since this is the only use of the `MustStake2Rounds` error, this error type can be removed.

### UpdateQueue

#### Overview

The contract owns a mapping of owner addresses to FIFO queue objects. Each queue object exposes a simple put/get queue interface for enqueuing opaque `Update` structs, each of which encodes a mutation to the owner's stake record. The put and get operations MUST be permissioned to the stake registry. The queue itself MAY be publicly readable, if it facilitates the signalling function that motivates its introduction. It MUST at least be readable by the stake registry, which needs to be able to make in-memory copies for evaluating `view` functions.

When an update is added to the queue along with a specified delay, a round number `effectiveFromRound` is calculated and recorded along with it. This number is either the current round plus the delay, or the `effectiveFromRound` of the last item in the queue, whichever is larger. When the current round is at least `effectiveFromRound`, the update item is said to be in *effective* state. The queue will only return updates in effective state; if none are found, it raises an exception.

#### Interface

````solidity
mapping(address => Queue<UpdateItem>) public updateQueue;

// UpdateQueue entry
struct UpdateItem {
    uint64 effectiveFromRound;
    Update update;
}

// Update struct
struct Update {
    // private fields
    // bundle with library exposing update.applyTo(Stake record)
}

// Add update to the queue of updates for `owner` with validity 
// in rounds starting after a delay of `delay` rounds.
// Only StakeRegistry may call.
// Emit UpdateEnqueued event.
function put(address owner, Update update, uint64 delay) external;

// Pop an effective update from the queue
// or throw NoEffectiveUpdates error   
// Only StakeRegistry may call.
function get(address owner) external returns Update;

// Pop all items associated to owner, even if not yet effective, and delete queue.
// May only be called via migrateStake.
function fastForward(address owner) external whenPaused returns UpdateItem[];

// Create and return an in-memory copy of the list of effective updates
// for applying changes in view functions.
function cloneEffective(address owner) external returns Update[];
````

#### Events

```solidity
// emitted on call to updateQueue.push()
// replaces OverlayChanged, StakeUpdated
event UpdateEnqueued {
    uint256 effectiveFromRound;
    uint256 balance;
    bytes32 overlay;
    uint8 height;
}
```

## Rationale

* *One queue.* All types of updates for all stake owners are considered to be part of one queue. While some queue designs may allow for handling different owners or different update types in isolation, others — such as a global churn rate limiter — require tracking global state. To future proof the queue interface against possible changes to queue design, other components of the system must treat the entire network-wide queue as a single black box.

* *Separate UpdateQueue contract.* We propose the update queue be maintained in a separate contract from the Stake Registry for the sake of maximising modularity and isolating parts of deployments from unrelated future upgrades.

  For the sake of gas efficiency, the UpdateQueue contract could be inlined into the StakeRegistry. However, we find this to be a premature optimisation that gives up modularity for the sake of gas fees that are basically insignificant (millionths of a dollar) in practice.

* *2 round thaw.* The 2 round thaw currently implemented (but not fully documented) in the `commit()` method of the Redistribution contract is absorbed into this queue. The delay length is preserved as the `BASE_UPDATE_DELAY` parameter. However, unlike in the old model, participation is still allowed during the thaw period — but under the old stake position.

* *Signalling.* To act as a signal, node operators must be able to easily index enqueued updates along with the round number at which they come into effect. Since the `UpdateQueue` contract is responsible for tracking when updates come into effect, the events used for indexing must be emitted from there. There is no need to emit an event when the update is actually applied in state, which is inconsequential.

* *Per-neighbourhood delay scaling.* It may make sense to adjust the delay of changes depending on the before and after population of each neighbourhood affected by the change. The core example is to reduce delay for nodes leaving a neighbourhood with large population (and in the case of overlay change, entering one with small population). This would require the queue system to be able to estimate replication depth and enlarges the design space considerably, so we omit it from the present proposal.

* *Maximum queue length.* In principle, an update queue could grow so long that it cannot be emptied in a single block. Therefore, there shold be a maximum number of updates that can be held in the queue for each owner. It probably won't cause a big problem if the number is quite small, e.g. 10.

  An alternative approach would be to internally merge operations using an internal representation closed under composition. While we can imagine ways to do this for the set of operations the queue is currently expected to process, it would complicate the process of adding any new types of operation to the queue or changing the queue algorithm. A simple maximum queue length is easy to implement, universal, and unlikely to raise any serious objections.
  
* *Staker commitments.* Staker commitments, i.e. transfers to the stake registry and latest-price updates to committed stake, must be binding for the staker at the time the update is requested. The queue subsystem must be able to report up-to-date commitments. The effect of the new commitment (i.e. the new `committedStake` balance can be used in Redistribution) does not apply until after the delay.

* *Liability tracking.* The proposed changes mean that the `potentialStake` recorded under a given `owner` in the Stake Registry does not always equal the total amount of BZZ deposited by that owner (net of surplus withdrawals). Rather, the records of liabilities of the Stake Registry to a given owner are split between the Registry itself and the Update Queue. Since these records control what can be withdrawn by calling the `withdrawFromStake` and `migrateStake` methods, these processes must either block on not-yet-active updates, or fast track and apply them.

* *Manual queue triggering.* To preserve the getter interface of the `StakeRegistry` and make minimal changes to `Redistribution`, getter methods do not actually apply effective updates in place. However, the contract still needs a way to apply updates in place, or the queue will grow without bound, hence the `applyUpdates` endpoint. It is expected that clients will trigger `applyUpdates` regularly, either immediately after a new update comes into effect or before calling `Redistribution.commit()` during the next round that the overlay comes into proximity.

* *Update classification.* To apply different delays to different updates, updates need to be classified into types to be processed by the queueing system. Currently, the logic of `manageStake` implicitly classifies updates by the four non-reverting branches it takes, according to the independent predicates `(_addAmount > 0)` or `(_previousOverlay != _newOverlay)`. In the interests of allowing `UpdateQueue` to concern itself exclusively with queueing semantics, and not with staking, we propose that the responsibility of semantic classification of updates remain with `manageStake`, while `UpdateQueue` deals with sizes of updates.

* *Update encoding.* There are two basic approaches to recording the data of an "update" in the UpdateQueue:

  1. Record the new values to be applied in a struct.
  2. Directly encode the calldata of the call that will be made.

  Option (2) is future-proof in the sense that the same encoding will make sense if new types of update are introduced. OTOH it is less suitable for introspection than (1). We argue that the Queue contract itself should not be doing any introspection — it simply keeps track of *when* each update should be applied, and it is the caller's responsibility to hand it enough data to make that call. From this perspective, the opacity of an encoded call is also an advantage. 

  The matter of encoding is relevant from an interface perspective because the queue needs to emit events for each update. Therefore TODO: we need to make a call on this. The "future-proof" model seems over-engineered.

### Effect of waiting status on other components

* *Price oracle.* For the purposes of adjusting storage prices, the reveal counter could discount nodes currently waiting to exit a neighbourhood. The basic reason to do this is to allow prices to pre-emptively respond to an upcoming decrease in supply, and hence mean replication rate. However, there are quite a lot of questions about on what principles the design of this feature should be based and how it should be implemented.

  * Local or global: should we attempt to introduce the discount when a node participates, or track node height reductions with a global counter?
  * In the other direction, should prices pre-emptively decrease in response to height increases and new nodes?
  * What price manipulations possibilities does this open up? What is the effect of enqueueing strings of updates?

  And so on. Moreover, the way that node balancing and replication rate is tracked may change substantially in the near future with something along the lines of SWIP-39. Therefore, we'd rather defer implementing price oracle pre-emption.

* *Reward sharing.* For the advance signalling function of an exit queue to work, nodes must be incentivised to continue operating while they are in the queue. Hence, they must be able to continue participating in reward sharing (and penalties) using their previous participation metadata while waiting. Accordingly, they must participate in all the activities that qualify them for reward sharing, i.e. reserve consensus and storage and density proofs.

* *Freezing.* Under the current system, frozen nodes are not allowed to mutate stake records. The effect of this is that if a frozen node decides they wish to update their stake record, they must wait until the freeze ends, execute the update, *and wait another 2 rounds* to participate again. In other words, as well as blocking participation, freeze penalties delay executing changes to the stake record. This behaviour appears to be undocumented (cf. https://docs.ethswarm.org/docs/concepts/incentives/redistribution-game#penalties), and it's not clear if it's important.

  This SWIP does not propose to change this behaviour, but we note that its effects are exacerbated by introducing longer record update delays. A node operator who decides while frozen to update their stake record must wait the update delay sequentially after the freeze period. On the other hand, if an update is enqueued and *then* the node gets frozen, the freeze period and the update delay run concurrently. 
  
  Applying effective updates in state is purely a gas management measure, and does not affect any values that can be read from the contract. Therefore frozen nodes should not be prevented from calling `applyUpdates`.
  
* *Pausing.* When the Staking contract is paused, `migrateStake` is allowed and `manageStake` is not. Pausing the staking contract has no effect on participation in redistribution. The intention of this construction is to allow stake to move to a new version of the stake registry, so we see no reason to make `migrateStake` calls go via the queue. Instead, they should immediately fast forward and delete the queue, making sure to process all updates to liabilities in the form of `potentialStake` including those that are not yet effective, then process the withdrawal.

### Concurrency

* If actions are anything other than instantaneous and atomic, we need to deal with concurrency — that is, an update being requested while another is waiting in the queue. 
* Different types of action ought to be treated differently, whence multiple delay types. 
* *In-order execution.* 
  * Insisting on in-order execution means that actions with short delays (e.g. topping up) can be held up by actions with longer delays (e.g. height reduction). This might not be necessary.
  * On the other hand, allowing out-of-order execution will probably make the analysis much more complicated. It will be harder to use the queue state to make a forecast and to implement lookahead.
* *Request cancellation.* Requires a way to specify which request should be cancelled, and again substantially complicates making use of the information benefits of a public queue. It is simpler and more elegant not to allow cancellations.

### Contract and parameter upgrades

Can the reference to `UpdateQueue` maintained by `StakeRegistry` be changed by the admin? With a delay? Broadly speaking, we see three approaches:

1. Reference is immutable. To change the update queue logic, a new stake registry must be deployed.
2. Reference is instantly mutable. Admin can burn stake by imposing infinite delays.
3. Reference is mutable with a delay, emitting an event. Under SWIP-40, stakers may withdraw if they do not want to be subject to the new queue logic.

Under the current implementation, the admin can lock all stake indefinitely, effectively burning it, by never pausing the contract. The proposed changes should not make this attack worse and expose stake to a malicious admin.

Can multiple `StakeRegistry` deployments reference a single `UpdateQueue`? *No*, because that would screw everything up. Write changes to `UpdateQueue` must be permissioned to a unique `StakeRegistry`. (`UpdateQueue` does not need to maintain a reference to `StakeRegistry`, only a commitment.)

An intermediate option is that the *logic* of `UpdateQueue` is immutable, but the *delay parameters* can be changed. This doesn't improve much, as it still gives the admin to lock stake indefinitely.

## Impact

### Security implications

* The update queue subsystem takes ownership, in the form of `BASE_UPDATE_DELAY`, of the 2 round metadata update delay currently found in the initial validation checks of the `Redistribution:commit()` call. A top-up or deposit delay of at least until the end of the current round is required to prevent shadow stake attacks. No immediate changes to security model for shadow stake or penalty evasion are implied by the current proposal, but care needs to be taken in future to preserve the `BASE_UPDATE_DELAY` minimum.
* In the proposed access control model, anyone may trigger processing of valid updates from anyone else's queue. Since updates cannot be cancelled and would be processed anyway before the state can be used in redistribution, this is harmless.

### Economic implications

The main effect, which is intended, is to slow down interactions with the stake registry, particularly those that could threaten data replication.

* Among the currently permitted changes, the most serious threat to stability comes from height reduction, which removes a node entirely from the service of a particular neighbourhood. Incentives to reduce height may include:
  * Save on storage costs by reducing commitment.
  * Maintain stake density after a drawdown.
* We expect that the incentives for drawing down stake occur frequently, driven by market conditions and the attractiveness of other opportunities. Currently, the opportunities to withdraw stake are limited to when the storage price quote has gone down from when the stake was last "committed." Since only "uncommitted" stake can be withdrawn, withdrawing it has no immediate impact on the incentive to continue providing good service on the node, so no delay is needed.
* Changing overlay address does not affect the mean replication rate, but it weakens one neighbourhood while strengthening another. The design of the revenue sharing system implies that the incentives will often be for nodes to move from more populated neighbourhoods to less populated ones, but this need not always be the case. 
  Introducing a modest delay gives the network time to react to such changes, for example by migrating nodes from other neighbourhoods to fill a gap. Discounting exiting nodes from the replication rate counter of the source neighbourhood allows new nodes to enter without triggering downward price pressure.

### Interactions with other proposals

* *Self-custodial/upgradable stake registry.* An upgradable stake registry change would not need the `migrateStake` endpoint and possibly separate balance and participation metadata management into different contracts.

  When a change to the queue design occurs, metadata updates already waiting in the queue should ideally continue be processed under the old queue logic. If the queue state is part of the Stake Registry contract, there is no way to protect it from arbitrary updates. Thus the queue ought to be part of a new contract accessible by the Redistributor.

  If a self-custodial vault model is used to protect user actions from malicious registry upgrades, a separate Queue contract could facilitate protection of withdrawals by taking over a claim on the funds marked for withdrawal from the Registry, before ultimately returning it to the owner when the withdrawal is ready. It would then be impossible for a Registry upgrade to affect the winding down of the claim.

* *Withdrawable stake.* Withdrawing stake completely needs its own delay, at least as severe as for reducing height. Since it doesn't really make sense for exiting to be triggered by a call to `Redistribution:commit()`, there should be a separate endpoint to manually trigger exits.

  If stake is withdrawable under more general circumstances, we expect that freezing will prevent such withdrawals.
  
* *Automatic address assignment.* Current versions of automatic neighbourhood assignment call for a delayed commit/execute scheme to be allocated a neighbourhood after staking. The present update queue proposal provides a subsystem to implement this delay.

  Changes to the way that balancing and node count are tracked could have implications for how the price oracle is adjusted, which would interact with variants of this proposal that use the queue to pre-empt price changes.

## Testing strategy

*Note: this section was written by Claude Opus 4.5 with minor revisions by the author.*

This section defines the testing strategy for validating a correct implementation of this SWIP.

### Testing Philosophy

#### Guiding Principles

- **Isolation**: Each component (UpdateQueue, StakeRegistry modifications, Redistribution modifications) should be testable independently
- **State machine verification**: The queue system introduces new state transitions that must be verified exhaustively
- **Delay correctness**: Core invariant is that updates are never applied before their `effectiveFromRound`
- **Backwards compatibility**: Getters must return correct values whether or not `applyUpdates` has been called
- **Security boundaries**: Only StakeRegistry should be able to mutate UpdateQueue state

#### Test Framework

Tests should use the existing storage-incentives test infrastructure:
- **Framework**: Hardhat + Mocha + Chai (TypeScript)
- **Fixtures**: `hardhat-deploy` fixtures for fresh contract deployments
- **Utilities**: Existing `test/util/tools.ts` helpers for block mining, token operations
- **Named accounts**: `node_0` through `node_7` for multi-staker scenarios

---

### Test Categories and Coverage Matrix

| Category                          | UpdateQueue | StakeRegistry | Redistribution | Integration |
| --------------------------------- | ----------- | ------------- | -------------- | ----------- |
| Unit tests                        | ✓           | ✓             | ✓              | -           |
| State transitions                 | ✓           | ✓             | -              | -           |
| Access control                    | ✓           | ✓             | -              | -           |
| Delay enforcement                 | ✓           | ✓             | -              | ✓           |
| Event emission                    | ✓           | ✓             | -              | -           |
| View function correctness         | -           | ✓             | ✓              | ✓           |
| Error conditions                  | ✓           | ✓             | ✓              | -           |
| Multi-round scenarios             | -           | -             | -              | ✓           |
| Concurrency (queued updates) TODO | ✓           | ✓             | -              | ✓           |

---

### UpdateQueue Contract Tests

#### Core Queue Operations

```
describe('UpdateQueue', function () {
  describe('queue structure', function () {
    - should initialize with empty queue for any address
    - should maintain FIFO order when multiple updates enqueued
    - should track effectiveFromRound correctly for each item
    - should enforce UPDATE_QUEUE_MAX_LENGTH (10 items per owner)
    - should revert when queue length exceeded
  })

  describe('put operation', function () {
    - should only allow StakeRegistry to call put()
    - should revert if called by non-StakeRegistry address
    - should calculate effectiveFromRound as max(currentRound + delay, lastItem.effectiveFromRound)
    - should emit UpdateEnqueued event with correct parameters
    - should accept delay of 0 (becomes current round)
    - should handle first item in queue (no predecessor)
  })

  describe('get operation', function () {
    - should only allow StakeRegistry to call get()
    - should revert with NoEffectiveUpdates if queue is empty
    - should revert with NoEffectiveUpdates if no items have effectiveFromRound <= currentRound
    - should return and remove the oldest effective update
    - should not return items where effectiveFromRound > currentRound
    - should correctly handle partial queue (some items effective, some not)
  })

  describe('fast forward operation', function () {
    - should revert if called by non-StakeRegistry address
    - should return all queued items for owner, including ones not yet effective
  })

  describe('effectiveFromRound calculation', function () {
    - should use currentRound + delay when queue is empty
    - should use predecessor's effectiveFromRound when it's larger than currentRound + delay
    - should chain delays: item2.effectiveFrom >= item1.effectiveFrom regardless of delay
  })
})
```

#### Edge Cases

```
describe('UpdateQueue edge cases', function () {
  - should handle round boundary transitions correctly
  - should handle updates enqueued in same block
  - should handle maximum queue length exactly (10 items)
  - should handle multiple updates becoming effective during the same transaction
})
```

---

### StakeRegistry Modification Tests

#### Delay Classification (`minimumUpdateDelay`)

```
describe('minimumUpdateDelay', function () {
  describe('BaseDelay classification', function () {
    - should return BASE_UPDATE_DELAY for trivial update (same nonce, same height, 0 amount)
    - should return BASE_UPDATE_DELAY for height increase
    - should return BASE_UPDATE_DELAY for deposit-only (same nonce, same height, amount > 0)
    - should return BASE_UPDATE_DELAY for any mixture of the above
  })

  describe('CapacityReductionDelay classification', function () {
    - should return CAPACITY_REDUCTION_DELAY when new height < old height
    - should prioritize CapacityReduction over other delay types
    - should apply CapacityReduction even when overlay also changes
  })

  describe('TransferDelay classification', function () {
    - should return OVERLAY_CHANGE_DELAY when overlay changes (different nonce)
    - should apply TransferDelay when overlay changes with height increase
    - should not apply TransferDelay for first stake (no previous overlay)
  })
})
```

#### `manageStake` Semantics Changes

```
describe('manageStake with queue', function () {
  describe('enqueueing behavior', function () {
    - should make no change to stakes table
    - should push update to UpdateQueue with correct delay
    - should transfer tokens immediately (liability recorded)
    - should not emit StakeUpdated event (delegated to queue)
    - should not emit OverlayChanged event (delegated to queue)
  })

  describe('token handling', function () {
    - should transfer tokens on enqueue for adding stake, not on apply
    - should correctly track liabilities across enqueued deposits
    - should handle multiple deposits in queue
  })

  describe('FIFO enforcement', function () {
    - if height decrease queued, then deposit queued, deposit waits for height decrease
    - short delay operations cannot leapfrog long delay operations
    - effectiveFromRound of item N+1 >= effectiveFromRound of item N
  })
})
```

#### View Functions (Lazy Evaluation)

```
describe('view functions with effective updates', function () {
  describe('nodeEffectiveStake', function () {
    - should apply effective updates in-memory before returning
    - should return frozen-aware value (0 if frozen)
    - should handle multiple effective updates
  })

  describe('overlayOfAddress', function () {
    - should return current overlay if no effective updates
    - should return updated overlay if update is effective
    - should return old overlay if update is not yet effective
  })

  describe('heightOfAddress', function () {
    - should apply effective updates in-memory
    - should return old height if waiting update not yet effective
  })

  describe('stakes(address)', function () {
    - should return struct with effective updates applied
    - should handle first deposit gracefully (return null values for 2 rounds)
  })
})
```

#### `applyUpdates` Function

```
describe('applyUpdates', function () {
  - should pop and apply all effective updates to storage
  - should stop when NoEffectiveUpdates is raised
  - should be callable by anyone (permissionless)
  - should handle empty queue gracefully
  - should correctly update stakes mapping
  - should leave no effective items on queue
  - should be idempotent if called twice within same round
})
```

#### `migrateStake` with Queue

```
describe('migrateStake with queue', function () {
  - should return all tokens (potentialStake + enqueued deposits, including those not yet in effect)
  - should only work when paused
})
```

#### Invalidated tests (8)

Of the 34 tests in `Staking.test.ts`;

* 9 are tests for `withdrawFromStake`, which will be replaced under SWIP-40.
* 17 are unaffected by the changes proposed.
* Of the remaining 8:
  * 4 (lines 131, 155, 274, 355) expect a `StakeUpdated` event — these will need to be updated to expect an `UpdateEnqueued` event instead.
  * 6 (lines 131, 155, 219, 664, 671, 677) check the stake record immediately after a call to `manageStake` — a suitable delay must be inserted.

---

### Redistribution Contract Tests

#### Removal of MustStake2Rounds Check

```
describe('commit without MustStake2Rounds', function () {
  - should allow commit with old metadata immediately after update to existing stake
  - should not allow commit immediately after first deposit, only after BASE_UPDATE_DELAY rounds
  - should not allow commit during a freeze penalty
})
```

#### Invalidated Tests (5)

The following existing tests are invalidated and should be removed:

| Line | Test                                                         | Reason                                                       |
| ---- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 253  | should not create a commit with recently staked node         | Expects `MustStake2Rounds` error (removed in SWIP-41)        |
| 266  | should create a commit with staked node                      | Expects `MustStake2Rounds` error                             |
| 288  | should create a commit with staked node and height 2         | Expects `MustStake2Rounds` error                             |

The following tests are impacted and should be modified, either by fastforwarding the chain to allow for height change delay, or by splitting each into two separate tests, one at each height.

| Line | Test                                                         | Reason                                                       |
| ---- | ------------------------------------------------------------ | ------------------------------------------------------------ |
| 513  | should create a commit with failed reveal... but good reveal if height is changed | Calls `manageStake()` mid-test to change height, expects immediate effect |
| 582  | should create a commit with successful reveal... with height 2 | Calls `manageStake()` then immediately commits expecting new height |

The remaining 44 tests in `Redistribution.test.ts` are unaffected.

---

### Integration Tests

#### Full Round Participation with Queue

```
describe('integration: round participation with queue', function () {
  - node stakes, waits BASE_UPDATE_DELAY rounds, can participate
  - node stakes, immediately tries commit, uses old metadata (none initially)
  - node updates height down, continues participating with old height during delay
  - node changes overlay, continues participating with old overlay during delay
  - node updates, waits, and triggers applyUpdates before commit, uses new metadata
  - node updates, waits, but does not trigger applyUpdates before commit, uses new metadata
})
```

#### Multi-Update Scenarios

```
describe('integration: multiple updates', function () {
  - deposit, then deposit again: both applied in order
  - deposit, then change overlay: overlay change waits for deposit
  - height reduction queued, then deposit: deposit waits for height reduction
  - 10 updates queued: all applied correctly in order
  - 11th update: should revert with queue full error
})
```

---

### Security-Focused Tests

```
describe('security', function () {
  describe('shadow stake prevention', function () {
    - cannot use newly deposited stake in same round (BASE_UPDATE_DELAY)
    - cannot change overlay mid-round and participate with new overlay
  })

  describe('access control', function () {
    - UpdateQueue.put only callable by StakeRegistry
    - UpdateQueue.get only callable by StakeRegistry
    - UpdateQueue.clear only callable when paused
    - multiple stake registries cannot call into same UpdateQueue deployment
  })

  describe('denial of service', function () {
    - queue max length prevents unbounded iteration
    - applyUpdates completes in bounded gas
  })
})
```

Note. Reentrancy is not a concern for this proposal, none of whose methods call into an untrusted contract.


---

### Event Tests

```
describe('events', function () {
  describe('UpdateEnqueued', function () {
    - should emit on manageStake with correct effectiveFromRound
    - should include post-update balance, overlay, height
  })

  describe('removed events', function () {
    - StakeUpdated should not be emitted from StakeRegistry on manageStake
    - OverlayChanged should not be emitted from StakeRegistry on manageStake
  })
})
```

---

### Test Data Requirements

#### Pre-computed values needed

- Overlays for multiple nonces (as in existing tests)
- Round numbers for delay calculations

#### Test fixtures

- Multiple stakers (`node_0` through `node_7` available)
- `TestToken` with mint capability
- Deployed `UpdateQueue`, `StakeRegistry`, `Redistribution`

#### Constants

```typescript
const ROUND_LENGTH = 152;
const BASE_UPDATE_DELAY = 2;  // rounds
const UPDATE_QUEUE_MAX_LENGTH = 10;
// CAPACITY_REDUCTION_DELAY and OVERLAY_CHANGE_DELAY TBD in separate SWIP
```
