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

### Filtering short-termist operator behaviour

Operators may be incentivised to make changes to their commitments based on short term signals such as market volatility, leading to excessive churn of stake positions. Imposing a wait period $X$ makes it impossible to execute a strategy based on a holding period of less than $X$. See SWIP-40.

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

Requests to update registered information (committed stake, height, and overlay address) and withdraw tokens (under SWIP-40) are placed on a per-owner FIFO queue and executed lazily on calls to getter methods in the stake registry contract. An update is scheduled to come into effect at least a certain number of complete rounds has elapsed since it was placed on the queue. The minimum number of rounds depends on the nature of the update. Updates that allow stake balances to be reduced or nodes to remove neighbourhoods from their area of responsibility are subjected to longer delays.

The 2-round participation freeze currently imposed on stakers who update their stake data is removed and replaced with a 2 round delay managed by the queue introduced here. 

### Architecture

The proposal introduces a new update schedule component which is responsible for tracking the schedule of updates to be applied to each owner's stake account. The update schedule is consumed only by the stake registry; it has no public facing interfaces other than events. This proposal does not define the interface that the update schedule exposes to the stake registry, nor does it specify whether the update schedule lives in its own contract or is embedded in the stake registry contract.

The update schedule is written during the following workflows, whose semantics are affected:

* Creating a new stake deposit
* Adding tokens to an existing stake deposit
* Changing overlay address
* Increasing height

All of these workflows are mediated by the `manageStake()` method of `StakeRegistry`.

As a companion change, one workflow is removed:

* Decreasing height.

A new workflow is added:

* *Apply changes.* Apply scheduled updates from the update schedule. (SWIP-40: and transfer out tokens.)

The update schedule is read when calling getter methods of the owner's stake record.

### Parameters

#### Queue parameters

| Name                      | Value | Description                                         |
| ------------------------- | ----- | --------------------------------------------------- |
| `UPDATE_QUEUE_MAX_LENGTH` | `10`  | Maximum number of enqueued request items per owner. |

Embedded in the update queue at deployment time.

#### Delay lengths

| Name                  | Value | Description                                                  |
| --------------------- | ----- | ------------------------------------------------------------ |
| `WAIT_OVERLAY_CHANGE` | TBC   | Minimum delay in rounds to impose for change of overlay address. |
| `WAIT_BASE`           | `2`   | Minimum delay in rounds to impose for all operations.        |

Malicious changes to these variables could have the effect of trapping nodes in their positions indefinitely, so we propose that their values be embedded into the `StakeRegistry` contract at deployment time and not be modifiable by the admin.

To change these parameters, a new `StakeRegistry` must be deployed with the new parameters passed into the constructor. The usual flow for deploying a new `StakeRegistry` applies: the old registry paused, stake migrated, a new `Redistribution` deployed with a reference to the new `StakeRegistry`, and the Redistributor role on the `Postage` contract moved from the old `Redistribution` contract to the new one.

The values for `CAPACITY_REDUCTION_DELAY` and `OVERLAY_CHANGE_DELAY` are specified in a separate SWIP.

> **ALIGNMENT POINT.** Other than `WAIT_BASE`, the deployer may well wish to alter these values in future based on observations of depositor behaviour. This would be much easier if the contract provided admin-locked setter functions to change them on a deployed contract, but this potentially exposes depositors to an unaligned admin. A compromise solution is to hardcode constraints on the admin setter function, for example that it only be allowed to *decrease* the wait period, never increase.

### Interface

#### StakeRegistry

Line numbers in this section refer to version 0.9.4.

We introduce one new method:

```solidity
function applyUpdates(address _owner) public {
	// pop and apply all items from _owner's update queue
	// then write to storage
}
```

A new enum `DelayType` is introduced to semantically classify operations in terms of the commitment change they induce.

The constructor method gets a new parameter where a mapping of delay types to delay lengths is embedded.

```solidity
enum DelayType { DelayBase, DelayTranslation };

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

The function served by the events `StakeUpdated` and `OverlayChanged` are taken over by the following events, which are the responsibility (and the sole public-facing API) of the update queue component:

```solidity
// emitted when height increase or overlay change is added to schedule
// replaces OverlayChanged
event ServiceCommitmentUpdate {
    uint256 registeredFromRound;
    bytes32 overlay;
    uint8 height;
}

// emitted when a deposit is made
// replaces StakeUpdated
event Deposit {
    uint256 registeredFromRound;
    uint256 amount;
}

