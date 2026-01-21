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

* Create/destroy.
* Deposit/withdraw excess.
* Update height (up/down).
* Update overlay address.

Some of these operations — for example, height reduction — result in a node's exit from or reduced financial commitment to a neighbourhood, negatively affecting the storage service. In an ideal world, any reduction of service commitment from one node would be compensated by another node arriving to take its place. However, since there is currently no reliable way to predict changes in service commitment, this hand-over cannot happen without at least a short service disruption. Introducing a mandatory "unwinding" delay before such changes come into effect, during which nodes continue to participate under their previous commitments, would provide a reliable signal allowing for smoother handoff of responsibilities between outgoing and incoming nodes.

This issue becomes particularly pertinent if stake withdrawals are enabled (cf. SWIP-40), allowing nodes to completely exit their commitment to the network. A mandatory wait period to exit a stake position would be familiar from many types of risky investment, where delays are a standard measure to facilitate orderly unwinding of positions.

### Stake record update freeze

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

The previously overloaded stake field `lastUpdatedBlockNumber` is now only responsible for freezing. We rename some endpoints and ABI elements to reflect this change, and hand responsibility for checking frozen state entirely over to the stake registry.

### Architecture

The proposal calls for the deployment of a new UpdateQueue contract that manages a queue of calls to setter methods in the Stake Registry. The Stake Registry maintains a reference to the UpdateQueue contract so that it can push requests to and pop from the queue. No other contracts or entities need to access the UpdateQueue contract directly. 

### Parameters

#### Queue parameters

| Name                      | Value  | Description                                                  |
| ------------------------- | ------ | ------------------------------------------------------------ |
| `UPDATE_QUEUE_MAX_LENGTH` | `10`   | Maximum number of pending request items per owner.           |

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

Since under this proposal, the field `lastUpdatedBlockNumber` is only used to check freezing status and whether the stake has ever been touched, we recommend the field is to be renamed to `frozenUntil`. This affects the ABI for the `stakes()` endpoint. 

Its getter function is also renamed, and the `addressNotFrozen` endpoint is made public so that the stake registry takes responsibility for the definition of "frozen" status.

```solidity
// function lastUpdatedBlockNumberOfAddress(address _owner) public view returns (uint256);
function frozenUntil(address _owner) public view returns (uint256);

// function addressNotFrozen(address _owner) internal view returns (bool);
function addressNotFrozen(address _owner) public view returns (bool);
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

* `applyUpdates` — iteratively get updates from the sender's update queue until `noPendingUpdate` error is raised. Apply updates to stake table.

* `minimumUpdateDelay` — classifies updates into delay types. Updates are classified as follows:

  * If the new height is less than the old height, the update is a *capacity reduction*.
  * If the new overlay differs from the old overlay, the update is a *commitment transfer*.

  Capacity reduction and commitment transfer have associated `DelayType`s. If more than one condition applies, the longest delay type is selected. If no conditions apply, `BaseDelay` is selected.

  In Solidity:

  ```solidity
  if new_height < old_height
      return DelayType.CapacityReductionDelay
  else if new_overlay != old_overlay
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

+ `manageStake` — does not write to the `stakes` table. Instead, the change to be applied is recorded in an `Update` object, a suitable `DelayType` is selected, and the data are pushed to the update queue. Because this proposal replaces the 2-round freeze after updates to stake metadata with a delay managed by the queue, the field `frozenUntil` (formerly `lastUpdatedBlockNumber` — see above) is not modified on calls to `manageStake`. This logic replaces lines 152–158 (https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L152C1-L158C12).

  Event emission responsibilities are delegated to the `UpdateQueue`, so the top-level logic of this call does not emit any events. Lines [163–170](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L163C4-L170C15) and [174–176](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L174C1-L176C1) are removed.

+ `withdrawFromStake()` — REMOVED in SWIP-40. [This function should use the getters that apply updates before returning in its calculation of `potentialStake`, `committedStake`, and `height`.]

+ `migrateStake()` — SHOULD clean up the update queue as well as deleting the stake registry entry.

The semantics of getter methods of `StakeRegistry` that read from the stake table, other than the `frozenUntil` (formerly `lastUpdatedBlockNumber`) field, are affected. There are five such methods:

