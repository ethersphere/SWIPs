---
SWIP: <to be assigned>
title: Swarm Addressing
author: nolash (@nolash) 
discussions-to: 
status: Draft
type: Standards Track
category: Core
created: 2019-08-12
---


## Abstract

This document documents the current implementation of the Swarm Addressing constructs outlined in the architecture section of the [Swarm Guide](https://swarm-guide.readthedocs.io).

## Motivation

The current implementation of the Swarm Address implies a specific encoding and serialization. This needs to be documented.

## Specification

### Swarm Overlay Address

Swarm addresses all content and all nodes with 32-byte hashes. A node
address is called its Swarm Overlay Address. It is derived from the
public key of the Ethereum account used to operate the node.

To obtain the Swarm Overlay Address, hash the *uncompressed* form of the
public key, *including* its `04` (uncompressed) prefix, using the KECCAK256 hashing
algorithm.

Formally we define the Swarm Overlay Address thus:

``` {numbers="none"}
OVERLAYADDRESS = 32*(%x00-ff)
```

### Swarm Address Pair

To enable peers to locate the a node on the network, the aforementioned
Swarm Overlay Address is paired with an Underlay Address. The Underlay
Address is a string representation of the node's network location on the
underlying transport layer.

Currently the url string representation of the devp2p V4 Enode ID is
used for this value. Although this value currently serves no practical
purpose within the operations of the Swarm node, the handshake *MUST*
fail if the string cannot be parsed as a valid Enode ID.

We here add the following definitions:

``` {numbers="none"}
ENODEPREFIX = "enode://"
PUBLICKEYHEX = "04" 64HEXDIG
HOST = IP / FQDN
UNDERLAYADDRESS = ENODEPREFIX PUBLICKEYHEX "@" HOST ":" PORT
ADDRESSPAIR=2#2list(OVERLAYADDRESS UNDERLAYADDRESS)
```

## Backwards Compatiblity

This document does not introduce any new concepts

## Test Cases

This document does not introduce any new concepts

## Implementation

This document only refers to existing implementations

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