// emitted when a withdrawal is added to the schedule
event Withdrawal {
    uint256 registeredFromRound;
    uint256 amount;
}
```

The queue component MAY make the following view methods part of the public interface. Doing this makes `Update` part of the public interface.

````solidity
// OPTIONAL
// Return an in-memory copy of the list of effective updates
// for applying changes in view functions.
function peekReady(address owner) external view returns Update[];


// OPTIONAL
// calculate and return the minimum delay in rounds that
// would be applied for this update called by the given owner
// (owner could be replaced by msg.sender)
function minimumUpdateDelay(address _owner, bytes32 _setNonce, uint256 _addAmount, uint8 _height) public view returns uint64;
````

### Semantics

For the purpose of describing semantics of this SWIP, introduce the following Python pseudocode model of chainstate:

```python
Stake:
    overlay: bytes
    balance: int # SWIP-20 revert
    frozen_until: int # remove 2-round update freeze + rename lastUpdatedBlockNumber
    height: int    

State:
    current_block: int
    current_round: int
    stakes: dict[EthAddress, Stake]
    update_schedule: dict[EthAddress, UpdateSchedule] # see below
```

#### Updates

Under this proposal, updates are not applied in state immediately upon calling an update workflow. Consequently, the *update object* itself must be encoded and stored in state. The semantics of an update object are as follows:

```python
Update = Union[
    CreateDeposit,
    AddTokens,
    IncreaseHeight,
    ChangeOverlay
]
CreateDeposit:
    amount: int
    nonce: bytes
    height: int
AddTokens:
    amount: int
IncreaseHeight:
    new_height: int
ChangeOverlay:
    new_nonce: bytes
```

The lifecycle of an update object, once created, must end with its being applied to the stake registry. The semantic model of applying updates here is designed to parallel the current logic of the `manageStake` public interface. It cannot literally be implemented by calling `manageStake` since the semantics of the latter is changed to only *register* updates, not apply them; see below.

```python
# assume helper methods derive_overlay(nonce) and minimum_initial_stake(height) 
# are defined as in existing codebase and mainnet context

def create_record(state, update) -> Stake:
    """
    Create a new record with specified parameters.
    """    
    bzz_token.transfer_from(owner, amount)
    record = Stake(
        overlay = derive_overlay(update.nonce),
        balance = update.amount,
        frozen_until = state.current_block,
        height = update.height
    )
    return record

def apply(state, update): 
    """
    Apply update in state.
    """
    match type(update):
        case CreateDeposit:
            state.stake_registry.stakes[owner] = create_record(update)
        case AddTokens:
            state.stake_registry.stakes[owner].balance += update.amount
        case IncreaseHeight:
            # Apply only if new height would be greater than current height
            if state.stake_registry.stakes[owner].height < update.new_height:
                state.stake_registry.stakes[owner].height = update.new_height
        case ChangeOverlay:
            state.stake_registry.stakes[owner].overlay = derive_overlay(update.new_nonce)
        default:
            raise # not used
    del update 
```

With the exception of height increases, update object validity is checked at the time the update is created, not when it is applied. In the case that tokens are being added, token transfer is attempted at this time and must succeed. 

```python
# Scheduling hooks

def before_add_to_schedule(update: Update):
    match type(update):
        case CreateDeposit:
            before_create_deposit(update)
        case AddTokens:
            before_add_tokens(update)
        default:
            pass

def before_create_deposit(update: CreateDeposit):
    """
    Check deposit does not already exist and that amount exceeds threshold.
    Transfer tokens or fail.
    """
    if not (
        not state.stake_registry.stakes[msg.sender] and    # deposit does not already exist
        update.amount >= minimum_initial_stake(update.height) # amount exceeds threshold
    ):
        raise
    bzz_token.transfer_from(msg.sender, this, update.amount)

def before_add_tokens(update: AddTokens):
    """
    Transfer tokens.
    """
    bzz_token.transfer_from(msg.sender, this, update.amount) # token transfer succeeds
```

#### Update schedule

An update schedule is a sequence of update objects recorded together with the round number at which the update becomes effective. The schedule only concerns itself with timings and not semantics of updates; it may treat update objects as opaque blobs.

```python
Schedule = set[ScheduledUpdate] # sequence order is order items were added
ScheduledUpdate:
    update: Update
    round: int
```

The following mutations on a schedule are possible:

* Add scheduled update with minimum wait.
* Pop next ready update (whose scheduled time has already arrived).
* Pop all updates (including those whose scheduled round has not yet arrived) and free resources.

We also define a read-only helper function that peeks all ready updates.

```python
# Assume standard queue operations peek_next, peek_last, add, and pop_next are defined.
# Assume schedule is iterable as an ordinary sequence (without popping items)

