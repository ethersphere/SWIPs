---
SWIP: <to be assigned>
title: GSOC
author: Viktor Levente Tóth (@nugaon)
discussions-to: <URL>
status: Draft
type: Standards Track
category (*only required for Standard Track): Core
created: 2024-01-04
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->

GSOC (Graffiti Several Owner Chunk) is the next evolutionary step of [Graffiti Feed](https://github.com/fairDataSociety/FIPs/blob/master/text/0062-graffiti-feed.md), hence it is
> a serverless off-chain information signaling on the Kademlia network.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->

The architecture facilitates finding unknown resources and actors in relation to any particular data by using SOC derived from the data itself.
It can be useful for many use-cases such as forum, content labeling, initializing connection with others and else in a web3 fashion.
It does not require any running backround service to keep up a dynamic workflow and it also can 
act as an _inbox_ or an _open port_ of the Bee node.

Parties aware of the Graffiti consensus are able to read and write under a SOC address which may have multiple payloads.
These payloads can be retrieved one-by-one by a new backward compatible chunk request
or subscribed to if the GSOC address falls within the kademlia neighborhood of the node operator.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

### Improvemets on Graffiti Feed

GSOC offers significantly better properties for aggregation, spam protection, concurrent uploads and pub/sub behaviour over its predecessor.

### Defining the behavior of SOC with multiple payloads

This proposal provides a solution for the unhandled situation as well when there are different payloads under one SOC address.
Currently, the retrieval of such a SOC is undeterministic because of nodes cache different versions,
there is no possibility to retrieve all payloads from nodes that store multiple versions
and syncing is possbile within a neighborhood only so this undefined behaviour cannot be eliminated.
One can argue that this is an incompleteness in the system since these unreachable data in question are payed for storing and storers get compensated for that.
This feature is also needed to keep the serviceless fashion of the Graffiti concept, meaning, 
the dynamic workflow is maintained without any 3rd party operating and that is accessible for the whole network.

### Concentrating related data into one neighborhood

The SOC address can be seem as an _address space_ for Content Addressed Chunks
which allows to channel content into a specific neighborhood.
Thereby, 
- the aggregation of related data is easier because a service node can react immediately on chunks under the specified SOC address,
- the postage batch prevents flooding the GSOC with trash content because all data belongs to one neighborhood,
- GSOC can substitute PSS messaging with lower resource requirement._*_

_*it does not need to mine CAC address (which requires to build up 7 levels of Binary Merkle Tree each time), only a SOC address for a random assymetric key once. The subscription is also significantly lighter because it does not try to cast all incoming chunk to message only those that have an exact SOC address. With the new SOC chunk request, there is no need to run node for accepting messages, therefore the messaging feature can be available on gateways as well._

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

### Graffiti Consensus

GSOC is technically a simple SOC for which an assymmetric keypair must be created and an identifier must be constructed.

The proposal describes how to generate the keypair and construct the SOC address for data signaling along with its additional requirements.

#### GSOC assymmetric keypair

The GSOC private key (consensual private key = `cpk`) is solely derived from the `data`
that can be any binary data to which graffities relate.

If the data is available on the Swarm network, the CPK equals to its Swarm Address `cpk = swarmAddress(data)`, (which is the topmost segment of the BMT/Chunk Tree)
else the CPK simply equals to its keccak256 hash `cpk = keccak256(data)`.

The corresponding public key (along with the Ethereum Address `etha`) can be generated by using the ECDSA.

#### GSOC identifier

The identifier (GSOC Identifier = `gi`) is nothing else than a sequence of arbitrary 32 bytes which is one of the components used in the SOC address calculation (`socAddress = keccak256(gi, etha)`).

For that, a hashed string should be used which mines the SOC address as well to the desired neighborhood: 
`gi = nonce ? keccak256("AppName:v1") : keccak256("AppName:v1:" + nonce)`, were the _AppName_ is the name of the used consensus and _v1_ is the version of it.
This convention allows to define different consensus on the same resource and quickly mine SOC address to the neighborhood where the service node is active.

#### Write and read

GSOC payloads must satisfy a message format defined by the consensus or they will be filtered out as invalid data after retrieval.

such a message format can be expressed in an interface like this:
```ts
interface GraffitySocRecord {
  iaasIdentifier: EthAddress, // 40 chars longs string without 0x prefix
}
```
on which an assertion function can check whether the message satisfies the conditions.

The storage client must allow to upload chunk if the wrapped address of the SOC was never uploaded before.
Optionally, it can prevent to use up an additional postage stamp if the wrapped address belonging to the SOC address in question was stamped already.

Anyone can write a GSOC who is aware of the consensus, nevertheless, the message payload can be signed by the key of the uploader (additionally to SOC signing)
or the message can contain a reference to a storage area that only the sender can write.
If the storage area points to a SOC or Feed of the sender, the identifier or topic should be `psi = keccak256(cpk + gi)` within their personal storage.

### Change in the Chunk retrieval protocol

The format of the current chunk request has only one parameter:
```
ChunkRequest(chunkAddress bytes32)
``` 
The _constrained SOC request_ format introduces three optional parameters, namely the `optionType`, `wrappedAddress` and `prefixLength`:
```
ChunkRequest(chunkAddress bytes32, optionType uint8, wrappedAddress bytes32, prefixLength uint8)
```

These express the followings:
- `optionType`: defines what type of option parameters defined after the `chunkAddress`. It is `0` in case of constrained SOC request
- `wrappedAddress`: the address with which the address of the wrapped chunk (signed chunk address in the SOC) must match,
- `prefixLength`: defines how many prefix bits must match of the `wrappedAddress` with the actual wrapped chunk address.

Nodes must reject the request even if the `chunkAddress` has related chunk but that does not satisfy the other conditions.

### SOC subscription

Defining new API endpoint:

`GET soc/subscribe/{socAddress}`

that opens a new websocket channel relaying every new incoming SOC payload.

The same feature is elaborated in GitHub issue [#4333](https://github.com/ethersphere/bee/issues/4333)
though that approaches it from a different use-case. Here, the `socAddress` is obviously the address of the GSOC

### Postage Stamp Indexing

Since nodes can store different SOC payloads, new Postage Stamp restriction should be applied in order to allow multiple valid SOC payloads.
This must be introduced because of the incentivisation of the storer nodes; they have to prove that they store different payloads of a common and single SOC address.
The current stamping validation checks whether the stamp owner signed against the SOC address for which any content is valid that has valid SOC singature from the uploader. If it remains like this with GSOC, only the bandwith incentive active for the GSOC content upload that allows infinite content store.
In order to prevent this, the `timeStamp` PS attribute can be utilized to carry the prefix of the wrapped content address of the GSOC.
It has to be applied for the storage incentive SOC checks as well which requires smart contract modification.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The new request format allows to bypass caching and make paid out SOC payloads queryable.
Several other chunk request formats could also satisfy this feature but these points were preferred: 
- facilitating the serialization of the arguments and avoiding from overflow edge-cases (fixed lengthed parameters),
- let place for other request modifiers (`optionType`).

Graffiti Feeds do not allow concurrency even if the users act honestly because those may write on each other's index, making the Graffiti record ambiguous on retrieval.
Moreover, indices in Graffiti Feed cannot keep any canonical order of updates since uploaders use Postage Stamps with different lifespans.
On the other hand, building the idea on handling multiple payloads seems to graduate the Graffiti concept meanwhile defining an undefined behavior in the system.

As mentioned, storing records in a single neighborhood facilitates aggregation which is essential for popular topics and only possible if record addresses share the same prefix until the storage depth of the network. 
This could be done by mining but that is slow, computational heavy and that does not indicate correlation between records.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
On incoming chunk request, clients must check the byte length of its arguments which may differ from the default 32 bytes.
If so, then `optionType` on the 33rd byte must be checked and according to that the request should be handled.
This workflow keeps the original chunk request intact.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
_TBD_

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
_TBD_

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
