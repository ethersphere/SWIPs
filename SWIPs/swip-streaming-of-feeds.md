---
SWIP: <to be assigned>
title: Fault tolerant and flexible streaming of feeds
author: Viktor Levente Tóth (@nugaon)
discussions-to: <URL>
status: Draft
type: Interface
category (*only required for Standard Track): ERC
created: 2021-06-30
---

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
This _feed indexing method and its corresponding lookup_ achive the retriaval of a feed's most recent state in `O(1)` queries.

For that, the feed indices are anchored to their uploading times.

This method is optimized for downloading a feed chunk queried by a point in time as quickly and cheaply as possible.

It introduces new requirements for the uploader, but those are not strict and the lookup method corrects the inaccuracies of the stream.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
Mutable content can be streamed periodically from a content creator, where getting the _closest state_ to an arbitrary time as fast as possible is the most important factor.
Achive the fastest retrieval method of a feed stream which is optimised to download the closest available segment of the feed at a given update time.
It is intended to decrease the lookup processes on the network as much as possible. 
The main use-case is to get the last updated state of the content, for that there is a finite set of feed indexes in order to start its lookup method from the last (possible) updated feed index.
The owner of the feed _promises_ to upload feed segments for every time interval choosen, but it is a weak requirement and it is possible to leave out indexes from the stream in exchange for slower retrieval speed of the stream.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
The lookup time of feeds can be significantly long where the lookup process only stops if there is no newer content under a feed. 
A solution is needed where this approach is reversed: a lookup that stops if there is a successful hit before of a given upload time.
This lookup time can be shorthened already by not waiting for the last (non-existing) feed retrieval.
If the uploader keeps itself to the periodic feed indexing and it uploads every time when is needed, the retrieval for the user is `O(1)`.
Nevertheless, the lookups can easily go wrong, because of (1) network issues or (2) the uploader cannot upload the content in time.
These problems are equivalent from the retrieval perspective and the first one is also related to the epoch-based and sequential feeds. 
Any chunk of the lookup trajectory is not available (even temporary) then it could cause huge inaccuracy, but an approach like this is always closer or the same close to a desired upload time.
Moreover, the current lookup methods keep those chunks alive that maybe unnecessary from the content usage side when the goal of the content (or dApp) is to provide the most up-to-date state.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

