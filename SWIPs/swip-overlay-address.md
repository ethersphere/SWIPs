---
SWIP: <to be assigned>
title: Swarm node implementer spec - 
author: Louis Holbrook @nolash <dev@holbrook.no>
status: Draft
type: Track Specs
created: 2019-08-12
---

## Abstract

This SWIP is a part of a general specification of a Swarm node. The SWIP system is used for convenience only.

## Motivation

Enable other implementations of the swarm node.

## Backwards Compatibility

N/A

## Test Cases

N/A

## Implementation

N/A

## Copyright

Copyright and related rights waived via CC0

## Specification

### Swarm Overlay Address

Swarm addresses all content and all nodes with 32-byte hashes. A node
address is called its Swarm Overlay Address. It is derived from the
public key of the Ethereum account used to operate the node.

To obtain the Swarm Overlay Address, hash the *uncompressed* form of the
public key, *including* its \(04\) (uncompressed) prefix, using the
KECCAK256 hashing algorithm.   

Formally we define the Swarm Overlay Address thus:

    OVERLAYADDRESS = 32*(%x00-ff)

### Swarm Address Pair

To enable peers to locate the a node on the network, the aforementioned
Swarm Overlay Address is paired with an Underlay Address.

The Underlay Address is a string representation of the node’s network
location on the underlying transport layer, and *MUST* contain
sufficient data to enable peers to initiate new connections to the node.

    UNDERLAYADDRESS = VCHAR
    ADDRESSPAIR=2#2list(OVERLAYADDRESS UNDERLAYADDRESS)
