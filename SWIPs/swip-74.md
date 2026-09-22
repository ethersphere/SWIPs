---
SWIP: 74
title: BPS-lite — single-publisher live stream over a feed, one broker, one hop
author: Elad Nachmias (@acud), Viktor Trón (@zelig)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-09-14
---

<!-- Base SWIP of the Broadcast Pub/Sub (BPS) family. Rewritten from the first draft in
PR #111 after review: no history, no bandwidth incentive, no service messages, singlehop
only, one mode only — an explicit single publisher (live video streaming). SWIP-60
(PR #104) is the full singlehop protocol and is to be amended to extend this wire rather
than the other way round; see "Relation to SWIP-60". Open points are marked (?). -->

- **Business line**: a live stream on Swarm — one author, an audience, real time, no
  storage round trip and no polling: video/audio streaming, a price ticker, a game's
  server-authoritative state, a log tail. The stream is a feed, so the same updates can
  later be persisted and replayed from storage by anyone who missed the live run.
- **Dev line**: implement one libp2p protocol, `pubsub/1.0.0`, with the three frames
  below — one broker, direct streams, one authenticated publisher, read-only
  subscribers — and nothing else: **no history, no bandwidth incentive, no service
  messages, no Bee API, one hop, one mode.** Done when a broker, a publisher and
  subscribers from independent implementations interoperate per the conformance
  section. Everything the family adds — service messages and the Bee API, multiple
  publishers, self-indexed feeds, multihop — extends this wire without changing it.
- **DISC change**: NO. A new p2p protocol surface; no storage, retrieval or incentive
  change.

## Simple Summary

BPS-lite is a real-time broadcast protocol: a kind of push notification on a *channel*
that anyone can subscribe to and one participant can publish on. Each channel defines
its own cohort — a set of nodes connected through a unique central broadcaster node, the
**broker**; every node in the cohort is directly connected to the broker, hence
*singlehop*. A channel is identified by its spec — a feed topic and the address of its
**admin**. Anyone joins by sending that spec; the admin also sends a signature that binds
its identity to the stream, and has the exclusive right to publish. Its messages are
single-owner chunks that are the higher-index updates of the feed the topic names,
carried with their bare index; the broker accepts each one iff its index exceeds the
channel's cursor, it validates as a single-owner chunk under the feed's id and its owner
is the admin, and delivers it unchanged to every subscriber stream — never to a
publisher's. All other joiners are subscribers and verify the same way, end to end: the
broker can withhold, never forge. A channel ends when it goes idle.

## Motivation

SWIP-60 spans several cohort configurations, five topic bindings, a roster control plane
on a service feed, a history flag and the Bee API. That is the right target for the
reference implementation and too much for a second, independent one whose application
is one author broadcasting to an audience. BPS-lite names that one configuration and
specifies only what it needs, so that a second team can implement and conformance-test
it from three frames — and so that it stays the **base** of the family: nothing here is
a divergence to reconcile later, because the fuller protocol extends these frames.

One publisher over a feed also removes what the fuller protocol has to carry: a dedup
window (the feed cursor replaces it), a roster and the service feed that carries it (there
is nothing to announce), a publisher regime (there is one publisher), and any question of
who may write (the admin, proved by its signature on every message).

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, RECOMMENDED and MAY are to be interpreted
as described in RFC 2119. Terms — cohort (a channel's set of nodes), broker, admin, subscriber — are SWIP-60's.

### The contract

Per cohort: messages come from **the admin, and the admin only**; they arrive at **all
subscribers**; they are **feed updates, in increasing index order**.

### Topology and roles

- **Broker**: one full node per cohort. Every peer holds one direct libp2p stream per
  (peer, cohort) to it, protocol id `pubsub/1.0.0`. Depth is 1 by construction: no
  relaying, no referral. Broker discovery is out of scope; deployments configure the
  broker.
- **Admin = the publisher**: the address named in the cohort spec. It is the only
  identity whose messages are accepted. It need not be first to join, and the cohort
  does not end when its stream goes away.
- **Subscriber**: joins by naming the cohort, receives, never sends. A message from a
  subscriber stream is a protocol violation.
- **Publisher and broker are distinct nodes**; brokering for oneself is out of scope.

### The cohort spec

Three fields, no others:

| field | value |
|---|---|
| `topic` | 32 bytes: the feed topic |
| `binding` | `FEED_TOPIC`: the signed id of every message is `keccak256(topic ‖ index)` |
| `admin` | 20-byte address: the publisher |

**The spec is the cohort's identity.** Two peers naming byte-identical specs at a broker
are in the same cohort; a spec that differs in any field names a different one. The
invite for a stream is therefore the spec plus the broker: `topic`, `admin`, broker
address. No publisher regime, no roster, no spectator flag, no history flag, no
proximity constant: a BPS-lite broker answers any spec outside this table, and any
reserved field set, with `REJECTED`. Capacity is not in the spec: a cohort cannot
dictate a remote node's connection count.

### Wire format

Normative and complete. Field and enum numbers are SWIP-60's where a counterpart exists,
so that the fuller protocol extends these messages without renumbering; numbers it uses
and this SWIP does not are reserved, never reused. An unset enum (`*_UNSPECIFIED`, the
proto3 zero) is not a legitimate wire value: receivers MUST reject a message carrying one.

```proto
syntax = "proto3";
package bps;

// What the topic binds to. One binding.
enum TopicBinding {
  TOPIC_BINDING_UNSPECIFIED = 0; // invalid on the wire
  FEED_TOPIC                = 4; // signed id = keccak256(topic || index). SWIP-60's
                                 // number; 1, 2, 3, 5 are SWIP-60's other bindings
}

// The cohort's identity. Fixed by whoever joins first; immutable.
message CohortSpec {
  bytes        topic   = 1; // 32 bytes
  TopicBinding binding = 2; // FEED_TOPIC
  bytes        admin   = 5; // 20 bytes, required
  reserved 3, 4, 6, 7, 8, 9; // SWIP-60: publishers, history, (unused), (unused),
                             // (unused), spectators — none apply here
}

// Proof of an identity, bound to the stream it arrives on:
//   owner = ecrecover( keccak256("bps-join:v1" || topic || admin), signature )
// The preimage is static and carries no node identity (SWIP-60): the same key works
// from any node, and a join never links an address to a peer id. It is therefore
// replayable, and a replayed identity is worthless: authorship rests on the message
// signature, never on the handshake.
message Auth {
  bytes signature = 1; // 65 bytes
  reserved 2;          // SWIP-60: id, for bindings that do not fix it
}

// Peer -> broker: the first and only handshake frame on a fresh stream. Creates the
// cohort if no live cohort has this spec, attaches to it otherwise. `auth` binds an
// identity to THIS stream; absent, the stream has none and is read-only.
message Join {
  CohortSpec cohort = 1;
  Auth       auth   = 2;
}

enum Status {
  STATUS_UNSPECIFIED = 0; // invalid on the wire
  OK                 = 1;
  FULL               = 2; // a capacity bound (see Resource bounds)
  REJECTED           = 4; // spec outside this SWIP, or a reserved field set
  reserved 3;             // SWIP-60: UNKNOWN_TOPIC — cannot occur: Join creates
}

// Broker -> peer, answering Join. Status only. A non-OK Ack ends the stream.
message Ack {
  Status status = 1;
  reserved 2, 3, 4, 5;    // SWIP-60: spec echo and service SOCs — nothing to echo
}

// Both directions after the handshake: admin -> broker is a publication, broker ->
// subscriber a delivery of the same bytes. The single-owner chunk travels as its
// stored chunk data, opaque to the protocol and validated by the ordinary SOC code
// once the `id` slot has been rewritten as the Frames section says:
//   id (32) || signature (65) || span (8, LE) || payload (<= 4096)
message Message {
  bytes soc = 1;
}
```

Three frames — `Join`, `Ack`, `Message` — and the two types they carry, `CohortSpec` and
`Auth`. There is no envelope around `Join` — it is the only first frame there is — and no
separate publish and broadcast types: a broker pushes to subscribers, a non-broker does
not. Fields this SWIP does not define are ignored on receipt, as proto3 does; a `Message`
whose `soc` is empty is invalid.

### Handshake: `Join`

Every peer sends `Join` as the first frame on a fresh stream, carrying the full
`CohortSpec` and, if it claims an identity, an `Auth`.

The broker compares the spec against its live cohorts: **no match → the cohort is
created** with the joiner attached; **match → the joiner is attached** to it. Anyone may
create, including a subscriber arriving before the admin: a publisher-less cohort costs
the broker one map entry until the inactivity deadline reclaims it, and can accept no
message. There is nothing to pre-register and no "unknown topic".

Then the stream's role, from `Auth`:

| `Auth` | the stream is |
|---|---|
| absent | a **subscriber stream**, no identity |
| recovers to `spec.admin` | a **publisher stream** |
| recovers to any other address | a **subscriber stream** carrying that identity — no effect in this SWIP |

**The identity is bound to the stream, not to the peer connection.** One stream per
(peer, cohort); a node may present different identities on different streams, and a
stream without `Auth` has none. **(?)** What if a second stream authenticates as the
admin while a first one is live — the admin from two nodes, or reconnecting before its
old stream is torn down? This draft admits both as publisher streams and lets the
per-cohort cursor arbitrate (neither can publish an index the other already has); the
alternatives are that the new stream supersedes the old (reset), or that the second is
`REJECTED`.

The broker answers `Ack{status}`: `OK`, `FULL` at a capacity bound, `REJECTED` for a spec
outside this SWIP or a reserved field set. A non-`OK` `Ack` ends the stream; on `OK` the
stream is retained. A peer whose stream was refused or reset MUST back off before
rejoining (randomised exponential, 1 s to 30 s, full jitter); a broker MAY reset a stream
that retries faster. Without this every reclaim or reset of a cohort brings its whole
audience back at once.

### Frames

After the handshake there is one frame, `Message`, and it is direction-typed: on a
publisher stream towards the broker it is a publication; from the broker on a subscriber
stream it is a delivery. A delivery is the accepted publication's bytes, unchanged.

**The `id` field carries the bare index.** A feed update's signed id is
`keccak256(topic ‖ index)`, `index` a uint64 big-endian in 8 bytes. On the wire the
32-byte `id` slot of the chunk data holds that index left-padded with 24 zero bytes, and
the receiver reconstructs the signed id from the cohort's topic (the carriage of
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)). A `Message` whose `id` slot
does not have 24 leading zero bytes is not a feed update: a broker drops it as invalid; a
subscriber drops it without counting it as a violation.

