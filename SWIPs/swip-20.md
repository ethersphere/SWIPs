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

Currently, a storer node's stake to buy their way into the redistribution game, is permanently locked which means that returns on this stake are solely based on the ROI of the redistribution game. The purpose of this SWIP is to change this and allow users to withdraw part of their stakes.


## Objectives

Should the value of BZZ increase then the node operators value that is staked increases in USD, they should be able to withdraw the appreciation, i.e., the portion of the value that is above the amount required on initial stake to play and safeguard the system.
How it works is if BZZ price goes up, more node operators join because of that, the storage price goes down which makes commitedStake value in BZZ lower than potentialStake, which means the node operator can take out funds.


## Context

Currently, the smart contract can only increase a node's stake by sending additional collateral. Importantly, it does not allow node operators to  decrease their stake or any other way to fully or partially withdraw their stake. This limitation is what will be changed with this feature.


## Specification

This section describes how stakes should be created, modified, computed, and withdrawn. Since this is orchestrated by the [**Staking Contract**](https://github.com/ethersphere/storage-incentives/blob/master/src/Staking.sol), implementing this SWIP consists predominantly of changes to this smart contract. 

### Concepts

#### *balance or potential stake*
The contract keeps a balance of BZZ tokens associated with a node address (not an overlay as of SWIP-19). Every time a `manageStake` function is called, the amount of BZZ sent with the transaction is added to this balance.

#### *committed stake*

The committed stake is not denominated in BZZ, but in the commodity unit that it is meant to secure: unit price of storage rent. It is saved with that value.
  
Expressed in BZZ value can be obtained as `committedStake * unitPrice`. Initially, the committed stake aligns with the balance, in that the node's committed stake in BZZ is fully covered by the node's balance, however as the unitPrice changes (as a consequence of either cost changes, competition, or BZZ token price change), the committed stake can be under or overcollateralized by the actual stake balance.
 
#### *Effective stake*

The effective stake is the committed stake expressed in BZZ that has collateral.


### The stake endpoint

through calling `manageStake` function 
1.  The Staking contract accepts the same arguments as before, which are addAmount and setNonce
2.  The contract then adds the amount to the stake entry for the address of the sender and transfers funds from node address to contract.
 This sum can be referred to as the *potential stake balance*, denoted as `potentialStakeBalance`.
3. Contract also calculates committedStake as value that is derived from addAmount/unitPrice, unitPrice is gathered from priceOracle contract with currentPrice() function.

### The new withdraw stake endpoint
Withdrawal comprises the following steps:

1.  Calculate the *effective stake* as:
```
    effectiveStake = min(committedStake * unitPrice, potentialStakeBalance)
```
2.  Calculate the *surplus stake* as:
```
    surplusStake = potentialStakeBalance - effectiveStake
```
3.  If `surplusStake > 0` then the contract sends `surplusStake` back to the sender

### The stake accessor endpoint

Most importantly, the function called by the redistribution contract that calculates the stake of an address will return the *effective stake* (as per step 1 above) rather than the *potential stake balance* as it currently does.

The calculation of the stake amount used for the weights determining truth and winners
![](assets/swip-20/stake-definition.png)


## Implementation notes

### Minimum stake

Currently, the minimum stake is checked [in the redistribution game contract](https://github.com/ethersphere/storage-incentives/blob/master/src/Redistribution.sol#L300). If the amount is found to be less than the minimum stake the commit fails. Without any further changes to the contract, this is a discrepancy.
Instead, the staking contract should perform this check only once when the stake is registered for a particular node. Most importantly if the price of BZZ goes up and the committed stake is covered by less than 10 BZZ, then the node is allowed to withdraw the surplus. It is important that in this case the minimum stake requirement is no longer enforced. 
Conversely, if the price of BZZ decreases and the minimum stake is worth less, no additional checks are required. 


### Swarm API changes
- *API Stake endpoint:*
   For the staking node, the parameters that are set are the same as in swip-19, which are value and nonce
- *API Stake accessor:*
  Changes are already done in swip-19, where we access stake values keyed with node address
- *API support for withdrawal:*
  API endpoint for excess stake withdrawal should be added to the client. "withdrawFromStake" is a function to be called, no parameters are needed. 
- To get the value of possible stake to withdraw calling "withdrawableStake" function will return the value denominated in BZZ
- "usableStakeOfAddress" will return effective stake value which is also used in the redistribution game, also we are changing this to "nodeEffectiveStake" function
- There is also "migrateStake" endpoint, no parameters are needed. This will be used for possible future migrations.


The client code should be amended to be compatible with the new ABI for the staking contract.


### UX recommendations
Any UX for staking would benefit from displaying relevant context to users when they are selecting parameters:
- **Current value of (potential) stake balance:** Display the current amount of stake that has been staked by the user. 
- **Surplus balance:** Display any surplus balance that is available for withdrawal if any (how to calculate this is mentioned above).

  
## Backward compatibility

Upgrading the staking contract implies pausing the old version, making backward compatibility irrelevant.
Since new contract addresses are hard coded into the client code, operators should upgrade their client in order to participate in the storage incentive game.

<!-- Question: would currently staked nodes be able to withdraw after the upgrade, or would they need to re-stake, with the previous stake lost? -->

## Contract migration
Due to the contract upgrade, the deployment of this SWIP involves a migration process. As part of this, the old staking contract will be paused, allowing users to withdraw their stake and reinvest in the new staking contract with new parameters. This process facilitates the free movement of stakes when changing neighborhoods and necessitates a user-story testing session to ensure the migration steps are clear and functional.


## Test cases

0. Bootstrapping:
	- Manually set price oracle to a unit price of `0.1`
	- Set up nodes `A` and `B`
1. Test cases
	- Check that staking below the required minimum fails with the appropriate error 
    	- Manually change the price in the price oracle
    	- Confirm if it is possible to withdraw funds from the stake after the change
    	- Check if, when the price goes up, you can withdraw your excess
     	- Check that we can migrate funds when a contract is paused

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
