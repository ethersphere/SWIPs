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
- **Proximity Order (PO)**: How many starting bits are common between two addresses.
- **Bin X**: Bin X of a node M contains all the chunks in the network that has X as PO with M.
- **Storage Radius**: The minimum proximity order of chunk addresses matching with the pivot node address.
- **Storage Radius**: Smallest integer `D` such that all chunks in the network whose proximity order with the pivot node address is at least `D` fit into the storage space that node dedicates to its reserve.
- **Neighbourhood**  A set of peers in the network which proximity order with the pivot node address is at least `D`.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
If a node is connected to swarm as a full node, it fires up the pullsync protocol, which is responsible for syncing all the chunks that our node needs to store.Currently the algorithm we use makes sure that on each peer connection, both parties try synchronising their entire reserve. More precisely, each peer start streaming the chunk hashes in batches for each proximity order that is greater or equal to the pull-sync depth (usually the neighbourhood depth). In this proposal, we offer a much more efficient algorithm, still capable of replicating the reserve.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Imagine, that a naive peer joins a neighbourhood, then they will 'subscribe to' each 
depth of their peers within the neighbourhood. As they are receiving new chunks of course these are offering it too back to the peer they got it from. Plus they try to synchronise from each peer the entire reserve, not just part, which means a naive node's synchronisation involves exchange of `N*S` chunk hashrd where N is the neighbourhood size and S is the size of the reserve. This is hugely inefficient. 

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
Each peer `P` takes all their peers they are allowed to synchronise with: `p_0, p_1, ..., p_n`. 
All chunks need to be syncronized only once.
How about we syncronize each chunks from its closest peer among the neighborhood peers.

In order to find out what nodes share common chunk sets and what are unique ones, a leaf compacted binary tree of addresses from neighborhood peers can be made. The depth of any path extends only as far as is necessary to separate one group of addresses from another.
In this structure, every tree node represents a prefix and each step in the binary tree reflects a further position within the binary representation of the addresses and increments the `level` by 1.
Since the bins must be synchronised only above or equal to storage radius, the root node should represent the common prefix of the neighborhood and initialize the `level` with storage radius.

Each leaf holds a particular peer $p$ and its `level` is $p$'s uniqueness depth. Conseqently, each chunk sharing the prefix represented by the leaf is closest to $p$.
Each compactible node (i.e. that has one child) is the indication that all the chunks on the missing branch has no single closest peer and are equidistant from the two peers on the existing branch.

Ideally To sync all the chunks we need to cover all the branches of the trie:
- all chunks of leaf nodes must be syncronized from its stored peer.
- all chunks on the missing branch of a compactible node must be synced from a peer on the existing branch.

This is achieved if we traverse the trie in a depth-first manner and for each leaf node we subscribe to all bins greater or equal to its `level`. After then we accumulate peers at the intermediate nodes. While doing this, compatible nodes of level `X` we sync `bin X` from a peer from the accumulated set.

Note that those tree nodes that have two children of the trie represent prefixes that is fully covered by one of the peers below.

If all the peers we synced from are finished, the respective nodes reserve for any depth equal or higher to storage radius will be the same. 

Unlike the earlier algorithm, this one is extremely sensitive to the changing peerset, so every single time there is a change in the neighbours, pullsync stretegy needs to be reevaluated. 

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

One can see that each chunk is taken from its most immediate neighbourhood only. So depending on to what extent the peer addresses are balanced we save a lot on not taking anything more than once. Imagine a peer with neighbourhood depth `d`, and in the hood 2 neighbours each having a common 2 bit prefix. Their levels in the tree is `d+3` for each peer, and we synchronise chunks closest to them on their `Bin d+3`, `Bin d+4`, `Bin d+5`, etc. The peers share the same parent tree node on level `d+2` therefore their `Bin d+2` is not needed to be synchronised. `Bin d` and `Bin d+1` should contain the same chunks for both peers so each bin can be synchronised with one peer only. 
This means the synchronisation is halved for the first 2 levels and one bin is not synchronised at all for the peers that we need to synchronise with the current process in this setting.

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
