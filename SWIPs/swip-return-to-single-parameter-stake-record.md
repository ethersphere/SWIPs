---
SWIP: unassigned
title: Return to single-parameter stake record
author: Andrew Macpherson (@awmacpherson)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord)
status: Draft
category: Core
created: 2026-03-26
replaces: SWIP-20
---

# Return to single-parameter stake record

## Abstract

Revert the changes made in SWIP-20 and return to a single parameter staking system where revenue share is proportional to the number of tokens deposited.

## Motivation

SWIP-20 introduced a two-variable stake record that, in addition to the number of tokens deposited, tracks an internal counter "committed stake" which is used to compute the equity share in revenue distribution. The stated goal of this change was to allow users to withdraw some of their stake under certain conditions, giving them more optionality and making staking more attractive. 

Under SWIP-40, stake would become fully withdrawable and so the notion of "excess" stake is no longer meaningful. The internal variables and computations needed to track excess stake can be removed.

Reverting SWIP-20 is presented as a separate SWIP, intended to be implemented before SWIP-40 and SWIP-41, because it will be simpler to describe and implement 40+41 if we can assume this component is already gone.

## Specification

### Interface

The `Stake` object, which is the return type of the `stakes()` getter interface, is replaced with the following:

```solidity
struct Stake {
    // Overlay of the node that is being staked
    bytes32 overlay;
    // Stake balance (replaces)
    uint256 balance;
    // Block height the stake was updated, also used as flag to check if the stake is set
    uint256 lastUpdatedBlockNumber;
    // Node indicating its increased reserve
    uint8 height;
}
    
function stakes(address owner) public view returns Stake;

// PLACEHOLDER — superseded by SWIP-41
event StakeUpdated (
    address indexed owner,
    uint256 balance,
    bytes32 overlay,
    uint256 lastUpdatedBlock,
    uint8 height
);
```

The following interface components are removed:

```solidity
// methods
function withdrawFromStake();
function withdrawableStake() public view returns (uint256);

// events
event StakeWithdrawn(address node, uint256 amount);

// errors
error DecreasedCommitment();
```

The `PriceOracle` contract reference (`OracleContract`) is removed from the staking contract. It was only consumed by the committed stake computation in `manageStake` and by `calculateEffectiveStake`, both of which are removed under this proposal. The constructor parameter `_oracleContract` and the `IPriceOracle` interface import are also removed.

### Semantics

We describe semantics in terms of the following (Python pseudocode) model of EVM state:

```python
State:
    current_block: int
    stakes: dict[EthAddress, Stake] # Stake object defined as above
```

For everything except participating in redistribution, the new `balance` field in the stake record has exactly the semantics of the existing `potentialStake` field. Thus, a call to `manageStake` with positive `_addAmount` adds that many tokens to the `balance` field of the caller's stake account, and a call to `migrateStake` transfers out `balance` many tokens.

The part of `manageStake` responsible for computing `committedStake` is removed. This corresponds to [lines 141–149](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L141C45-L149C55) of `StakeRegistry.sol`. 

*The updated semantics of `manageStake` are to be fully defined in SWIP-41, which is intended to be deployed at the same time as this change. We suggest that this SWIP be implemented in the codebase before SWIP-41. The following can serve as a placeholder that compiles once the `committedStake` and withdrawable stake interface components are removed.*

```python
def derive_overlay(set_nonce: bytes):
    # existing logic of overlay address derivation pulling in network id and msg.sender

def manage_stake(state, set_nonce: bytes, add_amount: int, height: int):
    # if new deposit, check minimum initial stake threshold
    # check frozen status
    
    # update stake record
    new_balance = state.stakes[msg.sender].balance + add_amount
    new_overlay = derive_overlay(set_nonce)
    
    state.stakes[msg.sender] = Stake(
        overlay = new_overlay,
        balance = new_balance,
        last_updated_block_number = state.current_block, # removed SWIP-41
        height = height
    )
    
    # emit event if tokens added
    if add_amount > 0:
        log StakeUpdated(
            owner = msg.sender,
            balance = new_balance,
            overlay = new_overlay,
            last_updated_block = state.current_block, # removed SWIP-41
            height = height
        )
        
    # emit OverlayChanged if overlay changed
```

The *effective balance* of a stake position is defined to be either zero, if the position is currently frozen, or its balance. The semantics of the method `nodeEffectiveStake(address owner)` are to return the effective balance.

```python 
def node_effective_stake(owner: EthAddress) -> int:
    if address_not_frozen(owner):
        return state.stakes[owner].balance
    else:
        return 0
```

*This replaces a behaviour which defined effective stake of an unfrozen node in terms of its committed and potential stake. A helper function `calculateEffectiveStake` is no longer needed and may be removed.*

The methods `slashDeposit` and `migrateStake` reference the existing `potentialStake` field; these are mechanically renamed to `balance` with no change in semantics.

The redistribution contract consumes a stake position via the `nodeEffectiveStake` endpoint, read during a call to `commit()`. The updated semantics of participation are therefore to use the node's registered stake `balance` as a redistribution share.

## Rationale

The `StakeUpdated` event schema and emission logic inside `manageStake` is a placeholder that is replaced under SWIP-41. It is included to make this proposal self-contained as a well-defined change to the contract logic.

## Impact

**Protocol simplification.** SWIP-20 added significant protocol complexity, as evidenced by LOC and test count (10 as a proportion of overall code and tests of the stake registry. There has been at least one regression that necessitated a rapid contract redeployment, which could not have happened under a single variable system (or if stake were fully withdrawable). Anecdotally, the functioning of this subsystem does not seem to be widely understood among node operators.

**Unlock SWIP-40.** Retiring the committed stake system paves the way for fully withdrawable stake.

## Implementation

The internal function `calculateEffectiveStake` is no longer needed and may be removed.

