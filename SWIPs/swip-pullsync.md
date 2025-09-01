---
SWIP: 25
title: More efficient pull syncing within neighbourhood
author: Viktor Tron <@zelig>    
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
status: Draft
type: <Standards Track (Core)>
created: 2025-02-24
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
This SWIP describes a more efficient way to synchronise content between peers in the same neighbourhood.

### Glossary
_from the SWIP perspective_

- **Pullsync**: A protocol that is responsible for syncing all the chunks that our node needs to store.
- **Proximity Order**: How many starting bits are common between two addresses.
- **Bin X**: A set of chunks that has exactly X starting bits common with the address of the node holding it.
- **Storage Radius**: The minimum proximity order of chunk addresses matching with the pivot node address.
- **Neighbourhood**: A set of peers that are close to each other in the address space (their proximity order is at least the storage radius).

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
If a node is connected to swarm as a full node, it fires up the pullsync protocol, which is responsible for syncing all the chunks that our node needs to store.Currently the algorithm we use makes sure that on each peer connection, both parties try synchronising their entire reserve. More precisely, each peer start streaming the chunk hashes in batches for each proximity order that is greater or equal to the pull-sync depth (usually the neighbourhood depth). In this proposal, we offer a much more efficient algorithm, still capable of replicating the reserve.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Imagine, that a naive peer joins a neighbourhood, then they will 'subscribe to' each 
depth of their peers within the neighbourhood. As they are receiving new chunks of course these are offering it too back to the peer they got it from. Plus they try to synchronise from each peer the entire reserve, not just part, which means a naive node's synchronisation involves exchange of `N*S` chunk hashrd where N is the neighbourhood size and S is the size of the reserve. This is hugely inefficient. 

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
Each peer `P` takes all their peers they are allowed to synchronise with: `np = p_0, p_1, ..., p_n`. 
Two types of bins a peer can have:
- unique bins: its neighbors have different chunk set
- common bins: at least one peer shares the same chunk set
unique bins must be synchronised with all peers, but common bins can be synchronised with only one peer on that branch. In order to find out what nodes share common chunk sets and what are unique ones, a binary tree of addresses from `np` can be made. In this structure, every node holds a prefix and every edge corresponds to the continuation of that prefix by a single bit 0 or 1. Since the bins must be synchronised only above or equal to storage radius, the root node should represent the common prefix of all peers until the storage radius and initialize the `level` with storage radius. Each step in the binary tree reflects a further position within the binary representation of the addresses and increments the `level` by 1. The depth of any path extends only as far as is necessary to separate one group of addresses from another. By that, the `level` of a node is the number of the bin that is common to all addresses in the subtree rooted at that node.

Now for each peer `p_i` we start subscribing to all bins greater or equal to their level in the binary tree `level(p_i)`.
A folding algorithm can aggregate all subsumed addresses for intermediate nodes and decide on which peer should sync that corresponding bin. Therefore, in addition to `bin>=level(p_i)`, a peer may be chosen to synchronise some common bins below its level as well.

Note that unlike the earlier algorithm, this one is extremely sensitive to the changing peerset, so every single time there is a change in the neighbours, pullsync stretegy needs to be reevaluated. 

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

One can see that each chunk is taken from its most immediate neighbourhood only. So depending on to what extent the peer addresses are balanced we save a lot on not taking anything twice. Imagine a peer with neighbourhood depth `d`, and in the hood 2 neighbours each having a common 2 bit prefix. Their levels in the tree is `d+3` for each peer, and we synchronise `Bin d+3`, `Bin d+4`, `Bin d+5`, etc. from each peer. `Bin d`, `Bin d+1` and `Bin d+2` are common for both peers and these can be synchronised with one peer only. 
This means the synchronisation is halved for the first 3 bins (most probably broader sets than higher numbered bins) than what we need to synchronise with the current process.

One potential caveat is that if a peer quits or is no longer contactable before the pivot finished syncing with them, then another peer needs to start the process.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
Although it is a major strategic change, the subscription request wire protocol does not change and therefore, the SWIP is backward compatible.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
Thorough testing is neeeded, cos this can produce inconsistencies in the localstore and has major impact for retrievebility.

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
The assumption behind the loose specification is that we do not need to support for any kind of pull-sync change and existing data flow will be sufficient. In particular, the following assumptions are made:
- pullsync primary indexes the chunks by PO (relative to the node address)
- as secondary ordering within a bin is based on first time of storage.
- the chronology makes it possible to have live (during session) and historical syncing.

## Copyright/
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
