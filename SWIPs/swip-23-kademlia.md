---
SWIP: 23
title: Swarm node implementer spec - 
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-09-05
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

The Kademlia is both a database (DHT) of known and connected peers on
the network, as well as a component for routing and forwarding content
on the network.

### Records

A peer record *ALWAYS* contains the `Address Pair` and the
`Capabilities` of the peer. This data structure is known as the
`BzzAddress`. It serializes as follows:

    BZZADDRESS = LIST(OVERLAYADDRESS UNDERLAYADDRESS CAPABILITIES)

### Connectivity

#### Address matching

For two addresses to match each other, their byte values must be
identical.

For certain purposes in Swarm *partial addresses* are used. A partial
address is an address of less than 32 bytes. The bytes of a partial
address always represent the most significant bytes of the full address
that the partial address represents. A partial address matches a full
address if all the bytes in the partial address are identical to the
corresponding bytes in the full address.

#### Distance and proximity

In Swarm, differences between addresses are described in terms of
*Distance* and *Proximity*.

The *Distance* between two addresses is the value of the big-endian
binary integer cast of the XOR of the two addresses.

For example, the distance between the addresses 1010 and 1101 will be
\(1011 ^ 0111 = 1100\), where the big-endian binary integer cast of
\(1100\) is \(12\).

Another measure of difference *Proximity*, which is the logarithmic
distance between the addresses. Specifically we define the Proximity
Order, which is index value of the most significant bit that differs
between the two addresses.

For example, an address \(0101\) will have a Proximity Order of \(0\)
compared to \(1101\), a proximity Order of \(1\) compared to \(0011\),
and a Proximity Order of \(3\) compared to \(0110\). 

#### Proximity Bin

A Proximity Bin is the table row in the kademlia that contains all peers
that have the corresponding proximity to the node.
[0.2.2](#sec:distance-and-proximity)

As with the Proximity Order, a *closer* Proximity Bin has a higher
numeric value, and a *farther* Proximity Bin has a lower numeric value.

#### Neighborhood

The Neighborhood of a node are the peers in the two closest Proximity
Bins in which peers are known to the node.

#### Depth

The Depth of a node’s kademlia is found by the following method:

1.  Find the two closest Proximity Bins that have at least one
    *connected* peer.

2.  Find the next farther Proximity Bin that has at least one
    *connected* peer.

3.  If found, the Depth is the numeric value of that bin plus one.

4.  If not found, the depth is \(0\).

#### Health

A kademlia is healthy when:\[1\]

  - All peers in the Neighborhood are connected

  - At least one peer in every Proximity Bin *farther* than the Depth is
    connected.

### Content forwarding

The rules for content forwarding apply to *all* nodes on the content
route. In this document we refer to these nodes *relaying nodes*. This
includes the *sender* and any *receiver* nodes.

A node *MUST* always forward content\[2\], *unless* one of these
criteria are fulfilled:

1.  the recipient address of the content is a full 32-byte address,
    *and* matches fully with the node’s Swarm Overlay Address\[3\].

2.  the message has been seen already, before a certain period of time
    has elapsed, currently defined as \(10\) seconds. (see
    [\[sec:message-digest\]](#sec:message-digest))

3.  the kademlia of the node is not *healthy*

Which peer or peers the node should forward to depends on the proximity
of the node to the recipient address, aswell as the address type. See
[\[sec:address-matching\]](#sec:address-matching) for details on address
types.

#### Routing with full address

By full address we mean that the recipient address contains the full 32
bytes of the intended recipient node.

1.  If the recipient address falls within the *most proximate bin* of
    the node, the content should be forwarded to *all* the node’s
    *nearest neighbors*.

2.  Otherwise the node *MUST* attempt to send to exactly *one* peer in
    the bin that is the closest match to the recipient.

3.  If this is not successful, the node *MUST* try to forward to each
    remaining peer in that bin in order from closest to farthest to the
    recipient, until one is successful.

4.  If this is not successful, the node should retain the content and
    retry later.

#### Routing with partial address

1.  Identify the *farthest* peer that matches the partial address.

2.  If that peer is in the *most proximate bin*, the content should be
    forwarded to *all* the node’s *nearest neighbors*.

3.  Otherwise, if the bitlength of the recipient address equals the
    proximity order of its matching bin, the content should be forwarded
    to *all* peers that are in the matching bin or closer to the
    recipient\[4\].

4.  Otherwise the bitlength of the recipient address is *longer* than
    the promixity order of its matching bin. In this case the node
    *MUST* attempt to send to exactly *one* peer in the bin that is the
    closest match to the recipient address.

5.  If this is not successful, the node *MUST* try to forward to each
    remaining peer in that bin in order from closest to farthest to the
    recipient address, until one is successful.

6.  If this is not successful, the node should retain the content and
    retry later.

#### Routing with empty address

1.  Content should be forwarded to *all* peers.

2.  If *none* of the peers can successfully be forwarded to, the node
    should retain the content and retry later.

### Evaluating recipients

Any node receiving content has to evaluate whether it can be the
intended recipient, or one of the indended recipients, of the content.

The first condition that must be fulfilled is a matching recipient
address on the content. Matching may happen in one of two forms:

##### Literal matching

As described in [0.3.1](#sec:routing-with-full-address), if the full
32-byte recipient address matches the node address, the node is the only
intended recipient and *MUST* process the content.

If the recipient address is a partial address, and it matches the node
address, the node *may* be one of the intended recipients and *MUST*
process the content.

##### Proximity matching

This method provides a way to send content with a full 32 byte recipient
address to more than one recipient.\[5\] The procedure is as follows.

1.  The proximity order of the recipient address with respect to the
    node is calculated

2.  If the proximity order is within the node’s depth, the node *may* be
    one of the intended recipient and *MUST* process the content.

<!-- end list -->

1.  Note that it is technically possible for a kademlia to be healthy
    even though the Depth is \(0\).

2.  This is done to make it more difficult to determine the true
    recipient of a message by traffic analysis

3.  In this case the recipient is already fully revealed to anyone
    observing the traffic

4.  Notice that in this context, the matching bin becomes the *most
    proximate bin*

5.  This is the matching method used for the *Push Sync* feature, where
    content addressed chunks are routed to their neighborhood in the
    network.
