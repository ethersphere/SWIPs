---
SWIP: <to be assigned>
title: Kademlia load balancing
author: lash <dev@holbrook.no> (https://holbrook.no) Álvaro <alvaro@epiclabs.io>
discussions-to: <URL>
status: Draft
type: <Standards Track (Core, Networking, Interface)  | Meta | Informational>
category (*only required for Standard Track): <Core | Networking | Interface | ERC>
created: <date created on, in ISO 8601 (yyyy-mm-dd) format>
requires (*optional): <SWIP number(s)>
replaces (*optional): <SWIP number(s)>
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->
This is the suggested template for new SWIPs.

Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`.

The title should be 44 characters or less.

## Simple Summary

Initial improvement for evenly distributing requests among peers.

## Motivation

Currently no logic exists to guarantee that routing is distributed among peers in a bin. If a bin is unchanged between kademlia queries for forwarding peers in that bin, currently the most likely result is that the same peer will always be returned. This 

Hence a load balancing mechanism should be introduced. Load balancing is a topic that can be made as complex as desired. However, a simple round-robin scheme distributing requests evenly among the peers is already a vast improvement over the current (lack of) scheme.

## Specification

The component should be a layer above the kademlia itself, and most likely sits in the same layer as - or is even perhaps the same component as - the planned convergence of the request and message forwarding engine (todo link to related issue).

Let the simplest incarnation be keeping a counter that sorts the peers in the number of request in ascending order. The peer with the lower request count is selected.

However, since certain operations only work in conjunction with peers that have certain Capabilities, Capability-filtered peer request counters also need to be kept.

In the first version, there is no need to merge the request counts originated in Capability-filters with unfiltered ones. In other words, if a query returns a low number for Capability "pss" even though the peer does not have the lowest request count overall, this peer is still selected in the context of pss.

## Backwards Compatibility

The implementation should have no compabitility issues

## Test Cases

* Given `m` requests to `n`  peers in a bin, after `m*n` requests the peers will have made `m` requests each.
* Given `m` requests to `n` peers within the neighborhood, after `m*n` requests the peers will have made `m` requests each.
* Given `m` requests for no capability and `ma` requests for capability `a` to peers `n` with all capabilities and `peers `na` with capability `a`, after `n*n + ma*na` requests the `ma` peers will have made `ma+m` requests each.

## Implementation

Pending

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
