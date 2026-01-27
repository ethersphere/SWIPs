```yaml
---
SWIP: 40
title: Withdrawable stake
author: Andrew Macpherson (@awmacpherson)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord)
status: Draft
category: Core
created: 2024-08-07
---
```

# Withdrawable stake

## Abstract

Return the stake record data model to a single variable system in which a node's share of redistribution is proportional to the number of tokens deposited. Make stake fully withdrawable except while frozen or while participating in a round.

## Motivation

* Swarm's staking model does not generally allow withdrawal of stake, except during smart contract migrations. 
* There is an intricate notion of "excess stake" that can be withdrawn, after [SWIP-20](https://github.com/ethersphere/SWIPs/blob/master/SWIPs/swip-20.md) "improved staking." This concept substantially complicates the codebase — 1/3 of the tests for the stake registry are testing this function — 
* The fact that Swarm stakers generally cannot recover their principal except via revenue makes staking a risky prospect, akin to a small venture investment. It's likely that only larger operators will be prepared to take such risks, exacerbating inequality among noder operators. Conversely, the current capacity of the investment is likely too small to attract the interest of sophisticated operators.
* It also goes against the common understanding of what "stake" is.
* Making stake recoverable actually gives the system more leverage over node operators to behave well, potentially enhancing system service quality — the system can threaten penalties over the principal, instead of only over future revenue.

## Specification

Instead of using one field (`potentialStake`) to track a liability to the owner and a second, computed field (`committedStake`) to define the owner's equity in the redistribution game, return to a single field that fulfils both roles. In other words, a staker's stake balance is exactly their equity in redistribution. Revert SWIP-20. 

A node's "effective stake," as defined by the return value of the public function `nodeEffectiveStake`, is either its stake balance, or zero if the node is frozen.

The stake registry gets two new workflows:

* Draw down stake — withdraw some tokens, but remain in the stake table with the same overlay and height commitments.
* Exit stake — withdraw position completely and clear the stake record.

One old workflow is eliminated:

* Withdraw "excess" stake — implemented by the function `withdrawFromStake()`, which no longer needs to exist.

### Interface

The stake record data model is modified as follows:

```solidity
/* OLD

    struct Stake {
        // ...
        uint256 committedStake;
        uint256 potentialStake;
        // ...
    }

*/ 

// NEW 

    struct Stake {
        // ...
        uint256 balance;
        // ...
    }
```

Correspondingly, all methods and event schemata that reference those fields are modified:

```solidity
/* OLD

    event StakeUpdated(
        // ...
        uint256 committedStake,
        uint256 potentialStake,
        // ...
    );
    
*/ 

// NEW 

    event StakeUpdated(
        // ...
        uint256 balance,
        // ...
    );
```

The following new methods are added:

```solidity
// Withdraw `amount` from stake position of `msg.sender`.
// Atomically reduce `balance` and transfer tokens in the same amount.
// Raise error if this would reduce balance below minimum stake.
// SWIP-41: place withdrawal request on update queue, but do not update records or transfer tokens
function withdraw(uint256 amount) public;

// Delete stake record of `msg.sender` from table and return all tokens.
// Atomically reduce `balance` to zero and transfer `balance` tokens to sender.
// SWIP-41: place exit request on update queue, but do not update records or transfer tokens
function exit() public;
```

The following public methods and errors are removed completely:

```solidity
function withdrawFromStake() external;
function withdrawableStake() public view returns (uint256);

error DecreasedCommitment();
```

### Semantics

The semantics of the following methods are impacted:

```solidity
function manageStake(bytes32 _setNonce, uint256 _addAmount, uint8 _height) external;
function nodeEffectiveStake(address _owner) public view returns (uint256);
```

as follows:

* `manageStake` — straightforward elimination of logic computing `committedStake`. Compute updated balance, write updated balance to stake record, and emit an event. The computation in [lines 141–149](https://github.com/ethersphere/storage-incentives/blob/v0.9.4/src/Staking.sol#L141C45-L149C55), including the branch that raises `DecreasedCommitment` error, is removed. The `DecreasedCommitment` error type is not used, and can be removed. 
* `nodeEffectiveStake(address _owner)` — simply returns the owner's `balance`, or zero if frozen.

## Rationale

* An option to fully withdraw stake under typical network conditions makes staking a much more attractive, low-risk investment opportunity. Because principal is not at risk, it improves the accessibility of staking to risk-averse operators such as those with worse acess to capital. It also makes the opportunity easier to compare on a like-for-like basis with other staking systems. For a more detailed analysis, see [here](https://mirror.xyz/shtuka.eth/qQnVGyNL7viiS5iLizSVL_0eTTMYGavl3Kb77XiaBxk).
* Since the main negative incentives active in Swarm Protocol today are based on freezing, exiting stake cannot be a method to evade freezing. That is, frozen nodes cannot be allowed to withdraw.
* Although additional frictions or conditions, such as a withdrawal delay, could be imposed on withdrawals, this proposal represents the simplest possible approach, could be deployed immediately, and doesn't make incentives to stay online any worse.

## Implementation notes

TODO

## Security implications

* We expect that this will result in more money being held in the stake registry contract, which accordingly scales the security concerns.

* *Instant unfreeze.* Frozen accounts cannot be allowed to withdraw. Otherwise, a depositor could evade freezing by simply withdrawing and opening a new account.

* *Consensus penalty evasion.* If withdrawals are allowed in the middle of a round, a depositor who commits but does not reveal, or one who reveals but considers the risk of being found in disagreement too high, can evade Non-revealed or Disagreement penalties by quickly withdrawing. To make these penalties effective, withdrawals in the middle of the round should therefore be restricted, at least until the end of that round.

  Either of the following restrictions would prevent penalty evasion:

  * Preventing withdrawal if the owner has already committed in the current round. This requires the withdraw function to carry a reference to the Redistribution contract.
  * A withdrawal delay of at least one round.

* *Shadow stake.* Withdrawals enable a strategy in which a large amount of stake is temporarily deposited in order to skew the leader election contest. Currently, the stake update cool-off period embedded in the `commit()` method prevents this strategy from being carried out after the round anchor is revealed. Upgrades should take care to preserve some thawing period after depositing (including topping up) stake.

## Economic implications

* Staking becomes substantially less risky because principal is not at risk, nor even particularly illiquid.
  * When slashing is introduced, principal is again at risk, but only in case of abnormal conduct.
  * When withdrawal delays are introduced, liquidity is impacted.
* The value of the principal gets added to the value of stake positions. This makes the value of staked BZZ comparable with other yield bearing assets such as treasuries. The market will likely accept a much lower yield per token ($r$ instead of $1+r$ ) and hence support a much larger deposit base ($Y/r$ instead of $Y/(1+r)$).
* Staking becomes accessible to a wider variety of economic actors.
* The main threat to network stability imposed by exiting nodes is the same as that of changing overlay or reducing height via the `manageStake` endpoint: the replication rate of an address block decreases. It is therefore natural that a measure applied to disincentivise one of these actions also be applied equally to the others. Currently, the only disincentive to `manageStake` is the 2 round participation freeze it induces, which cannot logically apply to exits. The current proposal therefore maintains approximate incentive parity between exiting and changing neighbourhood commitment.

### Liquidity incentive

Currently, for a staked node sitting out of participation is disincentivised only by loss of revenue. Unstaking has the positive incentive of making capital immediately available, and implies sitting out of participation. So we have
```math
V(\neg \mathrm{Participate}) = O - R
```
where $O$ is the variable operating cost of running the node and $R$ is the revenue from participation. On the other hand,
```math
V(\mathrm{Unstake}) = LB(s) + O - R
```
where $LB(s)$ is the liquidity bonus of having $s$ BZZ liquid instead of staked. Since instantly withdrawable stake is close to liquid, $LB(s)$ is likely to be pretty small here except in times of high trading activity when stakers may prefer to immediately trade their BZZ or post them as liquidity on an exchange.

In times of high trading activity (high volatility, high volume), instantly withdrawable stake therefore entails a risk of higher node churn and potential network instability.

## Interactions with other proposals

* **SWIP-39.** Automatic address allocation is only binding if it is economically infeasible to reroll many times to achieve a desired prefix. Under the proposed scheme, withdrawals are instant and almost free, so they do not add any Sybil resistance to this scheme. Sybil-resistance could be introduced in a controlled manner by adding a tax or delay to withdrawals.
* **Non-custodial stake registry.** A non-custodial model for the stake registry separates the actions of *deregistering* stake, which disencumbers assets from their commitment to participation in the redistribution contest, and *withdrawing,* which actually transfers the assets out of the target account. In a non-custodial model, all references to "withdrawals" in the current proposal should apply specifically to deregistrations rather than moving assets, and its conditionals should be implemented within the redistributor contract which checks the conditions when the owner requests the lock be released.

## Alternative approaches

* **Withdrawal delay.** There are a few reasons that it may be desirable to enforce a delay on withdrawing assets after the intention to withdraw has been telegraphed. In this case, at least two actions would be required to withdraw: commit to withdraw, and execute withdrawal. For simplicity, this proposal specifies a single-action instant withdrawal.
* **Withdrawal queue.** In a system with a withdrawal delay, impose a hard limit on the number of nodes that can be waiting to exit at any one time. This is how Ethereum validator exits work. So far, we haven't established a need for this feature, which adds more complexity.
* **Address-based withdrawal restrictions.** Some discussions floated the idea of limiting withdrawals of nodes whose absence would cause the overlay address population to become "unbalanced" (for example, withdrawals from neighbourhoods that are already underpopulated).
* **Withdrawal tax.** Instead of being fully withdrawable, stake exits incur a fixed burn of some amount. The amount can be used to control the cost of exiting and re-entering, which in turn could be deployed as a mechanism to improve network stability.
