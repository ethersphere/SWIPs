---
SWIP: 19
title: Swarm node implementer spec - BZZ handshake
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-08-08
---

## Abstract

This SWIP is a part of a general specification of a Swarm node. The SWIP system is used for convenience only.

## Motivation

Enable other implementations of the swarm node.

## Specification

### BZZ protocol

#### Handshake

The bzz handshake is the first message to be exchanged between peers
after the p2p transport protocol has been successfully negotiated. After
the handshake a node should remember the following data about its peer:

  - `Swarm Overlay Address` of the peer
    [overlay-address](https://github.com/nolash/SWIPs/blob/swarm-overlay-address/SWIPs/swip-overlay-address.md)

  - What `Capabilities` the peer has advertised
    [capabilities](https://github.com/nolash/SWIPs/blob/spec-capabilities/SWIPs/swip-18-capabilities.md)

##### Message

The handshake message consists of four data fields:

| id | def |
| :--- | :---- |
| Version | UINT64 |
| Network | UINT64 |
| Address | ADDRESSPAIR |
| Capabilities | CAPABILITIES |

##### Procedure

Upon connection, the *peer who initiated the connection* sends a
handshake message to the other. If more than one handshake is received
from the same peer, the connection *MUST* be dropped.

The peers *MUST* have the same `Version` and `Network ID`. If one or
both of the fields don’t match, the connection *MUST* be dropped.

## Backwards Compatibility

N/A

## Test Cases

N/A

## Implementation

N/A

## Copyright

Copyright and related rights waived via CC0

## Specification