### Validation: the feed cursor

The broker keeps one **cursor** per cohort — the highest index accepted so far, initially
none. A `Message` arriving at the broker is accepted iff, in order:

1. it arrived on a **publisher stream** — on any other stream it is a protocol
   violation: the frame is dropped, the stream reset and the peer blocklisted per the
   node's policy;
2. its `id` slot is a bare index `n` and **`n > cursor`**;
3. with the id substituted by `keccak256(topic ‖ n)` the chunk **validates as a
   single-owner chunk**: the wrapped chunk's BMT address matches `span ‖ payload`, and
   the signature over `id ‖ wrappedAddress` recovers an owner;
4. the recovered owner is **`spec.admin`**.

On acceptance the broker sets `cursor := n` and enqueues the frame on **every subscriber
stream** in the cohort. Publisher streams receive nothing: a publisher never gets its own
messages back, on whichever of its streams they were sent.

Failures of 3 and 4 are invalid frames: dropped and counted; repeated invalid frames end
the connection (blocklisting policy). A frame failing 2 with `n ≤ cursor` is the one
benign failure — a retransmit, which an admin reconnecting after a reset legitimately
sends when it does not know what the broker last accepted — and is counted separately; a
broker MAY reset a publisher stream whose retransmit rate exceeds its policy, since the
cursor check is cheap and precedes the signature check. A frame failing 2 because the
`id` slot is not a bare index is invalid.