# read-only
def last_item_effective_from_round(schedule: Schedule):
    return schedule.peek_last().round

def add_with_minimum_wait(schedule, update: Update, minimum_wait: int):
    effective_from_round = min(
        state.current_round + minimum_wait, 
        last_item_effective_from_round(schedule)
    )
    schedule.add(ScheduledUpdate(update=update, round=effective_from_round))
    
def pop_next_ready(schedule) -> Update:
    next_item = schedule.peek_next()
    if next_item.round <= state.current_round:
        return schedule.pop_next()
    else:
        raise NoReadyItems
        
def pop_all_and_delete(schedule) -> list[Update]:
    updates = []
    while len(schedule) > 0:
        updates.append(schedule.pop_next().update)
    del schedule
    return updates

# read-only        
def peek_ready(schedule) -> list[Update]:
    updates = []
    for item in schedule:
        if item.round > state.current_round:
            break
        updates.append(item.update)
    return updates
```

The update schedule is FIFO, which means that items are scheduled in the order they were added. This property is ensured since all items are added through `add_with_minimum_wait`. 

```python
# constraint
is_fifo(schedule) = all([
    item_0.round <= item_1.round 
    for item_0, item_1 in pairwise(schedule)
])
```

The update schedule is *causal* if all scheduled items are scheduled in the future. A FIFO schedule may be made causal by iteratively popping all ready items.

```python
# constraint
is_causal(schedule) = all([
    item.round > state.current_round
    for item in schedule
])
```

When a new round starts, all scheduled updates whose round field equals the current round number come into effect. To maintain causality, these effective updates must be popped and applied.

```python
# dynamics
def on_new_round(schedule):
    while True:
        try:
            update = schedule.pop_ready()
            update.apply(state.stake_registry)
            del update
        except NoReadyItems:
            break
```

*Implementation note. EVM does not provide a means to schedule changes to its state. A state change can only be triggered by an external actor creating a transaction. Therefore, the EVM implementation of the schedule component must tolerate being non-causal. Client implementations SHOULD take responsibility for triggering accumulated round change events via the `applyUpdates` interface.*

#### Height decrease

Height decreases on an active stake position are disallowed.

> **ALIGNMENT POINT.** Height decreases can be blocked in a few different ways:
>
> 1. Block at scheduling time. This requires lookahead on all pending updates to see if the new height would be valid at application time, and increases the complexity of the queue.
> 2. Fail silently at application time. When applying an update that would decrease the height, simply do not honour the height change. From the perspective of the current interface, this is the lowest profile approach. However, it violates the principle that validity is checked at scheduling time and that scheduled updates will always be applied, which could lead to subtle errors in client implementations.
> 3. Block at interface level. Make the public API for changing height on an existing deposit take an unsigned integer *height increase* instead of the new height. Probably the cleanest solution but requires another public API change. 

#### Stake registry

The semantics following stake registry workflows are impacted:

* Create deposit
* Add tokens to existing deposit
* Change overlay address
* Increase height
* Decrease height (REMOVED)

Instead of writing directly to the stake record, each of the four remaining management workflows creates an `Update` object of the corresponding subtype, assigns a minimum wait, and places it on the queue via the `add_with_minimum_wait` pathway.

The new semantics of `manageStake` are captured by the `manage_stake` method:

```python
def classify_update(state, set_nonce: bytes, add_amount: int, height: int) -> list[type]:
    """
    Return subtype of update implied by parameters of call to manageStake.
    
    If updating an existing deposit, the call may combine multiple types.
    Since the three types of updates touch different fields in the stake record,
    the order of application does not matter.
    """
    if not state.stake_registry.stakes[msg.sender]:
        return [CreateDeposit(add_amount, set_nonce, height)]
    else:
        # Mutate existing deposit
        updates = []
        # Assume height increase since this validity check is done at application time
        updates.append(IncreaseHeight(height))
        if add_amount > 0:
            updates.append(AddTokens(add_amount))
        if derive_overlay(set_nonce) != state.stake_registry.stakes[msg.sender].overlay:
            updates.append(OverlayChange(new_overlay))
        return updates
    
MINIMUM_WAITS = {
    CreateDeposit: WAIT_BASE,
    AddTokens: WAIT_BASE,
    IncreaseHeight: WAIT_BASE,
    OverlayChange: WAIT_OVERLAY_CHANGE
}

