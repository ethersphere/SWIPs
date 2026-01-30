```yaml
---
SWIP: 40
title: Withdrawable stake
author: Andrew Macpherson (@awmacpherson)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord)
status: Draft
category: Core
created: 2024-08-07
requires: SWIP-41
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

An option to fully withdraw stake under typical network conditions makes staking a much more attractive, low-risk investment opportunity. Because principal is not at risk, it improves the accessibility of staking to risk-averse operators such as those with worse acess to capital. It also makes the opportunity easier to compare on a like-for-like basis with other staking systems. For a more detailed analysis, see [here](https://mirror.xyz/shtuka.eth/qQnVGyNL7viiS5iLizSVL_0eTTMYGavl3Kb77XiaBxk).

## Specification

Instead of using one field (`potentialStake`) to track a liability to the owner and a second, computed field (`committedStake`) to define the owner's equity in the redistribution game, return to a single field that fulfils both roles. In other words, a staker's stake balance is exactly their equity in redistribution. Revert SWIP-20. 

A node's "effective stake," as defined by the return value of the public function `nodeEffectiveStake`, is either its stake balance, or zero if the node is frozen.

The stake registry gets two new workflows:

* Draw down stake — withdraw some tokens, but remain in the stake table with the same overlay and height commitments.
* Exit stake — withdraw position completely and clear the stake record.

One old workflow is eliminated:

* Withdraw "excess" stake — implemented by the function `withdrawFromStake()`, which no longer needs to exist.

### Parameters

We introduce two new parameters to control the delay

| Name                     | Semantics                                                    | Comment                                 |
| ------------------------ | ------------------------------------------------------------ | --------------------------------------- |
| `DELAY_STAKE_WITHDRAWAL` | Minimum wait in rounds before executing stake withdrawal or exit. | Should be `>= DELAY_CAPACITY_REDUCTION` |

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
// Raise error if owner is frozen.
// SWIP-41: place withdrawal request on update queue, but do not update records or transfer tokens.
// Tokens cannot be transferred out if node is frozen.
function withdraw(uint256 amount) public;

// Delete stake record of `msg.sender` from table and return all tokens.
// Atomically reduce `balance` to zero and transfer `balance` tokens to sender.
// Raise error if owner is frozen.
// SWIP-41: place exit request on update queue, but do not immediately update records or transfer tokens.
// Update cannot be applied if tokens are frozen.
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

* *Withdraw/exit separate public methods from `manageStake`*. The `manageStake()` endpoint is already overloaded with five different workflows (create deposit, top up deposit, change overlay, increase height, decrease height). It contains four conditional branches and touches every part of the stake record. Withdrawal or exit are logically distinct actions from any of these, and there is no reason to bundle them into the same function.
* *Withdraw and exit separate methods.* Exit could have been implemented as simply "withdraw down to zero." Optionally, the method could decide to clear the stake record on a call that would reduce balance to zero. We chose this design because it  matches the natural split from a user decisioning perspective between a "drawdown" and "exit" action, the zero-parameter `exit()` method matches the simplicity of the decision itself (and is more gas efficient than `withdraw()`), and to minimise conditional branching and overloading of individual methods.
* *Frozen accounts cannot withdraw.* Swarm Protocol uses participation freezes to penalise consensus or commit-reveal faults. If the owner could draw down or exit the frozen stake position, he could reduce the impact of the freeze penalty; worse, the funds can be redeposited in the same neighbourhood to recover the income lost to freezing. Therefore, frozen nodes cannot be allowed to withdraw funds during the freeze period.
* *Same wait time for drawdowns and exits.* In principle, a drawdown is less impactful than an exit: the former doesn't necessarily entail a reduced service to the network. A drawdown therefore *could* reasonably be given a shorter wait time than an exit, at the cost of introducing one additional protocol parameter. In practice, we don't see is a clear enough benefit to allowing faster drawdowns to justify the added complexity. This is especially true given the current low minimum stake, which renders drawing down to the minimum roughly payoff equivalent to exiting.

## Security implications

* We expect that this will result in more money being held in the stake registry contract, which accordingly scales the security concerns.

* *Instant unfreeze.* Frozen accounts cannot be allowed to withdraw. Otherwise, a depositor could evade freezing by simply withdrawing and opening a new account.

* *Consensus penalty evasion.* If withdrawals are allowed in the middle of a round, a depositor who commits but does not reveal, or one who reveals but considers the risk of being found in disagreement too high, can evade Non-revealed or Disagreement penalties by quickly withdrawing. To make these penalties effective, withdrawals in the middle of the round should therefore be restricted, at least until the end of that round.

  Either of the following restrictions would prevent penalty evasion:

  * Preventing withdrawal if the owner has already committed in the current round. This requires the withdraw function to carry a reference to the Redistribution contract.
  * A withdrawal delay of at least one round.

* *Shadow stake.* Withdrawals enable a strategy in which a large amount of stake is temporarily deposited in order to skew the leader election contest. Currently, the stake update cool-off period embedded in the `commit()` method prevents this strategy from being carried out after the round anchor is revealed. Upgrades should take care to preserve some thawing period after depositing (including topping up) stake.

## Economic implications

*For new nodes.* The option to withdraw makes staking significantly more attractive: lower risk, higher reward per unit TVL. Indeed, the value of a position under these changes is bounded below by the liquidation value of the staked assets, suitably discounted by the withdrawal delay and the risk of freezes (which is very low because an operator that wishes to withdraw can reliably avoid freezes by refraining from participating). Hence, we expect that this change would lead to a significantly larger TVL owned by a more diverse set of stakers, including those with lower risk appetites.

*For existing nodes.* Since these changes would be deployed in a new stake registry contract and old stake migrated, any stake "trapped" in the old registry (attached to nodes whose operators wish to wind down their operations) will simply be withdrawn and never redeposited in the migration. There is no reason to expect any stake outflow in excess of what would normally be seen in a migration.

For nodes that do choose to make the migration, staking has just become more attractive, by the same logic as above. Stake inflows associated to new nodes increases the amount of stake required to break even on revenue share. We therefore expect to see substantial increases in stake balance among migrating nodes.

*Dynamics.* Allowing stake outflows will likely significantly increase the amount of activity in the staking pool. Nodes that have stopped operating are incentivised to signal that they have done so by withdrawing their stake. Onchain stake records become a more accurate predictor of how much stake will participate in redistribution. We recommend the community closely monitor inflows and outflows.

*Pricing stake positions.* Stake inflows and outflows can be viewed as trade in both directions between unstaked BZZ and stake positions. Allowing trade in both directions allows these products to be priced efficiently. Because stake positions and BZZ can be converted on a 1-1 basis with a delay, pricing the trade is a matter of maturity transformation. We expect that the TVL of Swarm stake will grow until the marginal yield earned by a staked BZZ token balances exactly against the liquidity penalty implied by the withdrawal delay. The volume of stake churn (inflows + outflows) is a measure of the strength of the signal pricing staked BZZ as an asset class.

*Signalling drawdowns and exits.* The enforced withdrawal delay means that nodes must signal their exit or drawdown a number of rounds before executing it and recovering their tokens. During this time, it is expected that they continue participating and earning rewards. The signal is not entirely reliable: if the operator changes their mind and decides they wish to stay while waiting to exit, they can simply re-enter shortly after exiting with only a short downtime penalty. That is, while the signal is necessary for a drawdown or exit to occur, it doesn't guarantee that the same operator will remain drawn down or exited for any significant length of time.

*Filtering drawdowns and exits.* The enforced withdrawal delay prevents nodes from drawing down their stake in order to deploy capital into a short-lived opportunity — certainly, at least, an opportunity expected to last for less than the delay period. This includes the case of drawing down capital to deploy it onto another node, but note that an overlay change can bypass this delay to achieve a similar effect. Depending on the length of the delay, this can have a substantial damping effect on stake churn. We recommend that stake churn be monitored with the goal of estimating its relation to exit delay length.

*Economic security.* Topping up or drawing down stake increases or reduces the economic security staked against consensus penalties, namely, failure to reveal or faulty reveal (in disagreement with the consensus leader). Since the expected effect of this proposal is a substantial increase in stake deposits, a corresponding increase in economic security is also anticipated. As long as the distribution of stake across the address space remains stable, stake churn has little effect on economic security in and of itself.

*Quality of service.* Node inflows and outflows increase and reduce the service quality of the network, respectively. Rapid changes in node population, even if the overall count remains stable, impacts service as new nodes must spend time syncing their reserve, a process that takes hours per neighbourhood. New node entries also have a resource impact on their neighbours, who must use bandwidth serving pullsync request, though we believe that in the current network configuration this effect is modest. The cost of entry and exit should therefore be carefully tuned to limit node churn and achieve a desired service quality. 

The main method we have to control the cost of entry and exit is the minimum delay period. Concretely, the larger of the deposit and withdrawal delays puts a hard limit on how often a given BZZ token can be moved in and out of stake.

* A long drawdown delay makes depositing costly by attaching it to a long commitment to lock capital in Swarm. 
* A long exit delay makes entry costly by attaching it to a long commitment to provide storage to Swarm (except the commitment is only really there if stake is also locked).
* A long deposit delay makes drawdowns costly by blocking the tokens from earning Swarm revenue. (This applies if tokens must be deposited at the start of the wait period.)
* A long entry delay makes exits more costly by blocking resources from earning Swarm revenue. (If resources must be committed to participate at the start of the wait period, which is really not the case without slashing if the node cannot earn revenue.)

What cannot be achieved with an exit delay is to slow down the rate of nodes exiting with the intention to stay exited for a longer period. The benefit is in (i) filtering out short-termist stake churn, and (ii) discouraging mercenary capital in the first place.

*Cheap option.* If withdrawal delay is long relative to deposit delay, a depositor can acquire a "cheap periodic option" to exit by immediately enqueueing a withdrawal after his deposit. The option can be made more expensive by increasing the proportion of time the deposit must spend not earning rewards.

## Implementation notes

* We recommend this proposal be implemented in two phases:

  1. Revert SWIP-20 and remove `withdrawFromStake`, `withdrawableStake`, and `DecreasedCommitment`
  2. Implement exit and withdrawal endpoints.

  SWIP-41 can be implemented between the two phases so that the queue infrastructure is present to provide exit and withdrawal endpoints with suitable delays.

* These changes require a new StakeRegistry contract to be deployed. Because the StakeRegistry reference is hardcoded in the Redistribution contract, a new Redistribution contract would also need to be deployed. Access to the Postage contract would be granted to the new Redistribution contract and revoked from the old one.

* In the current release model of bee, a new version of bee is required to integrate the new contracts. In principle, a bee node that is unmodified other than to update its reference to the contracts could continue to stake and participate as before. However, the interface would need to be updated to be able to integrate with withdrawal or exit, and forecasts of revenue share would need to reflect the simplified logic.

## Interactions with other proposals

* **SWIP-39.** Automatic address allocation is only binding if it is economically infeasible to reroll many times to achieve a desired prefix. Under the proposed scheme, withdrawals are instant and almost free, so they do not add any Sybil resistance to this scheme. Sybil-resistance could be introduced in a controlled manner by adding a tax or delay to withdrawals.
* **Non-custodial stake registry.** A non-custodial model for the stake registry separates the actions of *deregistering* stake, which disencumbers assets from their commitment to participation in the redistribution contest, and *withdrawing,* which actually transfers the assets out of the target account. In a non-custodial model, all references to "withdrawals" in the current proposal should apply specifically to deregistrations rather than moving assets, and its conditionals should be implemented within the redistributor contract which checks the conditions when the owner requests the lock be released.

## Alternative approaches

* **Withdrawal delay.** There are a few reasons that it may be desirable to enforce a delay on withdrawing assets after the intention to withdraw has been telegraphed. In this case, at least two actions would be required to withdraw: commit to withdraw, and execute withdrawal. For simplicity, this proposal specifies a single-action instant withdrawal.
* **Withdrawal queue.** In a system with a withdrawal delay, impose a hard limit on the number of nodes that can be waiting to exit at any one time. This is how Ethereum validator exits work. So far, we haven't established a need for this feature, which adds more complexity.
* **Address-based withdrawal restrictions.** Some discussions floated the idea of limiting withdrawals of nodes whose absence would cause the overlay address population to become "unbalanced" (for example, withdrawals from neighbourhoods that are already underpopulated).
* **Withdrawal tax.** Instead of being fully withdrawable, stake exits incur a fixed burn of some amount. The amount can be used to control the cost of exiting and re-entering, which in turn could be deployed as a mechanism to improve network stability.

## Testing strategy

TODO