The cursor is initially **absent, not zero**: index 0 is the first update of every feed
and MUST be accepted on a fresh cohort.

**There is no dedup window.** The cursor is total: a message is either beyond the last
accepted index or it is not, and there is no eviction and no replay hole. **Gaps are
allowed** at the broker (`n > cursor + 1`): they are the publisher's business, and
SWIP-65 makes them detectable and recoverable at the subscriber. This is stricter than
SWIP-65's general carriage rule, under which a broker does not enforce monotonicity; the
restriction is sound here because one publisher on one hop admits no legitimate
reordering.

Subscribers re-verify every delivery exactly as the broker does (steps 2–4, against the
spec they joined with and their own cursor), end to end, whatever the broker did.

### Lifetime: inactivity

**A cohort ends by inactivity, and by nothing else.** A cohort on which no publisher
stream has had a message accepted for the **inactivity deadline** is reclaimed: the
broker resets every stream in it and forgets it. There is no end-of-stream signal in
BPS-lite — that is a service message, and this SWIP has none; an application that needs
"over" to be distinguishable from "paused" sends it in its last update, or waits for the
service feed the family adds.

A publisher stream going away — closed or reset — is therefore not an end: the cohort
and its cursor persist, subscribers stay attached, and the admin rejoins with `Auth` and
resumes at `n > cursor`. Likewise a subscriber-only cohort waits for its admin until the
deadline reclaims it. A cohort with **no attached streams** MAY be reclaimed at once —
nothing observes the difference beyond a fresh cursor on the next `Join`.

