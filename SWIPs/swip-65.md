---
SWIP: 65
title: Self-indexed feeds
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track (Interface)
created: 2026-08-09
requires: 60
---

<!-- The sequential construction promised by SWIP-60 ("self-indexed feeds, SWIP-65
(forthcoming)") — binding-semantics note and API frame-prefix rule both anchor here. -->

- **Business line**: live streams that persist themselves — every live message is already
  a feed update, and every update carries the complete index of its history. Late
  joiners, seekers and after-the-fact viewers need only the latest message; a missed
  message is recoverable from storage, not lost. This alone unlocks HLS-style live video
  with no manifest republication, and collaborative editing with catch-up.
- **Dev line**: no new wire frames and no proto change; implement (1) the `FEED_TOPIC`
  SOC assembly/validation rule — bare-index frames per SWIP-60's API
  ([#104](https://github.com/ethersphere/SWIPs/pull/104)), groundwork in bee
  [#5435](https://github.com/ethersphere/bee/pull/5435) — (2) publisher-side whirl-only
  pot maintenance (bee-js **(?)**), (3) subscriber-side gap detection and feed recovery;
  done per the conformance section.
- **DISC: NO** — SOCs, feeds, postage, push-sync and retrieval are all used exactly as
  they are; this is a chunk-payload convention plus BPS client behaviour over SWIP-60.
  No storage-layer change, no new protocol.

## Simple Summary

Under explicit publisher regimes the SOC id does no protocol work (SWIP-60), so this
SWIP gives it one: the publisher uses a plain sequence number, **signs each message as a
feed update** (signed id = `keccak256(topic ‖ index)`) **but carries only the bare
index** — the topic is implicit in the channel, so any receiver reconstructs the signed
id from channel topic + index. Each message is thereby simultaneously a live BPS message
and a retrievable feed update, and an index gap is detectable at the next frame. On top
of this, each update's payload is a node of a **whirl-only pot** over all previous
updates — the feed carries its own index, so the latest update alone gives ordered
playback, random access and range queries over the entire history, with zero auxiliary
chunks. Recovery of missed updates rides the same structure: the frame that reveals the
gap carries the pot that indexes everything missed, and the descent authenticates the
recovered chunks by hash against the one signature already verified.

## Motivation

SWIP-60 deliberately left the sequential construction open: under explicit publishers,
legitimacy is list membership, the id is unconstrained, and publishers MAY use sequence
numbers. This SWIP is that construction, made to settle three things at once: dedup
needs no per-binding special cases, missed live messages stop being unrecoverable, and
SWIP-61's dual-parent bandwidth cost becomes a choice instead of a necessity. The pot
layer then answers the question every streaming design on Swarm trips over: how does a
late joiner get the history without the publisher republishing an ever-growing manifest?

## Specification

Notation: `H` = keccak256, `H_BMT` = BMT hash, `‖` = concatenation. `IDX` is a uint64,
big-endian, starting at 0, incremented by 1 per update.

### The construction: signed as a feed update, carried as the bare index

Update `i` by owner `O` on topic `TOPIC` is the SOC ⟨`a`, `c`⟩:

```
id  = H(TOPIC ‖ IDX)                                  // the signed id: a feed update
a   = H(id ‖ OWNER)                                   // SOC address in storage
sig = SIG_O( H( id ‖ H_BMT(SPAN ‖ PAYLOAD) ) )
c   = IDX ‖ sig ‖ SPAN ‖ PAYLOAD                      // carried content: bare index
```

In storage this is byte-for-byte an ordinary sequential feed update — any feed client
can follow it with no knowledge of BPS. Within a cohort (p2p frames and WS bridge
frames alike) the 32-byte id field carries the 8-byte `IDX` instead: `TOPIC` is fixed
by the channel, so carrying `H(TOPIC ‖ IDX)` would transmit an opaque digest of a value
the receiver needs in the clear — the index is what makes gaps *visible*. Every
receiver reconstructs `id`, verifies `sig`, and where it stores or forwards outside the
cohort, reassembles the standard SOC.

### Validation and dedup — no special rules

A broker (and every verifying receiver) on a `FEED_TOPIC` cohort with explicit
publishers checks exactly SWIP-60's list: signature recovers an owner in the genesis
publisher list, and the chunk address `a` — computable from channel topic + carried
index + recovered owner — is not a duplicate. **Dedup is on chunk address, as for every
implicit binding, and needs nothing else**: distinct indices give distinct addresses by
construction, so the SWIP-61 dual-parent overlap, make-before-break reparenting and
history replay all dedup through the one existing rule. The broker MUST NOT enforce
index monotonicity or contiguity — frames may arrive reordered, and gap handling is the
subscriber's business (below).

The contrast case shows what the index buys. In an explicit-publisher cohort *without*
a detectable order (`ANCHOR` binding: every message at one SOC address), the guard
against unsolicited republication of old SOCs must be dedup on the **wrapped chunk
address** — and for that dedup to be sound, the application must guarantee distinct
payloads, i.e. include some index in the payload anyway. The sequence requirement does
not disappear without self-indexing; it moves above the protocol, unspecified.
Self-indexing moves it into the construction, where the same index also buys
addresses, gap detection and recovery. (The application-level payload-index
requirement is an amendment SWIP-60 owes; see Backwards compatibility.)

Two valid SOCs sharing an index but not a payload are an **equivocation**: both pass
dedup (distinct addresses), and the pair is self-evidencing publisher misbehaviour —
two signatures by one owner over one id. What to do about it is the application's
decision; detecting and signalling it is the protocol's. Detection is an **anchor
check**: the receiver validates that the SOC at its last known index wraps the very
pot node it holds from the chain (see below) — one comparison that implicitly
validates the integrity of the entire pot since the node joined. On mismatch the
receiver MUST surface a protocol error to the application. The anchor check is not a
history audit: recovery by pot descent does not retrieve the missed SOCs, so a fork at
those indices — a divergent signed history — surfaces only if the application
retrieves and compares them; how much of that to pay is its integrity/latency trade.

### The payload is the index: whirl-only pot

Let `e_0, e_1, …` be the content of the updates — for streaming, each `e_i` a CAC
(a media segment, a document delta) — and let

```
KEY : e ↦ uint64 (big-endian)
```

be a key projection that is **strictly monotone over the sequence**: `KEY(e_i) <
KEY(e_j)` for `i < j`. The default is a **timestamp** (media presentation time, wall
clock — whatever the domain orders by). Access by sequence index needs no pot key:
the SOC addresses are already a secondary index by update index — index `i` resolves
the SOC, which wraps `n_i`, which pins `e_i`, all in O(1) — so an `IDX`-keyed pot
would duplicate what the feed provides; the timestamp key is what buys seeking by
time.

The `PAYLOAD` of update `i` is the canonical serialization of `n_i`, the top node of
the **whirl-only pot** (proximity order trie maintained exclusively by whirls, per
[Trón & Verbin](https://github.com/ethersphere/SWIPs) **(?)** — reference to be pinned)
over `{e_0, …, e_i}` keyed by `KEY`:

- `n_i` **pins** the newest element: ⟨`KEY(e_i)`, `ref(e_i)`⟩;
- its **forks** are Swarm references to earlier nodes `n_j`, `j < i`.

Three properties of pots carry the whole design:

1. **One new node per insert.** A whirl-only insertion creates exactly one new node —
   `n_i` itself. So the index has **no chunks of its own**: every node of the pot over
   `{e_0, …, e_i}` is the wrapped payload of some earlier update. Publishing update `i`
   publishes the message *and* the index delta in the same chunk.
2. **Iteration is history.** XOR distance from key 0 is the key's numeric value, so
   ascending iteration from 0 enumerates the elements in `KEY` order — which by
   monotonicity is publication order: `Iter(n_i, 0, ASC) = e_0, …, e_i`, retrieving
   every node exactly once. Descending iteration from key `2^64 − 1` yields
   newest-first: the live window is its first `k` elements.
3. **Random access.** Lookup of any key (a seek to a timestamp) is a descent from the
   latest node: `O(log n)` chunk retrievals **(?)**.

The sequence of updates and the index they weave (indices 0–4, `KEY = IDX`, 3-bit keys
for legibility; every arrow is a fork — a Swarm reference to the wrapped chunk of an
earlier update):

```mermaid
flowchart RL
    subgraph u4 ["SOC idx=4"]
        n4["n4: pin e4 (key 100)"]
    end
    subgraph u3 ["SOC idx=3"]
        n3["n3: pin e3 (key 011)"]
    end
    subgraph u2 ["SOC idx=2"]
        n2["n2: pin e2 (key 010)"]
    end
    subgraph u1 ["SOC idx=1"]
        n1["n1: pin e1 (key 001)"]
    end
    subgraph u0 ["SOC idx=0"]
        n0["n0: pin e0 (key 000)"]
    end
    n4 -- "PO 0" --> n3
    n3 -- "PO 1" --> n1
    n3 -- "PO 2" --> n2
    n1 -- "PO 2" --> n0
```

A fork reference names the earlier update's **wrapped CAC**, not its SOC address:
integrity by content hash at every hop, generic pot tooling works unmodified, and it is
what makes recovery implicitly authenticated (below) — one verified signature at the
root covers every chunk the descent reaches. The alternative — referencing update `j`'s
(computable) SOC address — would put a signature check on every descent hop, tie the
pot format to feeds, and duplicate an index that already exists: the SOC addresses
*are* the by-index access path, O(1) per index; rejected.

The pot layer is a **profile**: a cohort whose payloads need no history (pure signal)
MAY run the bare construction alone — it keeps gap detection, and recovers by
retrieving every missed index as a feed update.

### Gap detection and recovery

A subscriber tracks the highest contiguous index `w` it has verified. A frame with
`IDX > w + 1` is evidence of `IDX − w − 1` missed updates — and, with the pot profile,
that same frame carries the means of recovery: its payload `n_IDX` is the pot over
*all* elements so far, the missed ones included. The subscriber descends from `n_IDX`
and retrieves the missing elements directly. Two properties make this the primary
recovery path:

- **the gap-revealing frame is the recovery index** — no id reconstruction, no feed
  lookup; the fork references in a payload already in hand name everything missed;
- **implicit authentication** — fork references are content addresses, so every
  recovered chunk verifies by hash against a reference chain rooted in `n_IDX`, whose
  signature was already checked on the live frame. One signature covers the whole
  recovery; the missed updates need no individual signature verification, because they
  are implicitly signed via the pot node that references them.

Index association needs no extra data, whatever the key: a sequential feed index
advances by exactly 1, and iteration enumerates elements in publication order, so the
traversal assigns indices by **counting from a known anchor** — the `IDX` explicit in
the frame whose payload roots the descent, or, for a plain-feed client, the index of
the latest update it just constructed and looked up.

Recovered elements MUST be indistinguishable to the dApp from live-delivered ones
(same session, same serialization, delivered in index order). Recovery is silent
self-healing, not an error path — and it doubles as **withholding evidence**: a parent
whose stream shows gaps its recovered chunks prove existed is caught without a second
feed to compare against.

Without the pot profile, recovery falls back to feed retrieval: missed update `j` is
individually addressable at `H( H(TOPIC ‖ j) ‖ OWNER )` and verified as an ordinary
feed update — one retrieval *and one signature check* per missed update. This is also
the path for clients that are not on BPS at all and follow the stream as a plain feed.

### Persistence: what recovery presupposes

Recoverability presupposes the updates reach storage. When persistence is on, the
publisher's node uploads each update under a valid postage stamp, push-synced as usual.
The **wrapped node chunk is the essential upload**: it is what pot descent — recovery,
history, seeking — resolves against (the storage-side counterpart of
`swarm-cache-wrapped-chunk` **(?)**). The SOC upload serves the feed identity: it makes
the stream followable as a plain sequential feed by clients with no BPS session, and
carries the no-pot fallback recovery. A cohort without persistence still gets gap
*detection* and dedup for free; it forgoes recovery and history, and SWIP-61's masking
is then the only gap protection — the trade below.

### Consequences for SWIP-61: masking becomes a choice

SWIP-61 buys gap-freedom structurally: every node keeps two live parents, 2× bandwidth
at every level, single failures masked with no gap. Self-indexing changes what a gap
*is* — detectable at the next frame, repairable from storage — so a delivery gap
degrades from a contract violation to recovery latency, and the dual-parent cost stops
being mandatory:

1. For self-indexed cohorts, the SWIP-60 contract ("messages arrive at all
   subscribers") is satisfied by **deliver-or-recover**; dual parenting is no longer
   the only conformant means. SWIP-61's conformance items 5–6 are accordingly relaxed
   for such cohorts: a second parent is **not required** — for a subscriber content
   with recovery latency it is pure extra cost.
2. The trade is real and stated: masking pays 2× continuously and closes the gap
   entirely; recovery pays nothing until a fault, then pays storage round-trip latency.
   Collaborative editing barely notices recovery latency; the live edge of a video
   stream might — a viewer at `latest` cannot wait out push-sync plus retrieval.
3. The choice is **per-subscriber, and needs no protocol change**: SWIP-61 trees
   already seat single-parented nodes (SWIP-60 leaves), and a single-parented relay
   endangers only itself — its children hold their own second parents. A node-level
   choice is coherent precisely because dual parenting is the costlier-but-*faster*
   alternative: what 2× buys over recovery is latency, and latency tolerance is local
   — the live-edge viewer and the archiver sit in the same cohort with different
   needs. `CohortSpec` stays untouched; no resilience flag.

### API

SWIP-60's bridge already carries this SWIP's frame rule: for feed bindings the inbound
and outbound frame prefix is the bare index, signed id `keccak256(topic ‖ index)`.
Amendments **(?)**:

- `swarm-soc-fields` gains an `index` field — the bare uint64, so a dApp on a
  self-indexed stream reads its position without recomputing ids;
- a postage batch supplied on the WS session (`swarm-postage-batch-id`) switches
  persistence on: the node uploads each published update (SOC + wrapped chunk) as it
  publishes; absence means live-only;
- recovered updates are injected into the session in index order; the bridge delivers
  frames as they arrive and back-fills, it does not reorder the live stream **(?)**.

### Worked example: HLS-style live video

`e_i` = the i-th media segment (CMAF fragment, 2–6 s); `KEY` = presentation timestamp
in ms — the default key. **The pot is the manifest**:

- **live** — subscribe via BPS: each frame's payload pins the newest segment; the
  player's live window is the first `k` elements of descending iteration;
- **seek** — to timestamp `t`: XOR-nearest descent from any recent node, `O(log n)`
  retrievals;
- **join late / VOD** — the latest update alone is the complete recording:
  `Iter(n_latest, 0, ASC)` plays start to finish; when the stream ends, the final feed
  update is the permanent artifact;
- **missed segment** — an index gap; the next frame's manifest already references it,
  so it is fetched by descent (hash-verified, no signature check) while playback
  continues from buffer.

Contrast the status quo: HLS on Swarm republishes a growing playlist on every segment —
`O(n)` bytes a time, `O(n²)` cumulative — and players poll it. Here the manifest delta
rides inside the segment's own update, history included, nothing republished, nothing
polled.

## Rationale

**Why carry the index instead of the id?** The id is a hash of the index; within the
channel the topic half of its preimage is known to every party. Carrying the digest
hides the one number that makes sequence position, gaps and recovery addresses
computable — and buys nothing, since the id is reconstructible either way. The bare
index is the same information, usable.

**Why is this the dedup story?** (nugaon's first argument.) Sequential indices make the
address-dedup rule that implicit bindings already use sufficient for feeds too: no
per-binding special cases, no highwater marks in brokers, no ordering assumptions in
the forwarding plane. The forwarding plane stays dumb; sequence is meaning the edges
attach.

**Why challenge double parenting?** (nugaon's second argument.) SWIP-61's 2× is the
price of masking *undetectable* loss. Self-indexing makes loss detectable and
repairable, so paying 2× at every tree level forever is no longer the only way to keep
the contract — it is a latency product some cohorts (live video) may still buy, and
others (collaborative editing) should not have imposed on them.

**Why recoverable rather than resent?** (nugaon's third argument.) The publisher
already persisted the update — recovery is a storage read, needs no publisher
cooperation after the fact, no broker buffering, no retransmission protocol, and works
for a subscriber that was offline for the whole outage, not just a blip. And with the
pot profile it is a *cheap* read: the gap-revealing frame hands over the index to
everything missed, and one already-verified signature authenticates the entire descent
— recovery costs hash checks, not signature checks.

**Why a whirl-only pot rather than a linked list or a republished manifest?** A
back-pointer list gives ordered history at `O(n)` traversal and no random access; a
republished manifest gives random access at `O(n)` republication per update. The
whirl-only pot gives both at one chunk per update — the theoretical floor, since the
update itself is already a chunk — because whirl insertion creates exactly one node and
that node is the update. Monotone keys make XOR-from-zero iteration coincide with
publication order, so no separate ordering structure exists either.

## Out of scope (deliberately)

Dynamic publisher lists (out of scope since SWIP-60); history *delivery* over BPS
streams (bps-history — though this SWIP's pot descent is the obvious mechanism for it
**(?)**); equivocation *response* policy (detection and error signalling are normative
above); multi-publisher cohorts need nothing here — one self-indexed feed has one
owner, so a multi-publisher cohort is simply one feed per publisher; encryption of
payloads and segments (orthogonal).

## Conformance (definition of done)

An implementation is conformant when:

1. a publisher node assembles the SOC from a bare-index frame (reconstruct id, sign
   client-side per SWIP-60's key-holding rule), and every verifying receiver validates
   it with SWIP-60's checks alone — dedup on chunk address, no index monotonicity or
   contiguity enforcement anywhere in the forwarding plane;
2. in storage, an update is an ordinary sequential feed update: an unmodified feed
   client follows the stream with no BPS knowledge;
3. with the pot profile on, publishing update `i` creates exactly one new chunk, whose
   payload is the whirl-only pot node over all elements so far; ascending iteration
   from the latest update enumerates the full history in publication order retrieving
   each node exactly once, and key lookup costs `O(log n)` retrievals;
4. a subscriber detects any index gap at the next verified frame and (persistence on)
   recovers every missed element by pot descent from that frame's payload, verifying
   recovered chunks by hash only — no per-update signature checks; without the pot
   profile, by feed retrieval per missed index; recovered updates are indistinguishable
   from live ones at the dApp boundary;
5. a receiver performs the anchor check — the SOC at its last known index wraps the
   pot node it holds — and surfaces a protocol error to the application on mismatch
   (equivocation detected);
6. with persistence on, both the feed lookup (SOC address) and the index descent
   (wrapped chunk address) of every update resolve from the network;
7. an unmodified SWIP-60 `FEED_TOPIC` cohort interoperates: frames are byte-identical,
   and a SWIP-61 subscriber on a self-indexed cohort MAY hold one parent without
   breaking any tree invariant.

## Backwards compatibility

No new frames, no proto change, no version bump: this SWIP realises semantics SWIP-60
reserved for it (id unconstrained under explicit regimes; bare-index frame prefix for
feed bindings). Storage-side artifacts are ordinary feeds — legacy feed clients
interoperate by construction. Both parent SWIPs receive follow-up amendments once this
SWIP settles: SWIP-61's dual-parent requirement (conformance items 5–6) is relaxed to
not-required for self-indexed cohorts — trees mixing single- and dual-parented
subscribers were already well-formed — and SWIP-60's `ANCHOR`-binding dedup note gains
the application-level requirement that payloads carry an index, without which
wrapped-address dedup is unsound.

## References

[SWIP-60](https://github.com/ethersphere/SWIPs/pull/104) (requires) ·
[SWIP-61](https://github.com/ethersphere/SWIPs/pull/105) (consequences) · pots:
Trón & Verbin, *Proximity Order Tries* (2026) **(?)** — pin a public link · origin:
[PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" · implementation:
bee [#5435](https://github.com/ethersphere/bee/pull/5435),
[#5486](https://github.com/ethersphere/bee/pull/5486),
[#5497](https://github.com/ethersphere/bee/pull/5497), bee-js
[#1151](https://github.com/ethersphere/bee-js/pull/1151)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
