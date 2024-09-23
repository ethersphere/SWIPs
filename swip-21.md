---
title: Reserve doubling
SWIP: 21
author: Viktor Tron (@zelig), Callum Toner (@callum)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord)
status: Draft
type: Standards Track
category: Core
created: 2024-05-04
---

# Reserve doubling 

How to extend node storage capacity dedicated to the reserve to be able to calibrate operators' profitability.

## Abstract 

No matter how large the storage space a node could dedicate to their reserve, in the current setup of the redistribution game, it only gets rewarded for a prescribed amount of chunks called the reserve size. The current reserve size of cca. 4 million chunks (around 16 GB, or more precisely 2^22, which effectively requires  25Gb with indexes) is proving to be too small for the profitable operation of nodes. The purpose of this SWIP is to change this and allow nodes to double their reserve size (potentially multiple times) and get rewarded accordingly.

## Background and objectives

The reserve size was deliberately chosen relatively small, so that Swarm can experience scaling in the number of nodes relatively quickly. After a successful period of multiple instances of storage radius increases, we now consider Swarm’s storage capacity scaling safe and tested. Operating a node requires other resources like CPU, memory, and bandwidth. In order to help calibrate a profitable setup, it is desirable that storage capacity can be dynamically set.

Increasing the node reserve capacity (and getting incentivized and paid accordingly for it) vastly decreases how many peer connections are needed to be maintained per unit of storage. This makes operating a node far more economical as they will earn more revenue for storing more data, at virtually the same operating costs. On the other hand, this allows the network to operate with the same capacity and security of storage with less nodes. If all storer nodes double their reserve, only  half as many nodes will be required to maintain the same quality of service. 

## Context 

The redistribution game requires nodes to sample the chunks closest to the current round anchor, called the *playing reserve* (This is validated by the *retrievability* check), and mandates  that each participating node’s overlay address be close to this same round anchor (*responsibility* check). Close here means the address must match the anchor up to at least *d* bits, where *d* is the committed depth of storage. Nodes are encouraged to report the largest depth *d* they can, since both the selection of truth and the winner are determined by the node’s stake density,  which is the effective stake per volume of responsibility (i.e., stake \* 2^d). Overreporting depth is prevented by checking that the sample comes from a large enough chunk pool, corresponding to the prescribed minimum playing reserve size (*resources* check). Therefore we can rephrase the participation as follows: a node is selected if the anchor falls within its neighbourhood that can hold all the chunks in that neighbourhood given the prescribed reserve capacity, and the node must sample its reserve (filtering chunks matching the anchor at least up to the storage depth).

## Solution

Now the solution to increased reserve size will be indirect. The game will stay almost the same as currently, i.e., nodes sampling the part of their storage designated by the anchor, with a  depth corresponding to storage depth *d*. However, the constraint on the node overlay proximity to the anchor can be weakened: the node’s overlay will no longer need to match the anchor up to *d* bits. This effectively means that a node is allowed to play in a round where its *sister neighbourhood* is selected, i.e, when the responsibility criteria is modified to allow the node overlay to match the anchor with *d’\<d* bits. Let us call *d’* the *depth of responsibility*. Now we can see that by doubling the storage capacity and decreasing the pull-sync depth by one, a node will be able to synchronise the sister neighbourhood’s playing reserve and get rewards twice as often as with the original storage capacity.  
Analogously, if the responsibility criteria are modified and allow the node overlay to match the anchor with *d’\<d-1* bits, then by quadrupling its capacity and synchronising at PO  *d-2,* nodes will be able to play in rounds where their sister and cousin neighbourhoods are selected, thereby also quadrupling their income.  
![][image1]  
With the calibration of the reserve becoming optional through these changes, this solution allows node operators to find their optimal setup. It empowers two distinct user roles based on storage capacities and chunk traffic (their activities regarding storage incentives and/or bandwidth incentives). 

## 

## Specifications 

### Increasing the reserve capacity

The reserve should now be optionally configurable to the playing reserve size (of 16Gb) as the lowest, or that multiplied by a power of 2\. Practically in the relevant powers of 2 the exponent is in the small integer range. Initially, we will focus on doubling. 

When a node doubles its reserve, it essentially extends its storage capacity and takes on the task of storing the content of the entire *parent neighbourhood,* i.e., the node’s neighbourhood of depth *d-1* where *d* is its original depth of storage.

Assuming a playing storage depth of 11 in the network, if you want to double your reserve, you must connect to all nodes whose overlay address matches your own 10 bits or more as well as you must sync from them their playing reserve (i.e., chunks in the peer’s neighbourhood of depth 11). As a result, you end up storing all chunks whose  addresses match your overlay in the first 10 bits: composed of the chunks in your own depth-11 neighbourhood as well as its *sister*. 

### Participation in the Redistribution game

