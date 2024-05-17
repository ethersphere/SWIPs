---
SWIP: 19
title: Neighbourhood hopping
author: György Barabás <gyorgy@ethswarm.org> (@dysordys), Viktor Trón <viktor@ethswarm.org> (@zelig)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track   
category: Core
created: 2024-05-08
---


## Abstract

This SWIP describes the process to support **neighbourhood hopping**, i.e., moving a node to another neighbourhood without the need to pay the stake each time.

## Objectives

Enable a node to change its overlay address while preserving the stake it already possesses.


## Context


Neighbourhood hopping is currently supported by the Bee client. The overlay address, which specifies which neighbourhood a node falls into, is derived by hashing the node key together with an arbitrary overlay nonce chosen by the user (refer to the figure below). 

![](assets/swip-19/overlay-definition.png)

Bee already supports placing one's node in an arbitrary neighbourhood by mining an overlay nonce that will result in the corresponding neighbourhood.

Currently, the staking smart contract associates a stake with an overlay address. Therefore, neighbourhood hopping requires the node operator to re-stake their node each time they change neighbourhoods. This is considered unfair and contrary to the system's ethos, as the ability to change neighbourhoods fluently is essential for the balanced distribution of nodes across the network.


## Specification

To support neighbourhood hopping with transferable stakes, the staking contract should register the user's Ethereum address instead of their overlay address.


## Implementation notes

The implementation requires two indices: one keyed by the Ethereum address and another one keyed by the overlay address, as was previously the case. The staking API already requires the sender to send the so-called overlay nonce to the nodes to calculate the overlay address. Therefore, there will be no changes to the interface functions; however, their semantics will shift. Now, if a new overlay nonce is provided, the existing node overlay address should be removed.

The stake endpoint:
1. Look up the stake in the index by Ethereum address.
2. If the stake is not found, insert it in the same index, with the overlay calculated from the address and the nonce provided in the transaction data. Then proceed to step 4.
3. If the stake is found, remember the old overlay, and update the Ethereum address entry with this old overlay in the same index.
4. Remove the old entry in the other index (keyed by overlay), and insert the new overlay value updated with additional funds.


## Backward compatibility

Since we are changing how information is passed (both the overlay address and the Ethereum address), this change is not backwards-compatible.


## Test cases

Case study, with individual items needing to be tested:
1. Can one stake a node?
2. Is it then possible to change neighbourhoods?
3. If so, then did that happen with the stake transferred without a change?


## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
