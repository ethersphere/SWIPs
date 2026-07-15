---
SWIP: <to be assigned>
title: Pullsync Chunk checksum for divergent sync
author: acud (@acud)
discussions-to: <URL>
status: Draft
type: Standards Track
category: Networking
created: 2026-07-14
---

## Simple Summary

Change the pullsync `Chunk` message so that, instead of advertising a chunk's
batch ID and stamp hash as two separate fields, a node advertises a single
16-byte checksum (`Sum`). The checksum is a compact fingerprint of the
information a peer needs in order to decide whether its copy of a chunk diverges
from ours and therefore needs to be synced. This shrinks the offer message,
and — crucially — lets single-owner chunks (SOCs) that share the same SOC
address but wrap different content be recognised as distinct and synced
independently.

## Abstract

The pullsync protocol advertises candidate chunks to a downstream peer using a
`Chunk` message carrying three fields: `Address`, `BatchID` and `StampHash`. The
downstream peer uses these to decide whether it already has an equivalent chunk.
This SWIP replaces `BatchID` and `StampHash` with a single field, `Sum`, a
16-byte Keccak checksum. For a content-addressed chunk (CAC) the checksum is
`keccak(batchID | stampHash)`; for a single-owner chunk (SOC) it is
`keccak(batchID | stampHash | wrappedCacAddress)`. The receiver's sync decision
becomes a single lookup, `if !storage.Has(address, sum) { sync }`, delegating the
retention/override policy to the storage layer rather than encoding it in the
protocol. Folding the wrapped CAC address into the checksum for SOCs makes two
SOCs with an identical SOC address but a different wrapped payload produce
distinct sums, so both can be pulled. The change is a breaking wire change to the
`Chunk` message and requires a protocol version bump.

## Motivation

The existing `Chunk` message is inadequate for two reasons.

1. **SOCs with a shared address but divergent content cannot be distinguished.**
   A single-owner chunk's address is derived from its owner and identifier, not
   from its payload. Two SOCs can therefore share the same address while wrapping
   different content-addressed chunks. The current offer, keyed on
   `(address, batchID, stampHash)`, gives the receiver no protocol-level signal
   that the wrapped payloads differ, so a divergent SOC may fail to sync. To
   allow SOCs to be transferred between nodes correctly, the protocol must carry
   enough information to detect this divergence.

2. **The sync decision is over-specified and the message is heavier than it
   needs to be.** The receiver reconstructs an equality decision from two
   separate identifier fields (64 bytes combined). This bakes a specific
   comparison into the protocol and costs wire bytes on every offered chunk,
   across every bin, on an ongoing basis.

Rather than *adding* a field (e.g. the wrapped address) to cover the SOC case —
which would make the message heavier still — this SWIP *reduces* the message to
a single opaque checksum that subsumes all the divergence-relevant inputs. The
checksum is a signalling mechanism: it tells a peer whether our
address/stamp/content permutation differs from theirs. The actual decision of
what to store, override or discard is made by the storage abstraction on
delivery, where the full stamp is re-validated — not by the protocol. This keeps
the protocol mechanism trivial while allowing the persistence layer to evolve
richer retention heuristics independently.

The cost is one hashing operation per chunk. Using the optimised official Keccak
hasher this is negligible in latency and allocation-free, and the checksum is
computed once at write time (see Specification), not per offer.

## Specification

### Message format

The `pullsync` `Chunk` message is redefined from:

```protobuf
message Chunk {
  bytes Address = 1;
  bytes BatchID = 2;
  bytes StampHash = 3;
}
```

to:

```protobuf
message Chunk {
  bytes Address = 1;
  bytes Sum = 2;
}
```

The `Offer`, `Want` and `Delivery` messages are unchanged. In particular
`Delivery` still carries the full serialised postage stamp, so the receiver
retains every input required to independently recompute `Sum` and to validate
the stamp on delivery.

### Checksum definition

`Sum` is the first 16 bytes of a Keccak-256 digest over the concatenation of the
divergence-relevant inputs, in order:

- **CAC:** `Sum = keccak256(batchID ‖ stampHash)[:16]`
- **SOC:** `Sum = keccak256(batchID ‖ stampHash ‖ wrappedCacAddress)[:16]`

where:

- `batchID` is the 32-byte postage batch identifier,
- `stampHash` is the hash of the chunk's postage stamp (as produced by the
  existing stamp hashing routine),
- `wrappedCacAddress` is the 32-byte address of the content-addressed chunk
  wrapped by the SOC.

The inputs are concatenated with no separator; the field widths are fixed, so
the encoding is unambiguous. A node MUST compute the SOC form for single-owner
chunks and the CAC form for content-addressed chunks.

### Sender behaviour (offer construction)

When assembling an `Offer` for a requested interval, for each local chunk the
sender emits `Chunk{ Address, Sum }`. To keep offer construction allocation-free
and independent of chunk payloads, `Sum` MUST be precomputed and persisted in the
reserve index at chunk `Put` time and read back when building the offer. This is
necessary because offers are built from index metadata, and the SOC checksum
depends on the wrapped CAC address, which is not otherwise part of that metadata.

### Receiver behaviour (offer processing)

For each offered `Chunk` within the receiver's storage radius, the receiver
performs a single divergence check against its storage layer:

```
if !storage.Has(address, sum) {
    // request the chunk in the Want bitvector
}
```

Wanted chunks are tracked keyed on `(address, sum)`.

### Delivery matching

`Delivery` messages are unchanged. On receiving a delivery, the receiver
recomputes `Sum` from the delivered stamp (and, for a SOC, the wrapped CAC
address recovered from the delivered chunk), and matches it against the
outstanding `(address, sum)` want set. A delivery whose recomputed `(address,
sum)` is not in the want set is rejected as unsolicited. The stamp is then
validated exactly as today before the chunk is put to the reserve.

### Origin-side lookup

The `Sum` is a wire signal only and is never used as a lookup key on the origin
node. When servicing a `Want`, the sender resolves each wanted chunk using the
local identifiers it already holds for that offer entry (address, batch ID, stamp
hash), not by reversing `Sum`.

### Protocol version

This is a breaking change to the `Chunk` wire format. The `pullsync` protocol
version MUST be incremented. Nodes running the old and new versions are not
interoperable on this stream (see Backwards Compatibility).

## Rationale

**Why a single opaque checksum rather than adding a field.** The SOC-divergence
problem could be solved by adding `WrappedAddress` to the `Chunk` message, but
that grows an already-repeated message. Collapsing all divergence inputs into one
checksum both solves the SOC case and reduces per-chunk overhead. The protocol no
longer needs to understand the structure of the identity; it only needs to know
whether two permutations differ.

**Why the storage layer owns the decision.** Making the protocol check a single
`storage.Has(address, sum)` means the protocol expresses intent ("do our
permutations differ?") and nothing more. What to keep, override, or discard —
and any future heuristic about divergent chunks — lives in the persistence layer,
where the full stamp is available and re-validated. This decouples protocol
evolution from storage-policy evolution.

**Why 16 bytes.** `Sum` gates only the sync-or-not decision; it is never trusted
as chunk identity, and the full stamp is re-validated on delivery. A 16-byte
(128-bit) truncated Keccak digest gives a birthday bound of ~2⁶⁴ per address. A
collision cannot cause acceptance of an invalid chunk — at worst it causes a
divergent permutation to be treated as already-held and not synced, an
availability edge case with a vanishingly small probability, not a safety issue.
The 16-byte width was chosen to halve the identifier overhead relative to a full
32-byte digest while keeping collisions negligible.

**Why precompute the checksum at write time.** Offers are built from index
metadata without loading chunk data. The SOC checksum needs the wrapped CAC
address, which is not in the reserve index today. Persisting `Sum` in the index
at `Put` time keeps offer construction allocation-free and pays the single
hashing cost once per chunk stored, rather than once per offer served.

**Cost.** One Keccak operation per chunk at write time, using the optimised
official Go hasher: negligible latency, no additional allocations.

## Backwards Compatibility

This is a breaking change to the `pullsync` `Chunk` message and is therefore not
wire-compatible with the current protocol. Consequences and handling:

- **Protocol versioning.** The `pullsync` protocol version is bumped. A node
  only speaks the new `Chunk` format with peers that negotiate the new version;
  version negotiation prevents a new node from misparsing an old `Chunk` (which
  carried `BatchID`/`StampHash`) as the new one, and vice versa.
- **Mixed networks.** During rollout, nodes on the old version and nodes on the
  new version cannot pullsync with each other. Syncing degrades gracefully to
  same-version peers until the network has upgraded. No data migration of stored
  chunks is required, but the reserve index must begin persisting `Sum` for newly
  stored chunks; existing entries need `Sum` backfilled (computed from their
  stored batch ID, stamp hash and, for SOCs, wrapped address) so they can be
  offered under the new protocol.
- **No stamp-format change.** Postage stamps and the `Delivery` message are
  untouched, so stamp validation and chunk storage formats are unaffected.

## Test Cases

Because this SWIP changes a message format, test cases are mandatory. At minimum:

- **Checksum vectors.** Fixed `(batchID, stampHash)` → expected CAC `Sum`, and
  fixed `(batchID, stampHash, wrappedCacAddress)` → expected SOC `Sum`, including
  a pair of SOCs with identical SOC address but different wrapped CAC addresses
  demonstrating distinct sums.
- **Offer/Want/Delivery round trip.** A syncing pair where the receiver correctly
  wants only chunks whose `(address, sum)` it lacks, and correctly rejects a
  delivery whose recomputed `(address, sum)` was not offered/wanted.
- **SOC divergence.** Two nodes each holding a SOC with the same address but a
  different wrapped CAC; the divergent SOC is offered, wanted and synced.
- **Collision safety.** A delivery is only accepted when its stamp validates,
  independent of the `Sum` match.

## Implementation

Reference implementation targets the Bee client
(`github.com/ethersphere/bee`), touching:

- `pkg/pullsync/pb/pullsync.proto` — redefine `Chunk`.
- `pkg/pullsync/pullsync.go` — offer construction, offer processing
  (`Has(address, sum)`), want keying, and delivery matching (recompute `Sum`).
- `pkg/storer` and `pkg/storer/internal/reserve` — persist `Sum` in the reserve
  index at `Put`, expose a `Sum`-keyed `Has`, carry `Sum` on the bin-subscription
  result, and backfill `Sum` for existing entries.

The implementation must be completed and demonstrated on a test network before
this SWIP can move to Final.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