```solidity
function nodeEffectiveStake(address _owner) public view returns (uint256);
function withdrawableStake() public view returns (uint256);
function overlayOfAddress(address _owner) public view returns (bytes32);
function heightOfAddress(address _owner) public view returns (uint8);
function stakes(address _owner) public view returns (Stake); // implicitly defined
```

Instead of returning the current values registered in the `stakes` table, these methods must pop and apply updates from an in-memory copy of the referenced `UpdateQueue` before returning a value. To maintain the `view` status of these methods, the updates are not written to storage.

#### Tests

* The Stake Registry cannot report stale values. All `view` endpoints as well as `updateAndGet*` endpoints
* Calls to `manageStake` should be enqueued in order and with correct delays.
  * A "trivial" update with `_setNonce` and `height` the same as before and `_addAmount = 0` receives the Base Delay. Trivial updates may still result in a change to `committedStake`. More generally, any update which leaves `_setNonce` unchanged and does not decrease `height` receives Base Delay.
  * Any update that decreases `height` receives the Exit Delay, regardless of what other changes it makes.
  * An update that changes `_setNonce` and either leaves `height` the same or increases it receives the Overlay Change Delay.
  * FIFO structure: if a `height` decrease is enqueued, then an update with a short delay is enqueued, the second update is not applied until after the full `EXIT_DELAY`.
* Call to `migrateStake` correctly processes enqueued deposit liabilities and withdraws all deposited tokens (when paused).
* Call to `withdrawFromStake` takes enqueued stake commitment into account when computing stake surplus. If there is some surplus, enqueuing another update makes that surplus instantly committed and inaccessible to `withdrawFromStake`.

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

Instead, it must be replaced with a check that the owner is not currently frozen.

Since this is the only use of the `MustStake2Rounds` error, this error type can be removed.

**Tests.**

* `commit()` does not access stale state. Pending updates are always applied before values are used.
* If less than 2 rounds have elapsed since any update was enqueued, `commit()` sees the same metadata as before. Therefore the same `obfuscatedHash` should be usable.

#### Implementation notes

The frozen check is semantically equivalent to `StakeRegistry.stakes[owner].frozenUntil >= block.number / ROUND_LENGTH`. Since the stake registry is responsible for tracking this value, it makes sense for it to also take responsibility for this check via a call to the `addressNotFrozen()` endpoint instead of repeating the predicate in the redistribution contract. 

### UpdateQueue

#### Overview

The contract owns a mapping of owner addresses to FIFO queue objects. Each queue object exposes a simple put/get queue interface for enqueuing opaque `Update` structs, each of which encodes a mutation to the owner's stake record. The put and get operations MUST be permissioned to the stake registry. The queue itself MAY be publicly readable, if it facilitates the signalling function that motivates its introduction. It MUST at least be readable by the stake registry, which needs to be able to make in-memory copies for evaluating `view` functions.

When an update is added to the queue along with a specified delay, a round number `effectiveFromRound` is calculated and recorded along with it. This number is either the current round plus the delay, or the `effectiveFromRound` of the last item in the queue, whichever is larger. When the current round is at least `effectiveFromRound`, the update item is said to be in *pending* state. The queue will only return updates in pending state; if none are found, it raises an exception.

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

// Pop an update from the queue if any valid calls are pending
// otherwise throw NoPendingUpdates error   
// Only StakeRegistry may call.
function get(address owner) external returns Update;

// Delete queue data associated to owner. Can only be called via migrateStake.
function clear(address owner) external whenPaused;
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

#### Tests

TODO

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

* *Manual queue triggering.* To preserve the getter interface of the `StakeRegistry` and make minimal changes to `Redistribution`, getter methods do not actually apply pending updates in place. However, the contract still needs a way to apply updates in place, or the queue will grow without bound, hence the `applyUpdates` endpoint. It is expected that clients will trigger `applyUpdates` regularly, either immediately after a new update comes into effect or before calling `Redistribution.commit()` during the next round that the overlay comes into proximity.

