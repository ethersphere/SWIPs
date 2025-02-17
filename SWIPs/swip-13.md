---
SWIP: 13
title: Websocket addresses to be communicated in handshakes and gossiped onward
author: Ábel A. Bodó (lat-murmeldjur)
discussions-to: N/A
status: Draft
type: Standards Track
category: Protocol update
created: 2025-01-28
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Abstract

Currently, websocket addresses are not gossiped rendering the swarm network not connectable from a browser-based node.
To solve this issue, the relevant message communicating the adddress in both the gossip and the handshake protocols must be extended with a field for the websocket underlay.

## Context

To enable instantaneous access to the swarm without installing anything, an in-browser libp2p-based client (light node, written in rust-webassembly) is under development (https://github.com/lat-murmeldjur/weeb-3).

At the current stage the client is able to connect to nodes that have a websocket underlay enabled (as well as engage in the basic set of necessary protocols, including gossip, retrieval, pseudosettle and has basic capability to display resources, websites hosted on swarm etc.).

## Solution

When gossiping peers in the hive protocol, currently there is no capability for gossiping multiple underlays for a single peer. Furthermore, when a bee node connects to another node through a pure TCP underlay, it will only gossip that one.

The in-browser nodes can only connect via websocket underlays, therefore the pure TCP/IP addresses are not useful and the relevant gossip protocol message that publicises the addresses to connect to must be extended with an extra field for the websocket underlay. This same field must be added to the handshake protocol as well so that bee nodes learn each other's websocket underlay and potentially spread it even when they connect to each other through pure TCP/IP.

To further help in-browser nodes to find a sufficient number of connectable nodes exposing websocket underlays, it's important to have the websocket underlays enabled by default for full bee nodes.

## Specification

As protobuf 3.0 is even backward compatibly extendable with new fields (as long as existing field numbers don't change), the suggested change is to add the following new fields:

in hive.proto:
    
```protobuf
    message BzzAddress {
        bytes Underlay = 1;
        bytes Signature = 2;
        bytes Overlay = 3;
        bytes Nonce = 4;
    +   bytes WSUnderlay = 5;
    }
```

in handshake.proto:

```ptotobuf

    message BzzAddress {
        bytes Underlay = 1;
        bytes Signature = 2;
        bytes Overlay = 3;
    +   bytes WSUnderlay = 4;
    }
```

The 'wsenable' configuration option must be set by default to true for full nodes, adding a new 'ws-port' configuration option with default set to e.g., 4336 (previously unused).

## Rationale

A limiting factor in accessing the network is the need to install client software, a browser extensions, etc. This can be circumvented by using *public gateways*, that are jeopardizing privacy and are costly to run as it is their operators that pay the bandwidth and the server costs for their customers. What we need is an in-browser client, a node that is run as client side code in the browser and is served through a static page. Since the bandwidth usage is then solely weighing on the content consumer, while the privacy remains intact as the "server" that serves the browser-based client is not involved in any further communication with the swarm network.

## Backwards Compatibility

In theory, protobuf 3.0 already enables backward-compatible updates to protocols as all fields are optional and higher numbered fields can always be added on top of the existing ones.
However it seems more clean to test and introduce such a level of change involving multiple protocols as a breaking change.

## Test Cases
Testing this change would involve checking that nodes joining the network with custom websocket ports gossiped accordingly.

## Implementation notes

--

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
