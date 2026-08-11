---
SWIP: 66
title: Graffiti wall pattern
author: Viktor Trón (@zelig)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track (Interface)
created: 2026-08-11
---

<!-- The anti-GSOC. Replaces the shared-owner-key graffiti pattern with own-identity
writers mining into an anchor neighbourhood. Freestanding pattern; BPS (SWIP-60) enters
only as one of the write/read modes. -->

- **Business line**: a permissionless public write-board — a **wall** — named by any
  topic: anyone can write an entry under **their own signature**, everyone can read,
  and every entry has an accountable author. Headline application: **tag-based
  advertising** — announcing a videocast (`A`) on crypto-trading (`B`) on Monday the
  17th (`C`), the publisher puts an advert on the walls `H(A)`, `H(B)`, `H(C)`,
  `H(A‖B)`, `H(A‖C)`, `H(B‖C)` and `H(A‖B‖C)`, and anyone following any of those tag
  combinations discovers it.
- **Dev line**: no new wire frames and no proto change; implement (1) writer-side
  mining helpers — ephemeral-owner (MOC, SWIP-42) and span-index — in client
  libraries (bee-js or other JS libs),
  (2) the wall-entry validation rule (span-index construction) wherever SOCs are
  validated for ANCHOR-bound delivery, (3) reader plumbing over the existing
  GSOC-style subscription, `/moc/subscribe`, and BPS ANCHOR cohorts (SWIP-60,
  [#104](https://github.com/ethersphere/SWIPs/pull/104)); done per the conformance
  section.
- **DISC: NO** — standard SOC validation and the existing implicit-binding rule
  `PO(addr, anchor) >= PO_MIN = 16`; a wrapped chunk with an arbitrary span and empty
  payload is already allowed by storage, so nothing changes below the pattern.

## Simple Summary

A **graffiti wall** is the set of single-owner chunks mined into the neighbourhood of
an anchor derived from a public topic. The topic — usually a 32-byte reference, such
as a content address or a tag hash — serves both to form entry ids and to derive the
**anchor**, exactly as in the original GSOC pattern. What changes is the writer's identity: instead of every writer signing
with one shared, publicly derivable owner key, each writer signs with **their own
key** and spends mining effort to land their entry near the anchor — by mining an
ephemeral owner (the MOC pattern), or by mining the feed **index** itself, carried in
the span field of the wrapped chunk. Anyone can write; everyone can read; no two
writers ever share a key — and a BPS broker on the wall's cohort doubles as the
**aggregate feed indexer** over all writers.

## Motivation

The original GSOC pattern hands one secret key to the world, and everything wrong with
it follows from that. The arguments, enumerated:

1. In the Book of Swarm, signature attestation on a single-owner chunk is meant as an
   **integrity check**: because the secret key belongs to a *single* owner, no double
   signing on the same id is a reasonable requirement. A shared graffiti key voids the
   premise — anyone can sign anything on any id, so the attestation attests nothing
   and content at a SOC address loses its uniqueness guarantee.
2. **Pull sync.** Reconciling divergent versions at one address needs some digest on
   the chunks — which exists to sync postage stamps, but not for the content: pull
   sync assumes one content per address; GSOC breaks the assumption and forces
   content digests into the sync protocol — cf. the "chunk checksum for divergent
   sync" draft ([#101](https://github.com/ethersphere/SWIPs/pull/101)).
3. **Incentives.** The redistribution game had to mix the **wrapped address** into
   the sample to motivate storage of multiple payloads at the same address — a
   storage-incentive complication existing solely to accommodate multi-version SOCs.
4. **Stamping.** Currently the stamp for any SOC can be used as the stamp on *any
   version* of the same SOC address — unlimited versions ride a single payment.
5. **Retrieval locality.** Retrieval of a multi-version SOC is only possible from
   the closest node; caching is problematic — a cache cannot know whether its copy
   is the version wanted.
6. **Retrieval protocol.** A retrieve request has a single response; to exhaust the
   versions at an address one must resort to a wanted (matching) / not-wanted (not
   matching) request pattern — which the protocol does not offer.
7. **No censorship resistance.** The pattern does not solve the problem it is often
   assumed to: it is not censorship resistant.
8. **Collision-prone even when honest.** The genuine happy path — all writers
   well-intentioned — is already collision prone: cooperating writers race on the
   same id with no arbitration.

## Specification

Notation: `H` = keccak256, `H_BMT` = BMT hash, `‖` = concatenation, `ε` = the empty
byte string. `PO(x, y)` = proximity order; `PO_MIN = 16` (SWIP-60 protocol constant).
`SIG_O` = signature by owner key `O`; `ECRecover` recovers the signing address.

### The wall: topic and anchor

A wall is named by its **topic** `T` — usually a 32-byte reference (a content
address, or the hash of a tag or mnemonic string). Everything else is derived from
it:

```
A = H(T)               // the anchor — also the topic of the writers' content feeds
```

An entry is **on the wall** iff it is a valid SOC whose address `addr` satisfies
`PO(addr, A) >= PO_MIN`. The wall is therefore not a data structure anybody maintains
— it is a *neighbourhood*, and membership is bought with mining effort.

### Writing: three modes

A writer holding identity key `O` (or minting one) produces a wall entry in one of
three ways.

**Mode 1 — mined ephemeral owner (the MOC pattern, SWIP-42,
[#80](https://github.com/ethersphere/SWIPs/pull/80)).** The writer mines an ephemeral
keypair until the SOC address lands on the wall:

```
id   = H(T)                               // note: id = A
mine O_e  until  PO( H(id ‖ O_e), A ) >= PO_MIN
```

Content is unconstrained; the entry is a MOC and all MOC tooling applies. The
ephemeral owner is still *an* owner — unique to this writer, never shared — but the
entry is not linked to the writer's persistent identity unless the payload links it.

**Mode 2 — normal feed, bare index, brokered (no mining).** When writers connect in
publisher role to a broker (BPS, SWIP-60), a normal feed on topic `T` is used and
frames carry the **bare 8-byte index in the 32-byte id field** — the carriage rule of
SWIP-65 ([#106](https://github.com/ethersphere/SWIPs/pull/106)). Delivery is by the
broker, so no anchoring — and hence no mining — is needed. The publisher
parameterisation of the cohort is immaterial; the point is that both the topic
(implicit in the channel) and the bare indexes are known, so subscribers can follow.
Every frame carries the full SOC, so the writer's own key signs as in any feed.

**Mode 3 — normal feed, mined index (the span-index construction).** The writer keeps
their real identity `O` and mines the feed **index** so that the entry lands on the
wall. The index is a uint64 and is written into the **span field of the wrapped
chunk**; the payload is left **empty** for quick filtering. The entry is byte-for-byte
a feed update on topic `T` at index `SPAN`:

```
mine SPAN (uint64)  until  PO( addr, A ) >= PO_MIN   where

id   = H( T ‖ SPAN )
sig  = SIG_O( H( id ‖ H_BMT( SPAN ‖ ε ) ) )
addr = H( id ‖ O )
c    = id ‖ sig ‖ SPAN ‖ ε
```

Because the index sits in the span field, the entry is **self-describing**: a reader
holding only the chunk (and knowing `T`) validates it with no external information —

```
ID   = H( T ‖ SPAN )                       // recompute id from topic and span
O    = ECRecover( SIG, H( ID ‖ H_BMT(SPAN ‖ ε) ) )
addr = H( ID ‖ O )
valid  iff  PO( addr, A ) >= PO_MIN
```

The mined SPAN thus places a member of the writer's **MIC** in the proximity of the
anchor: the entry simultaneously belongs to the wall (by address) and to the writer's
own SOC universe (by owner). The mode-3 entry itself carries no message — it
*announces* a writer: the content lives on the **owner's content feed for the wall**,
whose topic is `H(T)` — one hash deeper than the wall's own id preimage, so a content
update `id = H( H(T) ‖ IDX )` can never clash with a wall entry `id = H( T ‖ SPAN )`
even when the mined SPAN happens to be a low integer. Note `H(T) = A`: the anchor
doubles as the content-feed topic. A reader recovers `O` from the entry and follows
the feed `(H(T), O)` — from index 0, or as a subscription — for the actual graffiti.
When the entry's existence is itself the message (see the worked example), no content
feed need exist.

### Reading the wall

- **Full node in the anchor neighbourhood**: wall entries arrive with the reserve;
  filtering **zero-length payloads with a conforming address** yields the mode-3
  entries directly, and the GSOC-style subscription surfaces entries as they land.
- **Light client, live**: a BPS cohort with ANCHOR binding and implicit publishers
  (SWIP-60) — the broker's implicit-publisher validation rule
  `PO(addr, anchor) >= PO_MIN` is exactly wall membership, so brokers need no new
  rules; mode-3 entries additionally validate by the span-index chain above.
- **After the fact**: BPS mediated — see the aggregation section below. Individual
  entries remain ordinary stored chunks, retrievable by address.

### Aggregation: the broker as wall indexer

The one piece that completes the pattern: a BPS broker serving the wall's cohort acts
as the **aggregate feed indexer** for the wall. The broker sees every entry as it is
published; each entry names a writer `O`, and each writer's content is a feed
`(H(T), O)`. The broker aggregates by **publishing its own feed of contributors for
the topic** — owner the broker's key, topic `H(T)`, one update per wall entry
observed **(?)** — and making it **self-indexing** per SWIP-65
([#106](https://github.com/ethersphere/SWIPs/pull/106)). A late joiner then needs
only the broker feed's latest update: the whirl-only pot in its payload indexes every
contributor in arrival order, gives O(log n) seek, and authenticates the whole
history against the broker's one signature. After-the-fact reading of a wall is thus
a single feed lookup, and trust in the broker is bounded: the broker can withhold a
contributor from its index, but cannot forge one — every indexed element is a wall
entry carrying its writer's own signature.

### Worked example: tag-based advertising

A publisher announces a videocast (`A`) on crypto-trading (`B`) on Monday the 17th
(`C`). Each tag and tag combination is a wall:

```
T ∈ { H(A), H(B), H(C), H(A‖B), H(A‖C), H(B‖C), H(A‖B‖C) }
```

For each wall the publisher writes one entry — mode 3, say: mine `SPAN` so that
`H( H(T ‖ SPAN) ‖ O )` lands within `PO_MIN` of `H(T)`. **No content feed is
needed**: this is an ad type where the entry's *existence* gives the information —
the wall names the tags, the recovered owner names the advertiser, and anything more
is discoverable through the writer's MIC and feeds. A reader interested in
crypto-trading follows the wall `H(B)`; one interested specifically in Monday's
videocasts follows `H(A‖C)`. Live discovery is the ANCHOR cohort on each wall; after
the fact, one lookup of a broker's contributor feed per wall.

### Conformance

1. A **wall entry** is valid iff it is a valid SOC and `PO(addr, A) >= PO_MIN`, with
   `A = H(T)` derived from the wall topic as specified above.
2. A **mode-3 entry** is valid iff, additionally, `id = H(T ‖ SPAN)` for the SPAN
   carried in its wrapped chunk's span field and its payload is empty.
3. Readers and brokers MUST ignore chunks in the anchor neighbourhood that fail the
   applicable validity chain; ignoring is silent.
4. A broker serving an ANCHOR-bound cohort MUST apply the implicit-publisher PO rule
   of SWIP-60 unchanged; this SWIP adds no broker-side rules.
5. Storage nodes MUST NOT reject a wrapped chunk on account of an arbitrary span
   value with an empty payload (already the case — codified here so the pattern's
   floor cannot regress).

## Copyright

Copyright and related rights waived via
[CC0](https://creativecommons.org/publicdomain/zero/1.0/).