* *Update classification.* To apply different delays to different updates, updates need to be classified into types to be processed by the queueing system. Currently, the logic of `manageStake` implicitly classifies updates by the four non-reverting branches it takes, according to the independent predicates `(_addAmount > 0)` or `(_previousOverlay != _newOverlay)`. In the interests of allowing `UpdateQueue` to concern itself exclusively with queueing semantics, and not with staking, we propose that the responsibility of semantic classification of updates remain with `manageStake`, while `UpdateQueue` deals with sizes of updates.

* *Update encoding.* There are two basic approaches to recording the data of an "update" in the UpdateQueue:

  1. Record the new values to be applied in a struct.
  2. Directly encode the calldata of the call that will be made.

  Option (2) is future-proof in the sense that the same encoding will make sense if new types of update are introduced. OTOH it is less suitable for introspection than (1). We argue that the Queue contract itself should not be doing any introspection — it simply keeps track of *when* each update should be applied, and it is the caller's responsibility to hand it enough data to make that call. From this perspective, the opacity of an encoded call is also an advantage. 

  The matter of encoding is relevant from an interface perspective because the queue needs to emit events for each update. Therefore TODO: we need to make a call on this. The "future-proof" model seems over-engineered.

### Effect of pending status on other components

* *Price oracle.* For the purposes of adjusting storage prices, the reveal counter could discount nodes currently waiting to exit a neighbourhood. The basic reason to do this is to allow prices to pre-emptively respond to an upcoming decrease in supply, and hence mean replication rate. However, there are quite a lot of questions about on what principles the design of this feature should be based and how it should be implemented.

  * Local or global: should we attempt to introduce the discount when a node participates, or track node height reductions with a global counter?
  * In the other direction, should prices pre-emptively decrease in response to height increases and new nodes?
  * What price manipulations possibilities does this open up? What is the effect of enqueueing strings of updates?

  And so on. Moreover, the way that node balancing and replication rate is tracked may change substantially in the near future with something along the lines of SWIP-39. Therefore, we'd rather defer implementing price oracle pre-emption.

* *Reward sharing.* For the advance signalling function of an exit queue to work, nodes must be incentivised to continue operating while they are in the queue. Hence, they must be able to continue participating in reward sharing (and penalties) using their previous participation metadata while waiting. Accordingly, they must participate in all the activities that qualify them for reward sharing, i.e. reserve consensus and storage and density proofs.

* *Freezing.* If a node gets frozen while waiting to withdraw funds, what happens?

  * If withdrawal is allowed even if the stake is frozen at the end of the wait period, the penalty implied by freezing is effectively reduced gradually as the period nears its end.
  * If, on the other hand, frozen nodes cannot actually withdraw funds until the freeze period is ended, the freeze penalty has the effect of restricting access to capital. The fact that a withdrawal was attempted suggests that the value of being able to deploy that capital has recently become greater than the potential revenue, which is value of the freezing penalty under normal circumstances. Therefore it is not disproportionate for freezing to prevent withdrawal of funds if the freezing period would overlap the end of the `DRAWDOWN_DELAY` period.
  * Currently, frozen nodes are allowed to make deposits. Under the proposed queue system, funds are deposited at the time a deposit request is entered, but only registered for the purposes of redistribution after the delay `BASE_UPDATE_DELAY`. This only matters if the node participates, which it cannot if frozen. So the choice in this case is irrelevant.
  * If being frozen prevents or delays a node from executing an AoR change at the end of a period, it becomes harder to forecast node movements from queue state (because getting frozen screws that up). But that's the case with freezing anyway. Also, a frozen node cannot participate so its AoR is irrelevant.

  We therefore suggest that freezing be allowed to prevent the withdrawal of funds. All other changes have effect only during participation, which is anyway prevented during freezing.

  Can frozen nodes put in new update requests? I don't see why not.

* *Pausing.* When the Staking contract is paused, `migrateStake` is allowed and `manageStake` is not. Pausing the staking contract has no effect on participation in redistribution. The intention of this construction is to allow stake to move to a new version of the stake registry, so we see no reason to make `migrateStake` calls go via the queue. Instead, they should immediately clear and delete the queue, making sure to process all updates to liabilities in the form of `potentialStake`, and process the withdrawal.

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

