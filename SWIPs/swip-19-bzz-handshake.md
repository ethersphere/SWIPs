---
SWIP: 19
title: Swarm node implementer spec - BZZ handshake
author: Louis Holbrook @nolash <dev@holbrook.no>
status: Draft
type: Track Specs
created: 2019-08-08
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

### bzz protocol

#### handshake

The bzz handshake is the first message to be exchanged between peers
after the p2p transport protocol has been successfully negotiated. After
the handshake each peer should remember the following data about the
other:

  - `Swarm Overlay Address` of the peer [\[address\]](#address)

  - What `Capabilities` the peer has advertised
    [\[capabilities\]](#capabilities)

##### message

The handshake message consists of four data fields:

``` 

Version     = UINT64
Network ID  = UINT64
Address data    = ADDRESSPAIR
Capabilities    = CAPABILITIES
```

##### procedure

Upon connection, the *peer who initiated the connection* sends a
handshake message to the other. If a more than one handshake is received
from the same peer, the connection *MUST* be dropped.

The peers *MUST* have the same `Version` and `Network ID`. If one or
both of the fields don’t match, the connection *MUST* be dropped.