After a cohort is forgotten a later `Join` creates a fresh one with an empty cursor.
Subscribers keep their own cursor across that, so a stale republication is caught at the
edge, not at the broker.

### Resource bounds

All broker policy, none on the wire. The first four bounds are REQUIRED, with the values
given RECOMMENDED where a value is given; the last two are MAY:

| bound | answer | recommended |
|---|---|---|
| subscriber streams per cohort | `FULL` to the next `Join` without an admin `Auth` — the audience cannot lock the admin out of its own cohort | implementation-defined |
| live cohorts per broker | `FULL` to a cohort-creating `Join` | implementation-defined |
| **cohorts per peer connection** — a peer cannot flood the broker with bogus cohorts while keeping one legitimate stream open | `FULL` | 16 |
| **inactivity deadline** — reclaims a cohort, see *Lifetime* | reset | 10 min |
| outbound queue per subscriber stream, one writer; a full queue resets that stream | reset | 64 frames |
| a peer connection with no live stream | MAY be disconnected at the transport | — |
| a cohort with no attached streams | MAY be reclaimed at once | — |

Any peer can make a broker allocate a cohort simply by joining, which is why the second,
third and fourth bounds exist together: a cohort costs a map entry, a peer can hold only
a bounded number of them, and none survives idleness. The broker has no delivery
obligation: a reset for a full queue is a recoverable liveness fault, and blocking
fan-out on one slow subscriber would punish the cohort.

### Relation to SWIP-60

BPS-lite is the **base** of the BPS family and SWIP-60 is its full singlehop protocol.
The relation is subset, and it is kept in one direction only — **later revisions extend
this wire, they never change it**:

- a BPS-lite peer sends only frames the full protocol accepts, and a BPS-lite broker
  accepts only what this SWIP defines; everything the full protocol adds to the
  handshake arrives in fields this SWIP reserves, so a full-protocol `Join` at a
  BPS-lite broker is `REJECTED` at the handshake rather than silently misread, and
  everything it adds to `Message` arrives in fields this SWIP does not define and
  ignores;
- a BPS-lite publisher and subscriber at a full broker are conformant peers of a
  single-publisher live-stream cohort; the full broker's additions (service messages,
  further `Ack` fields) reach them as frames they drop and fields they ignore;
- validation here is stricter, never looser: the cursor refuses out-of-order
  retransmits a full broker may pass through; no frame a BPS-lite broker accepts is one
  a full broker refuses.