def manage_stake(state, set_nonce: bytes, add_amount: int, height: int):
    """
    Classify updates into subtypes, check schedule-time validity,
    transfer tokens to stake vault if necessary,
    assign minimum waits, and add to schedule.
    """
    updates = classify_update(state, set_nonce, add_amount, height)
    for update in updates:
        match type(update):
            case CreateDeposit:
                # First item: must initialise queue object
                state.update_schedule[owner] = UpdateSchedule()
                before_create_deposit(update)
            case AddTokens:
                before_add_tokens(update)
        minimum_wait = MINIMUM_WAITS[type(update)]
        state.update_schedule[msg.sender].add_with_minimum_wait(update, minimum_wait)
```

With the exception of `addressNotFrozen` and `lastUpdatedBlockNumberOfAddress`, all view methods that read the stake record have changed semantics.

```python
def stakes(owner: EthAddress) -> Stake:
    record = state.stake_registry.stakes[owner].clone()
    for update in peek_ready(state.update_schedule[msg.sender]):
        record = apply_to(record, update)
    return record
```

Three other public API methods are defined by calling into the getter function above instead of reading the stakes table directly.

* `nodeEffectiveStake`
* `overlayOfAddress`
* `heightOfAddress`

#### Redistribution

Since the semantics of the `StakeRegistry` getter functions has changed, so too have the semantics of the three `Redistribution` functions that call them: `commit`, `reveal`, and `isParticipatingInUpcomingRound`.

Since the 2 round cool-off after a call to `manageStake` has been replaced with a delay managed by `UpdateQueue`, the following check in the logic of `commit()` is no longer needed and should be removed:

```solidity
        if (_lastUpdate >= block.number - 2 * ROUND_LENGTH) {
            revert MustStake2Rounds();
        }
