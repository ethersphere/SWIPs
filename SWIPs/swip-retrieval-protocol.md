---
SWIP: <to be assigned>
title: the bzz-retrieve protocol
author: @acud
discussions-to: <URL>
status: Draft
type: Standards Track
category Core
created: 2019-10-24
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->
## Simple Summary
Standardisation of the bzz-retrieve protocol which allows for nodes to issue requests for content addressed data and for their counterparts to deliver that content

## Abstract
Every node that fully participates in the Swarm is expected to request, deliver or forward requests for chunk retrievals. This is to be done using a simple p2p protocol that negotiates the delivery of those data chunks.

## Motivation
Different Swarm implementations must standardise the way chunk delivery is made. In order for the devp2p protocols on these nodes to correctly negotiate and establish normal operations, the underlying protocol messages and exchange rules must be thoroughly defined. Doing so should pave the way for a simplified reimplementation of Swarm in other clients and languages.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
The Swarm retrieval protocol is defined as a `devp2p` protocol with the following parameters:
Protocol name:    bzz-retrieve
Current version:  2
Max Msg Size:     10 * 1024 * 1024

Types of nodes and their participation in the retrieval protocol:
1. Bootnode - does not participate in the `bzz-retrieve` protocol
2. Light node - participates but does not handle retrieve requests (handles ChunkDelivery message and issues RetrieveRequest messages)
3. Full node - participates fully (issues and handles both RetrieveRequest and ChunkDelivery messages)

Protocol Messages:
1. ChunkDelivery
2. RetrieveRequest

The protocol messages are defined in the following manner:

1. RetrieveRequest is the message used to issue a request for a single chunk over the Swarm. When a chunk is not found locally on the node handling the message from the requester, that node is expected to send another
RetrieveRequest to the node it sees fit in order to get the chunk. In turn, if that node does not find the chunk, another RetrieveRequest is expected to happen and so forth until the chunk is found.
Once a chunk is found, it is sent back to the requesting node which in turn forwards the chunk back to the node which requested it etc, until the whole cascade of requests is resolved with the delivery of the
wanted chunk to the original requester of the chunk.

The definition of the RetrieveRequest message:
```go
type RetrieveRequest struct {
	Ruid uint
	Addr storage.Address
}
```

The RetrieveRequest defines two fields:
a. Ruid - a unique, random `uint32` generated on the requesting node to associate a certain requested chunk with a node
b. Addr - a 32-byte chunk hash to retrieve

2. ChunkDelivery is used in order to deliver chunks over the Swarm. It is the cornerstone of every bit that should be delivered over Swarm. Each ChunkDelivery message represents a delivery of one discrete chunk.
A ChunkDelivery must always be preceded by a RetrieveRequest message. This mitigates the risk of misbehaving nodes spamming other nodes with unwanted content, causing their local storage to be
filled with unsolicited content.

The definition of the ChunkDelivery message:
```go
type ChunkDelivery struct {
	Ruid  uint
	Addr  storage.Address
	SData []byte
}
```

The ChunkDelivery message defines 3 fields:
a. Ruid - a unique, random `uint32` that corresponds to the Ruid of the incoming RetrieveRequest message for which the ChunkDelivery was sent.
b. Addr - the 32-byte chunk address of the delivered chunk
c. SData - an arbitrary byte array containing the chunk data


Notes:
1. The requester node _MUST_ check that a Ruid on an incoming ChunkDelivery message exists for the specific peer from which the chunk was delivered. If the given Ruid cannot be found - that peer should be treated as a misbehaving node and should be dropped
2. The requester node _MUST_ check that the address on an incoming ChunkDelivery is identical to the requested chunk address that is associated with the request's unique idenfitier (Ruid). If the chunk addresses do not match - that node should be treated as a misbehaving node and should be dropped
3. The requester node _MUST_ verify that the content of the delivered chunk, after hashing, corresponds to the requested chunk address. If the hashes do not match - the node from which the chunk delivery was recieved should be treated as a misbehaving node and should be dropped.


## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->


## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
This serves as the first bzz-retrieve protocol standardisation. No backward compatibility needs to be maintained at this stage.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
given two nodes `a` and `b` which are connected, node `a` should drop node `b` when an unsolicited chunk was delivered from `b` to `a` (ruid not found error)
given two nodes `a` and `b` which are connected, node `a` should drop node `b` when an unsolicited chunk was delivered from `b` to `a` (ruid found but chunk address mismatch)
given two nodes `a` and `b` which are connected, node `a` should drop node `b` when an unsolicited chunk was delivered from `b` to `a` (ruid & chunk address found but chunk data does not validate against requested hash)

given three nodes `a`,`b`,`c` which are connected in the following manner a --> b --> c (`c` is not directly connected to `a`) and a random chunk `r` for which `po(r,c) > po(r,b) > po(c,a)` (`r` is closest to `c`) and given that `r` is stored on node `c`, we expect that node `a`'s request for chunk `r` which is issued to node `b` will be forwarded to node `c`.


## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