SWIP-60 is to be amended to match — its author's to-do, listed here so that the subset
claim is checkable:

- `Hello`/`Open`/`Subscribe` collapse into `Join` carrying the spec, and **cohorts are
  keyed by the whole spec, not by the topic**: a `Join` whose topic is live under a
  different spec creates a second cohort rather than being `REJECTED`, so a squatter
  who pre-creates `(topic, wrong admin)` obtains nothing;
- `GENESIS` goes (with the spec in `Join` it has nothing left to prove) and `Ack` echoes
  nothing;
- the publisher regime shrinks to a single value, `ALL` — anyone attached may publish;
  absent, the admin publishes and whoever its roster ever names, so a cohort is
  multi-publisher iff its admin publishes a roster, and nobody needs to know in advance;
- **`spectators` (field 9) goes, or reverts to a `closed` flag whose unset value means an
  open audience** — as a proto3 bool whose unset value is *false*, it reads a lite
  spec, which never sets it, as a closed cohort, and a full broker would refuse every
  lite subscriber;
- the chunk travels as opaque chunk data.

And one line in SWIP-65: its carriage rule, under which a broker does not enforce index
monotonicity, gets the exception this SWIP's cursor is.

## Rationale

**Why a feed, not an anchor.** The first draft bound the topic to a single SOC address
(`ANCHOR`), so that authorship followed from the topic and no publisher field was
needed. That collapses the wrong thing: one address for every message means messages
are told apart only by their wrapped payload, dedup needs a window, order is invisible,
and nothing connects the live stream to storage. Binding to a feed keeps the publisher
explicit — one address in the spec, one owner check per message — and buys order, gap
detection, replay-freedom and persistence for the same money: the stream *is* a feed,
live.

**Why `Join` carries the spec, and there is only `Join`.** A joiner that arrives with a
topic and learns the spec from the broker has to be told the spec by someone it then
has to verify. For a live stream the spec is a topic and an address; the invite that
names the broker names them too. Once every joiner carries the spec, the spec is the
cohort's identity, the broker is never trusted about it, `Ack` is a status, the
first-joiner-creates rule is the natural one — and a second handshake type has nothing
to do.

**Why the identity is on the stream.** `Auth` is in `Join`, and what it proves is bound
to the stream it arrives on. A peer connection is a node; a stream is a (node, cohort)
pair; the identity that matters is the key that signs the messages on that stream. Binding
it there is what lets one node carry different identities on different cohorts, and what
later lets a subscriber stream be promoted to a publisher stream in place, without a
rejoin, when the admin grants it.

**Why no loopback.** A publisher knows what it published. Echoing it costs a frame per
message on the stream whose back-pressure matters most, and buys no confirmation: a
rejected frame produces no echo either.

**Why the cursor, not a window.** A bounded seen-set is a memory bound with a replay
hole at its edge, and it exists because the general protocol admits many publishers and
duplicate paths. One publisher on one hop has neither. The feed index is a total order,
and "greater than the last" is both the dedup rule and the memory bound.

**Why inactivity, and only inactivity.** An end that is *signed* by the admin is a service
message, which this SWIP does not have; an end that is *inferred* from the admin's stream
turns every transport hiccup into a stream-ending event for the whole audience. So there
is no end: a cohort is a map entry that lives while it is used and is reclaimed when it is
not. What that gives up — "over" versus "paused" — is the application's to carry until the
service feed arrives.

## Security considerations

Those of SWIP-60, restricted to its live-stream configuration (admin set, the admin
alone publishes, open audience).

