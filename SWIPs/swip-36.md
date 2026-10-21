---
SWIP: 36
title: Free uploads without postage stamps
author: Viktor Trón <viktor@ethswarm.org> (@zelig)
discussions-to: discord SWIP channel, https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Core
created: 2025-03-17
---

# Free uploads without postage stamps 


## Abstract

In this SWIP, we are introducing a free tier for Swarm  uploads by making postage stamps optional. Uploading a chunk without  a postage stamp will offer rather weak guarantees of persistance, therefore it is advised to use the construct with a non-zero level of cross-neighbourhood redundancy.

## Motivation

As for bandwidth incentives, Swarm already has a free tier: essentially offering normal relaying with throttled throughput.[^1] Since downloading content only incurs bandwidth costs, this translates to the availability of free download functionality. Users[^2] expect this free tier to apply to the upload of at least temporary files, but, currently, Swarm expects a valid postage stamp to be attached to each chunk pushed.

[^1]: Throttling is implemented as a fixed rate of subsidy, so called *time-based allowance* available on each peer connection. 

[^2]: especially given that they are habituated to free cloud services on web2.

Chunks that are meant as short-lived messages  used in chat or as notifications are not meant to be persisted. Paying for a batch slot is unnecessary in these cases.
Note that on top of this, signing a stamp on the batch owner side as well as signiture validation by the forwarders and storers take a lot of CPU, which could otherwise be spared. 

When all its associated stamps expire, a chunk is expunged from the node's reserve. These expired chunks are not deleted but are put to the *cache*, giving popular chunks a chance to survive. Even if no longer eligible for storage incentive rewards, a chunk can potentially earn the node some profit through the bandwidth incentives as long as the node can serve it. Since the profitability of any one chunk is best predicted by its past access pattern, this could, in principle, be reflected in how the chunk is inserted in the cache.[^3] 


[^3]: One such pattern would involve tracking the access frequency of past retrievals even for chunks in the reserve, so that this information can then be used to insert into cache differentially, i.e., more frequent items are deleted before less frequent ones. 

Recency also plays a role, more recently accessed items are more likely to be requested than items accessed long time ago. In fact, since this is true of items never accessed, the time of first storage should also be reflected in which position we save an item to the cache. However, in this case especially, it does not make sense to prevent uploaders to do the same: to push a chunk in the cache. 
## Solution
This anomaly is remedied if the push-sync protocol accepts chunks without postage stamp and nodes forward it to the neighbourhood it belongs to based on their address, where it is then put in the cache of the nodes (or at least that of the closest node).[^4]

[^4]: Note that this is an entirely different motivation than free bandwidth, and unlike bandwidth, requires handling on the protocol level. The book of swarm argues that charging bandwidth for both retrieving and pushing chunks are critical (\S 3.1., pp79-89) for the security of the network. Some usecases (especially those that serve onboarding, e.g., the in-browser client) are calling for at least a limited free offering. While agreeing with this, it might nonetheless be better serving the network to subsidise the free tier explicitly through communal faucets, etc.  i.e., not on the protocol level.

## Feasability 


### targeted spamming

The only relevant function of stamps is that upload of chunks is actually load-balanced.[^6] Without mandatory postage stamps attached to chunks, caching nodes can be target to attack;[^5] i.e., a malicious node can just mine random chunks with an address close to a targeted node  posts them without a stamp. If bandwidth for upload is free and this is being done in a volume comparable to the cache size, the cache of all the nodes in the entire neighbourhood may well be reset. To mitigate this case we need to introduce a restriction on where in the cache the item is included. If the insertion is such that the item can override the most popular items, then an attacker can rewrite the entire cache content. If none of the chunks will ever be retrieved, then the node is robbed of all its potential bandwidth revenue at least until enough new chunks come in and are requested which can neutralise the attack. 
We conclude that free bandwidth for upload must be limited in absolute terms for chunks without stamps.

[^5]: The function of postage stamps include expressing an incentive-aligned signal of preference to help them manage their reserve; clearly irrelevant if the chunk is not put in reserve.

[^6]: Note that this attack is not new, in the sense that it can be relatively cheaply performed with skewed batches with short TTL.


### availability guarantees

in the cache are not synced across nodes of the neighbourhood and therefore they may not survive network growth either through new nodes[^7] or new content[^8] or a lot of use. 

[^7]: if a new node comes in then retrieve requests for chunks closest to it may not reach the node that was the closest before (even though they are the only one having the chunk).

[^8]: as new content is added and longer term the rate of new chunks appearing is higher than the total of 

## Implementation 

implementation notes to be included

### Backward compatibility 

Due to the stamp becoming an optional field, push-sync protocol's message types are redefined, so implementing this SWIP will break **backward compatibility**.

### Test Cases


## Copyright


Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