```

(see https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Redistribution.sol#L303). 

Since `nodeEffectiveStake` is zero for a frozen node, frozen nodes cannot participate even when this check is removed. Nonetheless, the implementer MAY wish to add a freeze status check to `commit()` so that participation fails early for a frozen node, saving on computation.

## Rationale

* *One queue.* All types of updates for all stake owners are considered to be part of one queue. While some queue designs may allow for handling different owners or different update types in isolation, others — such as a global churn rate limiter — require tracking global state. To future proof the queue interface against possible changes to queue design, other components of the system must treat the entire network-wide queue as a single black box.

* *Separate UpdateQueue contract.* We propose the update queue be maintained in a separate contract from the Stake Registry for the sake of maximising modularity and isolating parts of deployments from unrelated future upgrades.

  For the sake of gas efficiency, the UpdateQueue contract could be inlined into the StakeRegistry. However, we find this to be a premature optimisation that gives up modularity for the sake of gas fees that are basically insignificant (millionths of a dollar) in practice.

* *2 round thaw.* The 2 round thaw currently implemented (but not fully documented) in the `commit()` method of the Redistribution contract is absorbed into this queue. The delay length is preserved as the `BASE_UPDATE_DELAY` parameter. However, unlike in the old model, participation is still allowed during the thaw period — but under the old stake position.

* *Signalling.* To act as a signal, node operators must be able to easily index enqueued updates along with the round number at which they come into effect. Since the `UpdateQueue` contract is responsible for tracking when updates come into effect, the events used for indexing must be emitted from there. There is no need to emit an event when the update is actually applied in state, which is inconsequential.

* *Per-neighbourhood delay scaling.* It may make sense to adjust the delay of changes depending on the before and after population of each neighbourhood affected by the change. The core example is to reduce delay for nodes leaving a neighbourhood with large population (and in the case of overlay change, entering one with small population). This would require the queue system to be able to estimate replication depth and enlarges the design space considerably, so we omit it from the present proposal.

* *Maximum queue length.* In principle, an update queue could grow so long that it cannot be emptied in a single block. Therefore, there shold be a maximum number of updates that can be held in the queue for each owner. It probably won't cause a big problem if the number is quite small, e.g. 10.

  An alternative approach would be to internally compose operations using an internal representation closed under composition. While we can imagine ways to do this for the set of operations the queue is currently expected to process, it would complicate the process of adding any new types of operation to the queue or changing the queue algorithm. A simple maximum queue length is easy to implement, universal, and unlikely to raise any serious objections.
  
* *Staker commitments.* Staker commitments, i.e. transfers to the stake registry and latest-price updates to committed stake, must be binding for the staker at the time the update is requested. The queue subsystem must be able to report up-to-date commitments. The effect of the new commitment (i.e. the new `committedStake` balance can be used in Redistribution) does not apply until after the delay.

* *Liability tracking.* The proposed changes mean that the `potentialStake` recorded under a given `owner` in the Stake Registry does not always equal the total amount of BZZ deposited by that owner (net of surplus withdrawals). Rather, the records of liabilities of the Stake Registry to a given owner are split between the Registry itself and the Update Queue. Since these records control what can be withdrawn by calling the `withdrawFromStake` and `migrateStake` methods, these processes must either block on not-yet-active updates, or fast track and apply them.

* *Manual queue triggering.* To preserve the getter interface of the `StakeRegistry` and make minimal changes to `Redistribution`, getter methods do not actually apply effective updates in place. However, the contract still needs a way to apply updates in place, or the queue will grow without bound, hence the `applyUpdates` endpoint. It is expected that clients will trigger `applyUpdates` regularly, either immediately after a new update comes into effect or before calling `Redistribution.commit()` during the next round that the overlay comes into proximity.

* *Update classification.* To apply different delays to different updates, updates need to be classified into types to be processed by the queueing system. Currently, the logic of `manageStake` implicitly classifies updates by the four non-reverting branches it takes, according to the independent predicates `(_addAmount > 0)` or `(_previousOverlay != _newOverlay)`. In the interests of allowing `UpdateQueue` to concern itself exclusively with queueing semantics, and not with staking, we propose that the responsibility of semantic classification of updates remain with `manageStake`, while `UpdateQueue` deals with sizes of updates.

* *Update encoding.* There are two basic approaches to recording the data of an "update" in the UpdateQueue:

  1. Record the new values to be applied in a struct.
  2. Directly encode the calldata of the call that will be made.

  Option (2) is future-proof in the sense that the same encoding will make sense if new types of update are introduced. OTOH it is less suitable for introspection than (1). We argue that the schedule itself should not be doing any introspection — it simply keeps track of *when* each update should be applied, and it is the caller's responsibility to hand it enough data to make that call. From this perspective, the opacity of an encoded call is also an advantage. 

  The matter of encoding is relevant to the interface because events must be emitted for each update. 

### Effect of waiting status on other components

* *Price oracle.* For the purposes of adjusting storage prices, the reveal counter could discount nodes currently waiting to exit a neighbourhood. The basic reason to do this is to allow prices to pre-emptively respond to an upcoming decrease in supply, and hence mean replication rate. However, there are quite a lot of questions about on what principles the design of this feature should be based and how it should be implemented.

  * Local or global: should we attempt to introduce the discount when a node participates, or track node height reductions with a global counter?
  * In the other direction, should prices pre-emptively decrease in response to height increases and new nodes?
  * What price manipulations possibilities does this open up? What is the effect of enqueueing strings of updates?

  And so on. Moreover, the way that node balancing and replication rate is tracked may change substantially in the near future with something along the lines of SWIP-39. Therefore, we'd rather defer implementing price oracle pre-emption.

* *Reward sharing.* For the advance signalling function of an exit queue to work, nodes must be incentivised to continue operating while they are in the queue. Hence, they must be able to continue participating in reward sharing (and penalties) using their previous participation metadata while waiting. Accordingly, they must participate in all the activities that qualify them for reward sharing, i.e. reserve consensus and storage and density proofs.

* *Freezing.* Under the current system, frozen nodes are not allowed to mutate stake records. The effect of this is that if a frozen node decides they wish to update their stake record, they must wait until the freeze ends, execute the update, and wait another 2 rounds to participate again. In other words, as well as blocking participation, freeze penalties delay executing changes to the stake record. This behaviour appears to be undocumented (cf. https://docs.ethswarm.org/docs/concepts/incentives/redistribution-game#penalties), and it's not clear if it's important.

  This SWIP does not propose to change this behaviour, but we note that its effects are exacerbated by introducing longer record update delays. A node operator who decides while frozen to update their stake record must wait the update delay sequentially after the freeze period. On the other hand, if an update is enqueued and *then* the node gets frozen, the freeze period and the update delay run concurrently. 
  
  Applying effective updates in state is purely a gas management measure, and does not affect any values that can be read from the contract. 
  
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

The main effect, which is intended, is to slow down and filter interactions with the stake registry, particularly those that could threaten data replication.

* Among the currently permitted changes, the most serious threat to stability comes from height reduction, which removes a node entirely from the service of a particular neighbourhood. Incentives to reduce height may include:
  * Save on storage costs by reducing commitment.
  * Maintain stake density after a drawdown.
  
  Under the present SWIP and SWIP-40, nodes will only be able to reduce their height by closing their stake position (incurring the appropriate delay) and then opening a new one with lower height.
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



