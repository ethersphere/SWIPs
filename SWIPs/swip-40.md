---
SWIP: 40
title: Recursive Encrypted Chunk Read Support
author: Mirko Da Corte (@tmm360) <mirko@etherna.io>
discussions-to: https://discord.gg/WjSGyUrg
status: Draft
type: Standards Track (Core, Networking, Interface)
category: Core
created: 2025-08-11
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Define manifest metadata and intermediate-chunk conventions that enable nodes to read recursively encrypted Swarm chunks.  
This supports the practice of address chunk hashes into less-collided postage buckets by mining per-chunk keys (chunk compaction) and remains backward compatible with legacy content.  
In this document, “legacy” refers to unencrypted chunks and non-recursively encrypted BMTs, which are not deprecated.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
This proposal standardizes how clients detect and decode recursively encrypted data and intermediate chunks.  
It introduces two manifest metadata fields and an intermediate-chunk "hash-key" schema that together provide the information needed to decrypt child chunks during traversal.  
The proposal is read-only in scope: it does not mandate how keys are produced nor how chunk hashes are optimized.  
Mantaray node chunks remain compatible as-is, using their existing obfuscation mechanism. Legacy content continues to decode unchanged when the new metadata is absent.  
With these conventions, implementations can interoperate with chunks that use recursive encryption to improve postage-batch utilization without breaking existing content.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Chunks produced with recursive encryption improve postage-batch utilization by enabling a more uniform distribution of chunk hashes across postage buckets. However, without a shared read convention to discover per-child decryption keys during traversal, such chunks are unreadable for clients. A minimal, interoperable read specification is needed so that:
- legacy content remains readable with no changes,
- new content can signal recursive encryption and supply the necessary keys,
- clients can implement a deterministic traversal and decryption procedure with clear error handling.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
Scope: read/decoding only. This SWIP does not prescribe key generation or any write-side optimization strategy.

1) Manifest metadata (per file entry)
- `recursiveEncrypt`: boolean
  - Absent or false ⇒ default false (legacy decoding).
  - true ⇒ the BMT subtree uses recursive encryption.
- `chunkEncryptKey`: string
  - May be present to provide the root decryption key.
  - When recursiveEncrypt is true, a root key MUST be available either in chunkEncryptKey or via an application/API parameter.
  - When recursiveEncrypt is absent or false, the presence of chunkEncryptKey indicates that only the root data chunk is encrypted; recursive decryption MUST NOT be applied to intermediate chunks.
  - Encoding: 32-byte XOR key.

2) Intermediate chunk key table
- Format: up to 64 fixed-size entries; each entry is 64 bytes, written as raw bytes:
  - childRefHash: 32 bytes (the child’s Swarm hash)
  - childEncKey: 32 bytes (the child’s encryption key)
- A table length MUST be a multiple of 64 bytes and MUST NOT exceed 4096 bytes.
- Inheritance: intermediate chunks inherit the recursiveEncrypt reading mode from their parent. If the parent is read with recursive encryption, the child must be read recursive encryption too.

3) Decoding procedure (reader)
- If recursiveEncrypt is absent or false:
  - Use legacy decoding; nothing changed.
  - If chunkEncryptKey is present while recursiveEncrypt is absent/false:
    - Decrypt only the root data chunk with the provided key.
    - Treat all intermediate and leaf chunks as legacy (no recursive decryption).
- If recursiveEncrypt is true:
  - Obtain the 32-byte root decryption key (from chunkEncryptKey or an application/API parameter).
  - Decrypt referred chunk with the provided key.
  - For each intermediate chunk:
    - Parse its key table into up to 64 entries.
    - For each child reference, lookup at childRefHash on Swarm DISC, and use childEncKey as the XOR key for that child's data.
  - Continue recursively until leaves are read.
- Mantaray node chunks:
  - Unchanged: read using existing obfuscation rules; this SWIP does not alter mantaray decoding.

4) Error handling
- Invalid metadata:
    - `recursiveEncrypt == true` and no chunkEncryptKey provided.
- Intermediate table inconsistencies:
    - Data length not multiple of 64 bit when `recursiveEncrypt == true`

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->
- Backward compatibility by default: absent metadata yields legacy decoding.
- Minimal surface: two manifest fields and a fixed-size key table reuse existing structures without introducing new chunk types.
- Fixed-size table (64 × (32+32) = 4096 bytes) aligns with intermediate chunk capacity, enabling O(1) lookups and simple parsing.
- Per-file granularity: same mantaray allows pointing at the same time to both encrypted and unencrypted contents. This permits full compatibility with already published contents.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
- Legacy readers that ignore the new metadata and intermediate chunk's schema will not be able to read recursively encrypted content; however, legacy content is unaffected and continues to decode unchanged.
- Mantaray node chunks remain as-is; chunks compaction is implemented with already implemented mantaray nodes obfuscation.
- Default behavior (metadata absent) preserves existing datasets and workflows.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
- Manifest reading (ex: GET /bzz):
  - recursiveEncrypt=false or absent and chunkEncryptKey absent ⇒ legacy decoding succeeds.
  - recursiveEncrypt=true with valid chunkEncryptKey ⇒ recursive decoding succeeds.
  - recursiveEncrypt=false or absent with valid chunkEncryptKey ⇒ only root is decoded without recursive encryption.
- Raw data reading (ex: GET /bytes):
  - as for metadata with manifest, but parameters can be passed by API. Legacy decoding by default.

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
A working implementation has been provided with Bee.Net (https://github.com/Etherna/bee-net).

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
