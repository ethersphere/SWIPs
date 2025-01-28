---
SWIP: <to be assigned, preferably 13>
title: Websocket addresses communicated in handshakes and gossiped onward
author: Abel A Bodo (lat-murmeldjur)
discussions-to: N/A
status: Draft
type: Standards Track
category: Protocol update
created: 2025-01-28
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary

To enable instantaneous access to the swarm an in-browser rust-webassembly based libp2p client (light node) is under development (https://github.com/lat-murmeldjur/weeb-3).

At the current stage the client is able to connect to nodes that have a websocket underlay enabled (as well as engage in the basic set of necessary protocols, including gossip, retrieval, pseudosettle and has basic capability to display resources, websites hosted on swarm etc).

To make the next step of enabling these in-browser light nodes to connect to the swarm network, the missing feature from the bee client can be described as the following:

When gossiping peers in the hive protocol, currently there is no capability for gossiping multiple underlays for a single peer. Furthermore, when a bee node connects to another node through a tcp based underlay, it will only gossip its tcp based underlay.

For the specific case of in-browser nodes only websocket based underlays are connectable, therefore the gossiped tcp addresses are not useful. To enable browser based nodes to connect to the swarm the gossip protocol would need to be extended with an extra websocket-underlay field for each peer. This websocket-underlay would need to be added to the handshake protocol as well, so that bee nodes learn each other's websocket underlay even when they connect to each other through tcp underlays, for the purpose of being able to gossip websocket addresses. 

To further enable browser-based nodes to be able to find sufficient amount of connectable nodes exposing websocket underlays, it's important to have the websocket underlays enabled by default for full bee nodes.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->


## Motivation
Currently, websocket addresses (even if the feature would be working and enabled on most bee nodes) are not gossiped, therefore most of the swarm network is not connectable from a browser-based node.

To address this issue the gossip and handshake protocol would be need to be extended to enable better access to swarm.

## Specification
As protobuf 3.0 is even backward compatibly extendable with new fields (as long as existing field numbers don't change), the suggested change is to add the following new fields:

in handshake.proto

message BzzAddress {
    bytes Underlay = 1;
    bytes Signature = 2;
    bytes Overlay = 3;
+   bytes WSUnderlay = 4;
}

in hive.proto

message BzzAddress {
    bytes Underlay = 1;
    bytes Signature = 2;
    bytes Overlay = 3;
    bytes Nonce = 4;
+   bytes WSUnderlay = 5;
}

Also wsenable configuration option should be set by default to true for full nodes, adding a new ws-port configuration option with default set to e.g. 4336 (previously unused)

## Rationale
A limiting factor of access to the swarm can be characterized as the difficulty of accessing the network, having to install software, browser extensions, etc. This can currently only be circumvented by using public gateways, that are privacy jeopardizing as well as costly to run, as their operators need to provide bandwidth and server infrastructure to the consumers. A browser based node can be hosted much more efficiently (e.g. as a static github page), while the bandwidth usage is solely weighing on the content consumer / frontend, while the privacy remains intact as the "server" that serves the browser-based client is not involved in any further communication between the browser-based client and the swarm network.

## Backwards Compatibility
In theory, protobuf 3 enables backward compatible updates to protocols as all fields are optional and higher numbered fields can always be added on top of the existing ones.
However it seems more clean to test and introduce such a level of change involving multiple protocols as a breaking change.

## Test Cases
Testing this change would involve checking that nodes joining the network with custom websocket ports are gossiped accordingly.

## Implementation
--

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).