In the following subsections I would like to detail how to:
* [get the nearest last index of an arbitrary time](###-Nearest-Last-Index-for-an-Arbitrary-Time)
* [construct feed topic](###-Feed-Topic-Construction)
* [upload feed chunk](###-Upload-Feed-Chunk)
* [download feed chunk at specific time](###-Download-Feed-Chunk-At-Specific-Time)
* [and download (whole) feed stream](###-Download-Feed-Stream)

The feeds always have a `topic` and an `index`, that we have to define.

### Nearest Last Index for an Arbitrary Time

Let's figure out what is the nearest last `feed index` of a given arbitrary time.
We know the current time right now (`Tp`) which is surely greater or equal to the last upload time (`Tn`) of the feed stream.
We also know two metadata of the stream: initial time (`T0`) and update period (`Δ1`).
We want to find the nearest last index to an arbitrary time (`Tx`) where `T0 <= Tx <= Tn <= Tp`
All of these are timestamps and their smallest unit is 1 second, e.g. even with this time unit it is still uncertain whether the latest update can be downloaded if `Tp = Tn`, because of the nature of P2P storage systems.

So the formula is really simple how to calculate the nearest last index parameter (`i`) of the `Tx`:

```ts
function getIndexForArbitraryTime(Tx: number, T0: number, updatePeriod: number): number {
  return Math.floor((Tx - T0) / updatePeriod) // which is the `i`
}
```

### Feed Topic Construction

The `feed topic` has to contain the initial time (`T0`) and optionally can be prefixed/suffixed with an additional identification so that the uploader with the same key can maintain many distinct feed streams.
Either of them is chosen, the feed topic construction algorithm has to be the same and well-known between the parties. 

### Upload Feed Chunk

Within the upload function, the current time (`Tp`) is initialized and the `feed index` of the newest feed chunk can be calculated by calling `getIndexForArbitraryTime(Tp, T0, updatePeriod)`.
After the `feed topic` is initialized as well in the before mentioned way, the uploading can happen as at other feed uploads. 

### Download Feed Chunk at Specific Time

The feed download method only has 2 required parameters, where the last one is optional: `function downloadFeed(owner: EthAddress, topic: bytes[], Tx?: number): Feed`.

If the last parameter has not been passed, the `downloadFeed` function will calculate the nearest last index based on the current time like within the uploading feed function.

There are cases when the chunk is not available on the first calculated index, then the lookup method starts and tries to find the nearest downloadable chunk.
The most reasonable approach here is check the previous (`i-1`) and the next fetch index (`i+1`) until the worst case respectively `0` and last (`n`) index. 
This lookup also can happen paralelly and checking _n_ chunks simulteniously on both sides in order to raise the certainty for the successful hit.

### Download Feed Stream

The downloading of the stream is really straightforward, we should download all feeds one-by-one or paralelly starting from `0` index until and included `getIndexForArbitraryTime(Tp, T0, updatePeriod)` index.

The integrity check of the stream can only happen by putting versioning metadata into the feed segments, because the content creator may not intend to upload for every uploading time period (despite of the incentivised factor of this feed type).

Some other optimalizations, features and other aspects are described in the [next chapter](##-Rationale).

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The current worked out solutions of handling a content stream (Book of Swarm, Subscriptions, page 112) approach the update tracking by:
- push notifications about the update (PSS)
- epoch-based indexing for sporadically updated feeds
- polling for almost ideal periodic updates (frequent updates)

Though the book mentiones also _periodic feeds_ for calculating index of feed starting from a specific well-known time, 
but it does not touch the scenario what if the updates are _parlty sporadic_ and those are may not available or not uploaded.

This requires an **indexing method** that extends the `periodic feeds` indexing and a **specific retrieval method** to handle the holes in the update stream.

The best approach to get the closest feed of an arbitrary time is using epoch-based feeds, but its downside - additionaly to that I summarized [above](##-Motivation) - is after every writing the retrieval is slower. 
It is similar to that analogy when a hard drive is fragmenting because of the many frequent writes within one sector (base fragment of the epoch time lookup). 
This proposed feed indexing method is the opposite as at lookups: 
if there is expected amount of writes periodically, the retrieval of the data is faster, that even can be _O(1)_. 
Compared to the epoch-based feeds, basically the length of the base segment is arbitrary, and it encourages the user to make periodic uploads and stick to this base segment instead of sporadic uploading in exchange for better retrieval time.

The downside is within the concerted update time period the content creator cannot update the state of the feed - although it is possible to overwrite the content of a feed by uploading it again with different payload, but on download-side it is possible to still to get back the old one. 
This problem can be mitigated by changing the registry of the feed, from where the consumers get the initial metadatas of the feed: 
- the initial timestamp (`T0`) should be changed to that point from where the time period changes (`T1`)
- change the new time period (`Δ2`) from the old one (`Δ1`) for state uploads

If the registry settled on blockchain in a smart contract, then it can have a defined event on metadata change of the content, on which the clients can listen.
Thereby, the consumers of the feed can immediately react to the upload frequence change and they can poll according to the new rules.
If somehow the blockchain listening on client side is not suitable, it is possible to put the `uploading time period` and `initial timestamp` metadatas into all of the feed stream updates so that the consumers can sync to the stream after `MAX(Δ1,Δ2)` time if `MAX(Δ1,Δ2) % MIN(Δ1,Δ2) = 0` and  there is one `k` and `m` positive integer where `T0 + (k * Δ1) = T0 + (m * Δ2) = T1`

Though it is stated this approach does not address downloading the whole feed stream, it is still possible:
* In case of punctual updates without any upload time period change, the stream download is identical with the sequential/periodic feed stream download.
* If the uploading time period has been changed, the feed index set construction should happen either considering the before mentioned blockchain event emitting or if it is contained only in the feed metadata, then when it changes in the downloading process it is necessary to start a lookup backwards if `Δ2 < Δ1` until the change, but maximum `z = Δ1 / Δ2` units.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
The whole idea can be implemented on application layer using single owner chunks, but optionally the solution also can be integrated to the P2P client.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
_Pending_

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
_Pending_

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