To assess their ability to play, nodes now compare their overlay address to the current round anchor and determine participation based on whether they match up to their playing storage depth. When reserve doubling is effective, this condition is modified: the number of matching bits plus the number of doublings the node chose to apply must equal or exceed the committed depth. This weaker condition will be triggered every time a sibling neighbourhood of degree *m* is selected. Each time the reserve is doubled, the node will play twice as many games (and earns twice as much in revenue) as without doubling. If the doubling happens as the storage depth increases (or overall storage capacity and revenue doubles), the node gets wins with the same frequency while the revenue doubles. This means that variance does not increase with greater storage depth.

### Proof of reserve validation changes

Now with the increased node reserve size, the responsibility check needs to be modified to allow remote node participation. I.e. nodes that match  the current round anchor less than *d* bits, where *d* is the node’s playing storage depth declared as part of their commit. Matching the anchor on *d-1* bits allows playing in the sister neighbourhood, and matching the anchor on *d-2* bits allows playing in a cousin neighbourhood, In general, the depth of responsibility, or node storage depth, is *d-m,* where *m* is the *height* of the nodes' reserve, i.e., number of times the node doubles their reserve, i.e., their reserve size is 2^(22+m). 

In order to be able to apply the right depth for the responsibility check, the contract needs to access *m* when the node reveals their commit. Therefore, *m* must now be recorded for each node. 

When calculating the stake density for the redundancy/stake check, the contract must now use the depth of responsibility rather than the committed depth (of storage). As a consequence, for every doubling of reserve, a node needs to also double its effective stake in order to maintain its likelihood of winning. This increased stake accurately reflects the increased responsibility obtained through the increased reserve. 

### Network dynamics and process of storage size calibration.

If nodes in the network have a particular reserve size, then for the odd node to increase their height may be risky. Since with each doubling, they need to connect to virtually double the number of peers and continuously pull sync with them, their resource requirements are soon  gonna be prohibitively large. In order to allow a healthy dynamics, simply doubling should always be an option at least in not too overpopulated neighbourhoods. However, further doublings are unlikely if resource utilisation was close to maximum. This implies that a node  
is unlikely to go much farther ahead and increase their reserve to a height greater than what is dominant in the relevant neighbourhoods.

Let's see now how node profitability changes. Assuming the network is at equilibrium with 4 nodes in each neighbourhood and a uniform height of reserve, now imagine one of the nodes increases its height by 1\. The per-neighbourhood earnings go down 2.5%, but let us suppose that due to better utilisation of I/O and bandwidth there is cost savings amounting to more than *2.5%* and therefore more profit*.* The price oracle stays so those that do not increase their height will be priced out of the competition earlier all else being equal. For the second node to increase their height the processing burden is less and so on until there is only 4 nodes with height 1 cover the parent neighbourhood. All in all, assuming there is ever a motivation to increase the reserve to height *m* for a type of node, peers will be able to follow. Once the entire parent neighbourhood has the increased height and reaches equilibrium with 4 nodes, further doublings are possible again.

## Implementation

Implementing reserve doubling requires changes both in the incentivisation smart contract suite and the bee client code as well as tools such as Swarm CLI and Swarmscan.

### Changes in the smart contracts

#### Staking contract

For the responsibility check and stake calculation, a node needs to indicate its increased reserve by registering *m,* the number of doublings. The best place to do this is the staking contract. We essentially need to introduce an additional field in the stake struct called ‘height’.  
Without further action, this will give *m* the correct default value of 0\. In order to be able to change this, an extra parameter needs to be added to all the staking and stake-modifying endpoints. These API changes must be reflected in the corresponding Bee code.

#### Redistribution contract

The responsibility check in the reveal transaction (part of the reveal function execution) needs to know the depth of responsibility *d-m*. This requires not only the committed depth just revealed (*d),* but also the knowledge of the number of doublings. This is best achieved  by including an additional height field in the commit struct, copied from the stake struct, analogous to the overlay when the node commits.

This change has no impact on the Bee code.

