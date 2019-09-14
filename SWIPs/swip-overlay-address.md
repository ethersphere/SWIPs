---
SWIP: <to be assigned>
title: Swarm node implementer spec - 
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
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

### Base Hash

Swarm uses `KECCAK256` as its `Base Hash` algorithm. `KECCAK256` has a
digest size of 32 bytes.

### Swarm Overlay Address

Swarm addresses all content and all nodes using algorithms designed
around its `Base Hash`.

A node address is called its `Swarm Overlay Address`. It is derived from
the `ECDSA Public Key` of the Ethereum account used to operate the node.

To obtain the `Swarm Overlay Address`, calculate the `Base Hash` of the
*uncompressed* form of the `ECDSA Public Key`, *including* its \(04\)
(uncompressed) prefix. 

Formally we define the `Swarm Overlay Address` thus:

    OVERLAYADDRESS = 32*(%x00-ff)

#### Swarm Address Pair

To enable peers to locate the a node on the network, the aforementioned
`Swarm Overlay Address` is paired with an Underlay Address.

The Underlay Address is a string representation of the node’s network
location on the underlying transport layer, and *MUST* contain
sufficient data to enable peers to initiate new connections to the node.

    UNDERLAYADDRESS = VCHAR
    ADDRESSPAIR=2#2list(OVERLAYADDRESS UNDERLAYADDRESS)
