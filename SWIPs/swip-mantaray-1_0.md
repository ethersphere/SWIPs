---
SWIP: <to be assigned>
title: Mantaray 1.0
author: Viktor Levente Tóth (@nugaon)
discussions-to: <URL>
status: Draft
type: Core
category (*only required for Standard Track): Core
created: 2021-12-08
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
The `mantaray` data-structure is widely used whithin the Swarm ecosystem;
just to mention one, `manifests` are built on the `mantaray` data-structure, which consist of paths and files mappings of all dApps live on Swarm.

This proposal fixes some design issues of the current `mantaray v0.2` data-structure and additionally provides better metadata handling and makes possible to have reliable web3 services that deal with tree-like data-structures.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
The ojvectives that this proposal seeks to achieve:
1. **handling matadata of mantaray node**: currently, by design, only the mantaray forks can have metadata,
2. **polishing mantaray flags**: some flags are not necessary or not clear why they were implemented,
3. **the elements of the mantaray node body have random access**: the forks define their own metadata length, which makes forks to have only sequential access.  

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
(Mantaray 0.2 binary format can be found [here](https://github.com/ethersphere/bee/blob/377b43bb835261c074708ea87d09517bffdf7614/pkg/manifest/mantaray/docs/format/node.md))

Referring to the list in the Abstract:
1. There is a need to have accessible metadata on the node level about the node; one evidence is [the `/` path hack that also has some problems](https://github.com/ethersphere/bee/issues/2549). At the current metadata handling, it is always necessary to rely on such hacks that pollute the tree structure as well.
2. The `nodeType` encapsulated in the mantaray byte representation consists of the following flags:
  - `value`: notates whether the node's `entry` reference is defined or not. It is a useful flag, nevertheless, if it is zero, then 32 bytes of data is reseved for the `entry` anyway that does not carry any information.
  - `edge`: the node has additional forks that are referring to other mantaray nodes. Again, it is useful, but still the dedicated compressed mapping of forks, namely `forksIndexBytes <32 bytes>` is not omitted if it is zero.
  - `withPathSeparator`: it is unclear what this flag is used for.
  - `withMetadata`: indicates whether the forks have metadata or not. It seems it just saves the 2 bytes `metadataBytesSize` under each fork. The problem here is the metadata length for forks should be the same under one node, but about it in the next point.\
  \
  the `nodeType` is defined on fork, however, it could be a useful information on node level as well.
  Additionally to these, there is `refByteSize`(1 byte) on the node level, that only describes whether the `entry` (32/64 bytes) is an encrypted reference or not which could be a 1 bit flag instead.
3. Because the forks can have different byte length under a node, the fork array does not have random access. It is a huge problem, not only because the fork deserialisation is not optimal, but one also cannot perform _inclusion proof_ on forks. Thereby, web3 services cannot work reliably with tree-like data-structures, because the proof would be incredibly expensive on the blockchain for one particular segment of fork data.
If the fork metadata length would be unified and defined by the node for each fork then this issue could be sorted out.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

The specification elaborates the discrepancies from the current version and the new features. 

### Node

Node binary format:
```text
┌────────────────────────────────┐
│    obfuscationKey <32 byte>    │
├────────────────────────────────┤
│ hash("mantaray:1.0") <31 byte> │
├────────────────────────────────┤
│      nodeFeatures <1 byte>     │
├────────────────────────────────┤
│       entry <32/64 byte>       │
├────────────────────────────────┤
│   forksIndexBytes <32 byte>    │
├────────────────────────────────┤
│ ┌────────────────────────────┐ │
│ │           Fork 1           │ │
│ ├────────────────────────────┤ │
│ │            ...             │ │
│ ├────────────────────────────┤ │
│ │           Fork N           │ │ -> where N maximum is 256
│ └────────────────────────────┘ │
├────────────────────────────────┤
│     nodeMetadata <varlen>      │
└────────────────────────────────┘
```

#### nodeFeatures
- 3 bit flags + 5 bit forkMetadataSegmentSize
- flags
  - hasEntry
      - whether the node has `entry` field
      - +32 byte at nodeByteSize calculation
  - encEntry
      - if `hasEntry` 0 it cannot be 1
      - the `entry` field is an encrypted reference and 64 bytes long
      - +32 byte at nodeByteSize calculation
  - edge
      - whether the node has additional forks or not
      - if 0, then [forkIndexBytes](#forkIndexBytes) is omitted
      - +32 byte at nodeByteSize calculation
- forkMetadataSegmentSize
  - the first 5 most significant bit in the `nodeFeatures` bitvector
  - its `value * the segment size (32)` gives the reserved bytesize for metadata under each forkdata
  - the size is only the local maximum for metadata size, it does not apply or define for the whole tree

#### entry
- depends on the [nodeFeatures](#nodeFeatures)
    - if `hasEntry` is 0, it is omitted
    - if `encEntry` is 1, then it has 64 bytes length

#### forkIndexBytes
- notates and compresses what fork prefixes the node has
- depends on the [nodeFeatures](#nodeFeatures)
    - if `edge` is 0, it is omitted
    - if `edge` is 1, then it is 32 byte length and has at least one true bit in the bitvector.

#### nodeMetadata
- it is specified by another data structure
    - on which you can also perform inclusion proof in need
    - it can consist of content ID references of metadata on swarm that can be cashed
        - such as `Content-Type: index.hml`
    - it can describe its own length.
- in Mantaray 1.0 version it can be stringified JSON object.
- The remaining bits after forks' data can be utilised for any arbitrary metadata, because on node header interpreation one can define exactly until what length the mantaray data last until the end of the forks.


### Fork

Fork binary format:
```text
┌───────────────────────────────┬──────────────────────────────┐
│     prefixLength <1 byte>     │        prefix <31 byte>      │
├───────────────────────────────┴──────────────────────────────┤
│                    reference <32/64 byte>                    │
├──────────────────────────────────────────────────────────────┤
│        metadataBytes <forkMetadataSegmentSize * 32 byte>     │
└──────────────────────────────────────────────────────────────┘
```

- prefixLength
    - if it is > 31 (`prefix` length) then the mantaray fork's node is a continuous node -> on `addFork` it has to be taken account (shorten the child's node prefix by the common part until `prefixLength <= 31`)
- mantarayReference
    - always has same length as its parent node's `entry` length
- forkMetadata
    - in structure the same as [nodeMetadata](#nodeMetadata)
    - its length are defined by forkMetadataSegmentSize

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

Each separate part of the data-structure has been made for fitting into 32 byte segments in order to perform inclusion proof on that easily.

The structure of the `nodeMetadata` and the `forkMetadata` are stringified JSON objects as in the current version.
Obviously, it is not the best solution to store effectively any metadata, but it may require to introduce a new data-structure which satisfies also the 32 byte segments requirement and else.
Because of this, it seems the best to elaborate the metadata structure in a separate SWIP that can be employed in the following Mantaray version `1.1`.


## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
- instead of the designated `/` mantaray node which is used for setting `website-index-document`, the node can have [nodeMetadata](((wYiUD26Ek))) that consists of the same metadata
- how to get `nodeType` values on `mantaray:1.0` node
  - value
    - `hasEntry` flag is 1
  - edge
      - `edge` flag is 1
  - withPathSeparator
      - couldn't identify what was its role before
  - withMetadata
      - `nodeMetadata`'s length is greater than 0 OR
      - parent node sets its metadata if `forkMetadataSegmentSize` is greater than 0
- the `addFork` and `removeFork` interfaces remain the same.
- obfuscation key handling method remains the same, but for every new mantaray node should have different `obfuscationKey` than its parent if the `obfuscationKey != zeroBytes`

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
TBS

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
TBS

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
