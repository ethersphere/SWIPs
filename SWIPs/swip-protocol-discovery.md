---
SWIP: <To be assigned>
title: Swarm node implementer spec - Discovery Protocol
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-09-14
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

### Discovery

Nodes get new peers relevant to them by advertising their `Saturation
Depth`.

A node informs its peers about its `Saturation Depth` upon initial
connection, aswell as every time the `Saturation Depth` changes.

This constitutes a *subscription*, in which the peer should always share
connection information for peers that are in the `Proximity Bin`
corresponding to the `Saturation Depth` of the node *or closer*.

The Subscription message has the following format:

    DEPTH = LIST(UINT8)

The message containing the connection information for peers has the
following format:

    PEERS = LIST(LIST(*BZZADDRESS))