**The publisher role is proved, not asserted**: `Auth` recovers to `admin`, and it grants
nothing the admin's key has not already granted. Its preimage is static, so it is
replayable: a peer that captured the admin's `Join` can obtain a publisher stream, but
can send on it only what the admin already signed. Within one cohort's life the cursor
refuses that (every captured index is at or below it); **across a reclaim or at another
broker the cursor starts empty, and the base protocol does not distinguish a replay of
the admin's history from the admin's history**. Freshness is therefore a subscriber-side
property: a subscriber SHOULD keep its cursor per `(topic, admin)` across rejoins, and an
application that needs freshness for a first-time viewer carries it in the payload
(SWIP-65's timestamp key does). Fan-out of a replayed history is bounded by what was
captured and by the inactivity deadline.

**No confidentiality**: the broker and every subscriber see plaintext; applications
encrypt payloads. **The broker withholds, never forges**, and a withheld update is
visible as a gap in the index. **No end signal**: a broker can end a cohort for its
audience by resetting their streams, which is withholding, nothing more. **Resource
bounds are policy and the four capacity bounds are required** (above); the cursor
removes the dedup-window bound and its edge. A subscriber that publishes is a protocol
violation and is blocklisted; a squatted cohort is one map entry for one inactivity
deadline, and a peer can hold only a bounded number of them.

## Conformance (definition of done)

An implementation is BPS-lite conformant when:

1. a broker accepts a `Join` whose spec is `{topic, FEED_TOPIC, admin}` and answers any
   other binding, an absent `admin`, or any reserved field set with `REJECTED`;
2. a `Join` for a spec with no live cohort creates it, whoever sends it; a `Join` with a
   byte-identical spec attaches to it; the broker never sends status 3;
3. `Auth` is verified by recovery over `keccak256("bps-join:v1" ‖ topic ‖ admin)`; a
   stream whose `Auth` recovers to `admin` is a publisher stream; any other stream is a
   subscriber stream; the identity is a property of the stream;
4. `Ack` carries a status and nothing else; a non-`OK` `Ack` ends the stream;
5. a `Message` on a subscriber stream is dropped, the stream reset, the peer blocklisted;
6. a `Message` on a publisher stream is accepted iff its bare index exceeds the cursor,
   it validates as a single-owner chunk under `keccak256(topic ‖ index)`, and its owner
   is `admin`; accepted frames advance the cursor and are delivered unchanged to every
   subscriber stream in the cohort, and to no publisher stream;
7. `n ≤ cursor` is counted as a retransmit, not a violation, and there is no other
   dedup state; gaps are accepted; index 0 is accepted on a fresh cohort;
8. a cohort with no accepted message for the inactivity deadline is reclaimed, every
   stream in it reset; a publisher stream going away does not end the cohort;
9. the capacity bounds are enforced, `FULL` is issued at capacity and nothing else is;
10. a subscriber re-verifies every delivery against the spec it joined with and its own
    cursor;
11. a BPS-lite publisher and subscriber interoperate with a full SWIP-60 broker on a
    single-publisher cohort once SWIP-60 is amended per *Relation to SWIP-60*.

A broker MUST expose per-cohort counters for the silent outcomes — `invalid_index`,
`invalid_soc`, `wrong_owner`, `wrong_stream`, `retransmit`, `queue_reset` — since
items 6, 7 and 9 are unobservable from the wire without them.

## Out of scope (deliberately)

Service messages of any kind (roster, end of stream) and the Bee API bridge; multiple
publishers and the promotion of a subscriber stream to a publisher stream; the
self-indexed payload construction, gap recovery and persistence of
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106); multihop
([SWIP-61](https://github.com/ethersphere/SWIPs/pull/105)); history; bandwidth
incentives; broker discovery ([SWIP-59](https://github.com/ethersphere/SWIPs/pull/103));
confidentiality of any kind. Each extends this SWIP's wire without changing it.

## Backwards compatibility

New protocol; no existing behaviour changes. Every message and field number here is
kept by the fuller protocol, which extends by adding fields and messages and never by
changing these; a BPS-lite peer ignores fields it does not define.

## References

Full singlehop protocol: [SWIP-60, PR #104](https://github.com/ethersphere/SWIPs/pull/104)
· carriage: [SWIP-65 self-indexed feeds, PR #106](https://github.com/ethersphere/SWIPs/pull/106)
· first draft of this SWIP: [PR #111](https://github.com/ethersphere/SWIPs/pull/111)
· origin: [PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub"
· implementation groundwork: bee [#5435](https://github.com/ethersphere/bee/pull/5435)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