To query a node’s eligibility to participate in the next round, the function \`isParticipatingInUpcomingRound\` is utilised. In order to correctly trigger participation in sister or cousin neighbourhoods, the height parameter must be added and used when matching the anchor with the node overlay address.

This change needs to be reflected in the Bee code, and also requires that the Bee node has access to the height increase (the number of doublings) from the redistribution game agent code.

### Changes in the client code

#### Reserve sampling 

No matter how a node gets selected to play, it needs to sample only the part of the reserve that falls within the playing storage depth of the current anchor.  
If this is the native local neighbourhood of the node, then the sampling need not change. However, for sister and cousin neighbourhoods, only the chunks matching the anchor up till the playing storage depth need to be considered. 

Given the current implementation, the sampling uses the pull-sync index. For native neighbourhood sampling, this means iterating over all PO bins equal to or greater than the (playing) storage depth *d*. Now for sister neighbourhoods, one should just consider the contents of bin *d-1.* However, for cousin neighbourhoods, using the same indexing scheme may be suboptimal, because when iterating over bin *d-2* we will end up iterating over the playing reserve of both cousins at once. Although we can easily filter out those chunks that belong to the wrong cousin, effectively we iterate over twice as many chunks as needed. This extra iteration may have prohibitive I/O requirements in the sense that the increased time spent on iteration may cause the sample to not be completed by the end of the commit phase, thereby preventing the node from participating in the game.   
Practically, this means that until a different improved indexing is introduced (probably as part of pullsync improvement SWIP), potentially only doubling (and not quadrupling) the reserve will be feasible.

#### Syncing and storing

When increasing the reserve size, the localstore must use *2^(22+m)* as its capacity.  
When the node extends its reserve capacity through doubling, it must fill its reserve and synchronise with nodes and apply this increased localstore size as the eviction cut off point to arrive at the depth of responsibility. The node derives the depth of storage from its depth of responsibility *d* by adding to it its height *m*, i.e., *d+m,* which then must be used in the reserve sampling. In order to guarantee synchronization, the node must also seek to establish peer connection to all nodes within *d*.

[!IMPORTANT] 

This is an acknowledgement of concerns regarding the syncing and peer connections - which have been taken into consideration and accounted for below. 
Key feedback and thanks goes to ldeffenb for raising these concerns. 

"I see multiple (and necessary) mentions about "connecting to all peers in the sister neighborhood", but I suspect this will be problematic. The current kademlia attempts to connect to all nodes in the current neighborhood. This is good because the other nodes in the neighborhood are also trying to connect to us, and it "just works".

But consider a node that has doubled its reserve, it is now trying to connect to all immediate neighbors (as before), but now is also trying to connect to the nodes in the sister neighborhood as well. But the gotcha is that those nodes (at least, any that have not doubled) are NOT trying to connect to this node. So, all connections to the sister neighborhood nodes will be incoming connections to those peers which are purposely restricted so as not to overSaturate a node's connections. Without some kademlia changes, it may not be possible to achieve connections to "all" sister neighborhood nodes, and even less likely to be able to achieve (and maintain across peer connection periodic purges) this level of connections to cousin neighborhood nodes in a quadrupled (or more) configuration."

1. this is not much more of a problem than in a nondoubled neighbourhoods, if 2 nodes are oversaturated then no connection is possible
2. neighbours can be checked for their height on the blockchain and can be made exempt
3. its only meant to be a few doubled nodes for each non-doubled one
4. there is no big harm in not being connected to all sister peers

### Changes in tooling

#### CLI

We will need commands & CLI changes to support easy doubling of reserves on spin-up at any time, as well as manage associated stake requirements with the increased reserve. 

#### Swarmscan

In one of its functionalities, swarmscan enlists neighbourhoods with their population in order to inform operators (who want to start a new Bee node or just hop to a new neighbourhood) about the most profitable neighbourhoods, i.e the ones with the least amount of redundancy (least nodes).  Currently swarmscan just uses reachability to qualify nodes as full and uses the overlay to match. With possibly increased reserve, swarmscan will need to lookup the nodes height *m* first and indicate that the node contributes to the redundancy of all *2^m* playing neighbourhoods, i.e., count and list them under these neighbourhoods as if they belonged to their respective local population. Since this requires swarmscan to query the staking contract, as a bonus we get more accurate information about profitability since non-staked nodes will be filtered out.

## Glossary

###### *Neighbourhood*

a contiguous area of the address space characterised by a shared prefix in the node’s big-endian binary representation

###### *Neighbourhood of depth d*

a contiguous area of the address space characterised by a shared prefix of length *d* in the node’s big-endian binary representation

###### *A’s Neighbourhood of depth d*

the contiguous area of the address space characterised by A’s prefix of length *d* in the node’s big-endian binary representation

###### *Reserve* 

 the portion of a node’s storage dedicated to chunks with valid postage stamps

###### *Playing reserve size*

 2^22 chunks

###### *Height* 

Number of doublings of the playing reserve size the node dedicates to their reserve, i.e., the base 2 log of the number of playing neighbourhoods that the node is responsible for storing.

###### *Node reserve size*

 the total capacity a node dedicates to its reserve, i.e., *2^(22+m)*

###### *Depth of storage*

the playing depth of storage which is the same as the node’s depth of responsibility if the is no doubling of reserve

###### *Playing depth of storage*

the depth of a node’s (largest) neighbourhood that holds no more chunks than the playing reserve size (2^22 chunks) 

###### *Committed depth (of storage)*

 the playing depth of storage that the node committed as part of their reserve commitment

###### *reserve commitment* 

data related to the reserve sample that nodes in the selected neighbourhood need to submit to the redistribution contract; the target of the Schelling game the nodes need to agree on 

###### *Depth of responsibility* 

the depth of a node’s (largest) neighbourhood that holds the node’s reserve (the total of all its playing reserves), i.e. *d+m,* where *d* is the depth of storage and *m* is the height

## 
