---
SWIP: <to be assigned>
title: Swarm node implementer spec - 
author: Louis Holbrook @nolash <dev@holbrook.no>
status: Draft
type: Track Specs
created: 2019-08-23
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

### Capabilities

Swarm nodes rely on the underlying transport to negotiate which
protocols the node understands. If a protocol name and version pair
matches, the protocol execution loop must be started.

Additionally, the `Capabilities` mechanism enables peers to communicate
additional detail about what features within the modules the protocols
represent are enabled, and how they work. It is up to individual modules
running in the node to determine whether and how differences in
`Capabilities` cause incompatibilities.

`Capabilities` are transmitted as collections of key-value pairs of
numerical id and bitvectors. They are included in the bzz handshake
protocol. [\[sec:bzz-handshake\]](#sec:bzz-handshake)

    CAPABILITYID    = UINT64
    CAPABILITY  = LIST(LIST(CAPABILITYID *8BIT))
    CAPABILITIES    = LIST(LIST(*CAPABILITY))
