---
SWIP: <To be assigned>
title: Swarm node implementer spec - Hive
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

The connectivity driver of Swarm is named the `Hive`. The component
decides which peers to make connections to by consulting the `Kademlia`
for known but unconnected peers, and by invoking the `Discovery
Protocol` to alert peers about changes in its peer database.

### Saturation and Depth

In Swarm, a fully connected state is referred to as *Saturation*.

A *Proximity Bin* is saturated when it has at least \(2\) connected
peers.

A *node* is saturated if:

  - it is connected to all existing peers in its neighborhood

  - all Proximity Bins farther away than Depth are saturated

In the context of the Hive, the `Depth` at any moment before or during a
saturated condition is called `Saturation Depth`. This interpretation of
`Depth` differs slightly from the `Neighborhood Depth` used for routing
decisions. Specifically, it is the `Proximity Order` farthest from the
`Neighborhood Depth` that is *not* saturated. If no such bin exists,
`Saturation Depth` is effectively the same as the `Neighborhood Depth`.

### Prioritizing connections

A non-saturated node should seek connections with peers in the following
order of priority:

1.  the closest unconnected neighbors

2.  the farthest bin that has the least connected peers

### Retrying connections

If a peer connection fails or is disconnected, the node MUST reconnect.

If the initial reconnection attempt fails, the node SHOULD exponentially
increase the time it waits before retrying. The node’s reconnection
attempts SHOULD stay within the minimum bounds of the algorithm:

1.  If more than 42 retries have been attempted, discard the peer and do
    not continue

2.  Caluculate the time delta that since last retry

3.  Calculate the *number of warranted retries* by subtracting \(2\)
    from the \(log_2\) of the time delta

4.  Retry if the *number of warranted retries* is higher than the number
    of retries that has been made
