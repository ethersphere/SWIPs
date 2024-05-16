---
SWIP: 20
title: Improved staking - allowing excess stake withdrawal
author: György Barabás <gyorgy@ethswarm.org> (@dysordys), Viktor Trón <viktor@ethswarm.org> (@zelig)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Core
created: 2024-05-08
---


## Abstract

Currently, one's initial capital, invested as stake, is permanently locked. This means that returns on this stake is purely based on the ROI of the redistribution game. The purpose of this SWIP is to change that: in extenuating circumstances, users will be allowed to withdraw their stakes.


## Objectives

Should the effective price of a user's stake increase, they should be able to withdraw the appreciation, i.e., the amount that is no longer representative of the capital required to play and safeguard the system.


## Context

Currently, the smart contract can only increase a node's stake by sending extra collateral. Importantly, it does not allow node operators to  decrease their stake or any other way fully or partially withdraw their stake. This is what will be changed with this feature.


## Specification

This part describes how stakes should be created, modified, computed and withdrawn. As a first step, we need to obtain the *committed stake* of the user. This is set by user action, based on the following procedure:

### The stake endpoint
1.  The contract accepts an extra argument, `committedStake`, which sets the committed stake.
2.  The contract asks the price oracle for the unit price of storage -- let us denote it with the symbol `unitPrice`.
3.  The contract then adds whatever amount is sent with the transaction to the  stake entry for the address of `txorigins`. We can call this sum the *potential stake balance*, and denote it with the symbol `potentialStakeBalance`.

### The new withdraw stake endpoint
withdrawal comprises the following steps:

1.  Calculate the *effective stake* as:
```
    effectiveStake = min(committedStake * unitPrice, potentialStakeBalance)
```
2.  Calculate the *surplus stake* as:
```
    surplusStake = potentialStakeBalance - effectiveStake
```
4.  If `surplusStake > 0` then send `surplusStake` back to `txorigin`

Most importantly, the function called by the redistribution contract that calculates the stake of an overlay should now return the *effective stake* (as per step 1 above) rather than *potential stake balance* as it currently does.

![](assets/swip-20/stake-definition.png)


## Implementation notes

### Minimum stake
Currently the minimum stake is checked in the redistribution game contract. If the amount is found to be less than 
Without any further changes to the contract, this is a discrepancy.
Instead, the contract should check only once when the stake is registered for a particulat node. Most importantly if the price of BZZ goes up and the committed stake is covered by less than 10BZZ then the node is allowed to withdraw the surplus. It is important that in this case the minimum stake requirement is no longer checked. 
Conversely if the price of BZZ goes down and the minumum stake is worth less, no extra check is needed. 

### Neighbourhood hopping

We are changing the contracts, specifically the staking contract, to attribute stake to the address and not the overlay. This will allow stake to be moved when changing neighbourhoods, and allow nodes to migrate and distribute themselves across the network. (see SWIP-19)

### Swarm API changes
 - *API Stake endpoint* 
   for the staking node, the value for committed stake should be solicited as user input in the form of an added request parameter.
- *API support for withdraw*
  API endpoint for excess stake withdrawal should be added to the client.

The client code should be amended to work with new ABI for the staking contract.


### UX recommendations
Any UX for staking would benefit from showing some context to the user when selecting parameters:
- current value of committed stake
- potentual maximum committed stake
	- calculated from the current stake balance and the unit price as per the price oracle 
- the amount of BZZ  needed to be sent with the transaction when creating or modifying stake
	- when attempting to set commited stake amount above this value
- Surplus balance 
	- available to withdraw

  
## Backward compatibility

Since upgrading the staking contract implies pausing the old version, backward compatibility is irrelevant.
Since the new contract addresses are hard coded in client code, 
In order to play the storage incentive game, operators should upgrade their client.

<!-- Question: would currently staked nodes be able to withdraw after the upgrade, or would they need to re-stake, with the previous stake lost? -->

## Contract migration
Due to the contract upgrade, deployment of this SWIP involves a migration process. As part of this, the old staking contract will be paused, which allows users to withdraw their stake and then reinvest in the new staking contract with new parameters to move stake freely when changing neighbourhoods. This will need a user-story testing session of the process and steps.


## Test cases

0. bootstrapping:
	- manually set price oracle to unit price to `0.1BZZ`
	- set up nodes `A` and `B`
1. initial staking
	- check staking below required minimum fails with proper error 
	- check staking A with 10BZZ and 101 as value of committed stake should fail with proper error
	- stake A 10BZZ with 100 as the value for committed stake should succeed. 
	- stake B with 1,000BZZ should succed with 10,000 as the value for committed stake should succeed. 
2. modifying stake balance and committed stake
   - check if increasing A's committed stake to 200 without sending extra BZZ fails with proper error
	- send A 10 BZZ with a transaction to a total stake at 20 (still leaving 100 as committed stake) 
   - send 90,000 BZZ with a transaction to a total stake at 100,000 (still leaving 10,000 as committed stake) 
   - stake
   - resetting committed stake
3. manually change price oracle price
  - Once that is done, check if one can withdraw funds from the stake
  - check if the price of BZZ goes up you should be able to withdraw your excess as per the operator  

- 
A question for an imagined worst-case scenario: if BZZ increases incrementally, which incentivizes nodes to withdraw funds, and this happens simultaneously for many nodes, could that put the network as a whole in danger?


## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
