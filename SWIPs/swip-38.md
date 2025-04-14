---
SWIP: 38
title: Resolve ENS BZZ text record as website root hash
author: significance (@significance)>
discussions-to: github pr 
status: Draft
type: Standards
created: 2025-04-08
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->
## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Enhance gateway ENS functionality by deferencing a "bzz" ENS TEXT record as well as the currently supported content record with "bzz://" protocol prefix to enable ENS users to simultaneously use Swarm as well as other providers, eg. IPFS.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
When the "content" field of ENS was conceived, it was not initally forseen that there would be multiple networks hosting the same website. With the addition of TEXT records to ENS, this became possible. There are two clear use cases, backwards compatibility/migration (eg. an IPFS user wants to migrate to Swarm but needs to support legacy users still using IPFS) and simultaneous hosting (e.g. a Swarm user wants to also support users that use IPFS). 

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

At present, when an ENS name is presented a Swarm gateway, the content hash is checked and, upon finding that it is a 32 byte hex value prefixed by the bzz protocol indicator "bzz://". 

Now, if the content hash is empty, or not prefixed by bzz://, the ENS TEXT records will next be checked. Upon finding a record with key "bzz", which consists of a 32 byte hex value, handle this in the same way as if it as if it had been found in the content hash.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->


## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
Since this is just an enhancement, and all prexisting functionality to deference ENS content hashes should be retained and preferred if present, there are no backwards compatibility considerations.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
ENS records

### Happy

#### success: render contenthash value as website

contenthash: valid and available swarm
TEXT: bzz, valid and available

#### success: render TEXT value as website

contenthash: valid but unavailable swarm
TEXT: bzz, valid and available hash

contenthash: invalid swarm (i.e. bzz://n0t4h4sh...)
TEXT: bzz, valid and available hash

contenthash: invalid swarm (eg. valid IPFS or something else)
TEXT: bzz, valid and available hash

contenthash: empty
TEXT: bzz, valid and available hash



### Fail

#### fail: return error

contenthash: empty
TEXT: bzz, invalid hash

contenthash: empty
TEXT: bzz, valid but unavailable hash


## Implementation
tbc

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
