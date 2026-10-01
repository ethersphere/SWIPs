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
only, one mode only — an explicit single publisher (live video streaming). Rev 3: the
publisher role is claimed by signing a broker-issued challenge (the first draft had a
challenge; rev 2 wrongly replaced it with a static signature). Rev 4: the claim is carried
as a single-owner chunk (`Auth`) and verified by the ordinary SOC code; the data frame is
`Broadcast`. Rev 5: `Broadcast` carries the chunk data alone — the receiver forms the
address it validates against from the owner it already knows — and `wrong_owner` folds
into `invalid_soc`. Rev 6: the `Auth` type goes; the claim is a `Broadcast` whose chunk
payload is a service message of kind `CLAIM`, and nothing on the wire is told apart by
shape. Rev 7: the challenge is drawn at random per stream, not derived — a derived one
let whoever had captured the admin's claim replay it once the admin dropped — and it
salts the feed topic for the session, so every chunk of the session is signed under it:
the first publication is the claim, there is no claim chunk, no service message, no
credential in `Join`, and `Join` carries the spec and the peer's identity only; a
stream that says it is the admin's is admitted outside the fan-out bound, silent, until
it claims. SWIP-60 (PR #104) is the
full singlehop protocol and extends this wire without changing it; see "Relation to
SWIP-60". Open points are marked (?). -->

- **Business line**: a live stream on Swarm — one author, an audience, real time, no
  storage round trip and no polling: video/audio streaming, a price ticker, a game's
  server-authoritative state, a log tail. The stream is a feed, so the author can
  persist the same updates for anyone who missed the live run.
- **Dev line**: implement one libp2p protocol, `pubsub/1.0.0`, with the three frames
  below — one broker, direct streams, one publisher whose every message is signed under
  a challenge the broker issued for its stream, read-only subscribers — and nothing
  else: **no history, no bandwidth
  incentive, no roster or end-of-stream messages, no Bee API, one hop, one mode.** Done
  when a broker, a
  publisher and subscribers from independent implementations interoperate per the
  conformance section. Everything the family adds — the admin's service messages and the
  Bee API, multiple publishers, self-indexed feeds, multihop — extends this wire without
  changing it.
- **DISC change**: NO. A new p2p protocol surface; no storage, retrieval or incentive
  change.

## Simple Summary

BPS-lite is a real-time broadcast protocol: a kind of push notification on a *channel*
that anyone can subscribe to and one participant can publish on. Each channel defines
its own cohort — a set of nodes connected through a unique central broadcaster node, the
**broker**; every node in the cohort is directly connected to the broker, hence
*singlehop*. A channel is identified by its spec — a feed topic and the address of its
**admin**. Anyone joins by sending that spec and its own address; the broker answers
with a **challenge** drawn at random for that stream, and for the life of the stream the
channel's feed topic is salted with it: a publisher's messages are single-owner chunks
that are the higher-index updates of that session feed — the feed on
`keccak256(topic ‖ challenge)` — carried with the challenge and their bare index, and the
first of them is the publisher's claim on the stream. The
broker accepts each one iff it carries the stream's challenge, its index is at least the
channel's cursor, and the chunk validates as the admin's single-owner chunk under the
session feed's id, and delivers it unchanged to every subscriber stream — never to a
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
as described in RFC 2119. Terms — cohort (a channel's set of nodes), broker, admin,
subscriber — are SWIP-60's.

### The contract

Per cohort: messages come from **the admin, and the admin only**; they arrive at **all
subscribers**; they are **feed updates, in increasing index order**.

### Topology and roles

- **Broker**: one full node per cohort. Every peer holds one direct libp2p stream per
  (peer, cohort, identity) to it, protocol id `pubsub/1.0.0`. Depth is 1 by construction:
  no relaying, no referral. Broker discovery is out of scope; deployments configure the
  broker.
- **Admin = the publisher**: the address named in the cohort spec. It is the only
  identity whose messages are accepted. It need not be first to join; the cohort does
  not end when its stream goes away; and it may publish from any node, or from two.
- **Subscriber**: joins by naming the cohort and its own address, receives, never
  publishes. A publication from a subscriber stream is a protocol violation.
- **Publisher and broker are distinct nodes**; brokering for oneself is out of scope.

### The cohort spec

Three fields, no others:

| field | value |
|---|---|
| `topic` | 32 bytes: the feed topic |
| `binding` | `FEED_TOPIC`: the stream is a feed on the topic — on the wire, the session feed on `topic_s = keccak256(topic ‖ challenge)`, whose signed id is `keccak256(topic_s ‖ index)` |
| `admin` | 20-byte address: the publisher |

**The spec is the cohort's identity.** It has a **canonical serialisation** —
`Marshal(spec)`: fields in number order, unset fields not emitted — and cohorts are keyed
by it: two peers naming byte-identical specs at a broker are in the same cohort; a spec
that differs in any field names a different one. The invite for a stream is therefore the
spec plus the broker: `topic`, `admin`, broker address. No publisher regime, no roster, no
audience flag, no history flag, no proximity constant: a BPS-lite broker answers any
value outside this table with `REJECTED`, and ignores fields it does not define, as
proto3 does. Capacity is not in the spec: a cohort cannot dictate a remote node's
connection count.

### Wire format

Normative and complete. Field and enum numbers are shared with SWIP-60, which extends
these messages by adding fields, values and nothing else. An unset enum
(`*_UNSPECIFIED`, the proto3 zero) is not a legitimate wire value: receivers MUST reject
a message carrying one.

```proto
syntax = "proto3";
package bps;

// What the topic binds to. One binding.
enum TopicBinding {
  TOPIC_BINDING_UNSPECIFIED = 0; // invalid on the wire
  FEED_TOPIC                = 4; // the stream is a feed on the topic; on the wire the
                                 // session feed on keccak256(topic || challenge):
                                 // id = keccak256(keccak256(topic || challenge) || index)
}

// The cohort's identity. Fixed by whoever joins first; immutable; keyed by its
// canonical serialisation.
message CohortSpec {
  bytes        topic   = 1; // 32 bytes
  TopicBinding binding = 2; // FEED_TOPIC
  bytes        admin   = 3; // 20 bytes, required
}

// Peer -> broker: the first frame on a fresh stream. Creates the cohort if no live
// cohort has this spec, attaches to it otherwise. Nothing else is ever in it — no
// cursor, no credential: the stream's role follows from what it sends after the Ack.
message Join {
  CohortSpec cohort = 1;
  bytes      addr   = 2; // 20 bytes, required: the stream's identity — the address it
                         // publishes as if it publishes, which only the admin's may;
                         // a stream declaring the admin's is admitted outside the
                         // fan-out bound and receives nothing until it claims
}

enum Status {
  STATUS_UNSPECIFIED = 0; // invalid on the wire
  OK                 = 1;
  FULL               = 2; // a capacity bound (see Resource bounds)
  REJECTED           = 3; // a spec value outside this SWIP
}

// Broker -> peer, answering Join. A non-OK Ack ends the stream.
message Ack {
  Status status    = 1;
  bytes  challenge = 2; // iff OK: exactly 24 bytes drawn at random for this stream,
                        // never all zero — the salt of the session feed; held for the
                        // stream's life, never persisted, never reused
}

// Every frame after the handshake: publisher -> broker a publication, broker ->
// subscriber a delivery of the same bytes. The single-owner chunk travels as its chunk
// data, opaque to the protocol:
//   soc = id (32) || signature (65) || span (8, LE) || payload (<= 4096)
// with the id slot carrying challenge (24) || index (8, BE). The receiver reconstructs
// the signed id as keccak256(keccak256(topic || challenge) || index), forms the address
// the chunk must have — keccak256(id || admin) — and validates the chunk against it
// with the ordinary SOC code. A stream's first publication under its challenge is its
// claim: the stream is a publisher stream from the moment a frame of its own validates
// under its challenge as the admin's.
message Broadcast {
  bytes soc = 1;
}
```

Three frames — `Join`, `Ack`, `Broadcast` — and the one type they carry, `CohortSpec`.
There is no envelope: **what a frame is follows from the stream's direction and role.**
The first peer-to-broker frame is a `Join` and the first broker-to-peer frame an `Ack`;
after that every frame is a `Broadcast`: a publisher stream sends publications, the
broker sends deliveries, and a stream that has not yet published sends its claim — its
first publication under its challenge — and is a publisher stream or is reset. A frame
that is not what its stream may send is invalid.

### Handshake: `Join`, the challenge, the session feed, the claim

Every peer sends `Join` as the first frame on a fresh stream, carrying the full
`CohortSpec` and its identity, `addr`: the address the stream publishes as, if it
publishes — an assertion, proved only by the signatures that follow. Nothing else is in
it: no cursor, and no credential, because a credential that could be presented in a
`Join` could be presented by whoever captured it.

The broker compares the spec against its live cohorts: **no match → the cohort is
created** with the joiner attached; **match → the joiner is attached** to it. Anyone may
create, including a subscriber arriving before the admin: a publisher-less cohort costs
the broker one map entry until the inactivity deadline reclaims it, and can accept no
message. There is nothing to pre-register and no "unknown topic".

**The challenge.** With `Ack{OK}` the broker sends a **challenge**: 24 bytes it draws at
random for this stream, holds for the stream's life, and never persists or reuses — on
every stream, whatever its `addr`. It is not a secret: it will be in the clear in every
chunk of the session. It is a **freshness mark**: it exists on this stream only, and
nothing signed for another stream, another cohort, another broker or an earlier session
of the same peer carries it. Anyone may obtain one by joining, and gains nothing by it.
It is exactly 24 bytes and never all zero; a peer treats any other length as a protocol
error. A subscriber's challenge is unused in BPS-lite — it is issued so that the family
can upgrade the same stream later — and is never compared with anything.

**The session feed.** For the life of the stream the publisher does not write the
channel's feed but the **session's**: the feed on the channel's topic salted with the
challenge,

```
topic_s = keccak256(topic ‖ challenge)             the session topic
id      = keccak256(topic_s ‖ index)               topic 32, challenge 24, index 8 bytes
```

— an ordinary feed, addressable as `(admin, topic_s)` by ordinary feed tooling. The
chunk's 32-byte `id` slot carries `challenge ‖ index` — the challenge followed by the
index as a uint64 big-endian — so that every receiver that knows the topic, subscriber
or broker, reconstructs `topic_s` and the signed id from the slot without being told
anything else, and the broker additionally requires the slot to begin with the challenge
it issued on that stream. The salt is what makes a session chunk worthless anywhere but
on the stream it was signed for; the index in the clear is what the cursor and SWIP-65's
gap detection read. The publisher signs each update once per stream it holds, and MUST
NOT reuse an index across sessions: a subscriber cannot tell sessions apart, and its
cursor per `(topic, admin)` is what keeps an earlier session's update from standing in
for a later one (see Security considerations). The same wrapped payload signed again
under the channel's own id, `keccak256(topic ‖ index)`, is the update for storage (see
Rationale).

**The pending stream.** A `Join` that declares the admin's `addr` is admitted outside
the fan-out bound, as a **pending stream**: attached, in no fan-out set, receiving
nothing, until it claims or the **claim deadline** disconnects it (*Resource bounds*).
That is what keeps a full audience, or an old stream of the admin's that the transport
has not yet reaped, from locking the admin out, and it is worth nothing to anyone but
the admin: a pending stream costs the broker a map entry and a challenge for one
deadline and delivers nothing. Every other `Join` is a **subscriber stream**, within the
bound.

**The claim.** A pending stream claims the publisher role with its **first `Broadcast`
under its challenge** — a publication like every one that follows. A frame on it whose
slot does not begin with the stream's challenge is not of this session: it is dropped
and counted (`wrong_challenge`), not a violation — it is what an update the admin's node
signed for its previous stream and still had queued looks like, and what a
full-protocol admin's roster looks like here — and a publisher SHOULD discard or re-sign
what it had queued for a stream that was reset, since nothing signed for the old
challenge will be accepted. For a frame that does carry the challenge the broker checks
that with `id = keccak256(topic_s ‖ index)` the chunk validates as the admin's
single-owner chunk at `keccak256(id ‖ admin)`: signature, digest and signer in one
existing call, the owner forced rather than recovered, since recovering a signer always
yields *some* address. If it does, the stream **upgrades** to a **publisher stream** and
the frame is delivered, or counted as a retransmit, exactly as any publication
(*Validation* below). A signature under this challenge is possible only for the key of
`addr` and only after the `Ack`, so the first valid publication proves the key and the
session at once, and nothing else has to. There is **no reply**: the publisher sends its
first publication and the next back to back, and learns the outcome from whether the
stream survives. If it does not validate, it is a protocol violation: dropped, counted
(`wrong_stream`), the stream reset, the peer blocklisted per the node's policy — a chunk
under this challenge from a key that is not the admin's is nothing a conforming peer
sends; and so is any frame at all from a subscriber stream, whatever its slot. Several
streams MAY be claimed for the admin at once — the admin from two nodes, or
reconnecting before its old stream is torn down: each has its own challenge, and the
cursor arbitrates.

**The rest of the handshake.** `FULL` answers a `Join` at a
capacity bound, `REJECTED` one whose spec has a value outside this SWIP. A non-`OK` `Ack`
ends the stream; on `OK` it is retained. A peer whose stream was refused or reset MUST
back off before rejoining (randomised exponential, 1 s to 30 s, full jitter); a broker
MAY reset a stream that retries faster. Without this every reclaim or reset of a cohort
brings its whole audience back at once.

### Frames

After the handshake every frame is a `Broadcast`: a broker sends deliveries, to
subscriber streams; a publisher stream sends publications; a pending stream sends its
claim. A delivery is the accepted publication's bytes, unchanged.

**The frame carries no address.** Recovering a signer always yields *an* address, so the
ordinary SOC validation needs an address to hold the chunk against — and every receiver
has one: in BPS-lite the publisher is the admin, so the expected address of an update is
`keccak256(keccak256(topic_s ‖ index) ‖ admin)`, and validating the chunk against it checks
signature, digest and owner in one call, with the owner forced rather than compared
afterwards. Carrying the address would say nothing the receiver does not already know.

**The `id` slot carries the challenge and the bare index.** A publication's signed id is
`keccak256(topic_s ‖ index)`, `topic_s = keccak256(topic ‖ challenge)`, `index` a uint64
big-endian in 8 bytes. On the wire the 32-byte `id` slot of `soc` holds
`challenge ‖ index`, and the receiver reconstructs the session topic and the signed id
from the cohort's topic and the slot. This is the carriage of
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106), salted: under SWIP-65 the slot
holds the index left-padded with 24 zero bytes and the receiver prepends the topic —
that is the channel's own feed; here the 24 bytes are the challenge — that is the
session's. A slot beginning with 24 zero bytes therefore names the channel's own feed:
a broker never issues an all-zero challenge, never accepts such a frame on any stream,
and never sends one in BPS-lite — stored updates reach a subscriber through the
family's history delivery (SWIP-60), verified under the channel's own id. On a publisher
or pending stream, a `Broadcast` whose `id` slot does not begin with the stream's
challenge is not a chunk of this session: it is dropped and counted (`wrong_challenge`),
but it is not a violation — it is what an update the admin signed for an earlier session
and resent after reconnecting looks like, and what a full-protocol admin's service
message looks like at a BPS-lite broker. A subscriber does not check the salt — that was
the broker's check, and a subscriber does not know which stream a delivery came from —
and reads the index from the slot.

### Validation: the feed cursor

The broker keeps one **cursor** per cohort: **the lowest index it will accept next**,
initially 0 — index 0 is the first update of every feed. A `Broadcast` arriving at the
broker is accepted iff, in order:

1. it arrived on a **publisher stream** — or on a **pending stream**, as its claim: a
   frame there that passes 2 and 4 upgrades the stream, one that fails 2 is dropped and
   counted (`wrong_challenge`), one that passes 2 and fails 4 is a protocol violation:
   dropped, counted (`wrong_stream`), the stream reset, the peer blocklisted per the
   node's policy — as is any frame from a subscriber stream;
2. its `id` slot begins with **the stream's challenge**;
3. the index `n` in the slot's last 8 bytes is **`n ≥ cursor`**;
4. with `id = keccak256(topic_s ‖ n)`, `topic_s = keccak256(topic ‖ challenge)`, the chunk
   **validates as the admin's single-owner chunk**: the receiver forms the expected
   address `keccak256(id ‖ admin)` and runs the ordinary SOC validation against it — the
   wrapped chunk's BMT address matches `span ‖ payload`, and the signature over
   `id ‖ wrappedAddress` recovers an owner that hashes with the id to that address,
   which only the admin's does.

On acceptance the broker sets `cursor := n + 1` and enqueues the frame on **every
subscriber stream** in the cohort. Publisher streams receive nothing: a publisher never
gets its own messages back, on whichever of its streams they were sent.

A failure of 4 is an invalid frame: dropped and counted (`invalid_soc`); repeated invalid
frames end the connection (blocklisting policy). A frame failing 3 is a benign
failure — a retransmit, which an admin reconnecting after a reset legitimately sends when
it does not know what the broker last accepted — and is counted separately; a broker MAY
reset a publisher stream whose retransmit rate exceeds its policy. A frame failing 2 on a
publisher or pending stream is dropped and counted (`wrong_challenge`) without counting
towards blocklisting, as the Frames section says. The two cheap checks precede the
signature check.

**There is no dedup window.** The cursor is total: a message is either at or beyond the
next expected index or it is not, and there is no eviction and no edge. **Gaps are
allowed** (`n > cursor`): they are the publisher's business, and SWIP-65 makes them
detectable and recoverable at the subscriber. A returning admin that continues where it
left off sets the cursor with its first accepted update, never back. This is stricter
than SWIP-65's general carriage rule, under which a broker does not enforce
monotonicity; the restriction is sound here because one publisher on one hop admits no
legitimate reordering.

Subscribers re-verify every delivery exactly as the broker does (steps 3 and 4, against
the spec they joined with and their own cursor, the index and the session topic read
from the slot — never step 2: the challenge in the slot was the broker's check, and the
subscriber's own challenge is compared with nothing), end to end, whatever the broker
did.

### Lifetime: inactivity

**A cohort ends by inactivity, and by nothing else.** A cohort on which no publisher
stream has had a message accepted for the **inactivity deadline** is reclaimed: the
broker resets every stream in it and forgets it. There is no end-of-stream signal in
BPS-lite — that is one of the admin's service messages, of which this SWIP has none; an
application that needs
"over" to be distinguishable from "paused" sends it in its last update, or waits for the
service feed the family adds.

A publisher stream going away — closed or reset — is therefore not an end: the cohort
and its cursor persist, subscribers stay attached, and the admin rejoins — admitted as a
pending stream whether or not its old one is still held — receives a fresh challenge,
and claims with its first update under it, continuing at whatever index it is at. Likewise a subscriber-only cohort waits for its admin until the deadline
reclaims it. A cohort with **no attached streams** MAY be reclaimed at once — nothing
observes the difference beyond a fresh cursor on the next `Join`.

After a cohort is forgotten a later `Join` creates a fresh one with the cursor at 0, and
every stream on it a fresh challenge: nothing the admin signed for the old session is
accepted on the new, so a stale republication is caught at the broker as well as at the
edge, where subscribers keep their own cursor per `(topic, admin)`.

### Resource bounds

All broker policy, none on the wire. The first six bounds are REQUIRED, with the values
given RECOMMENDED where a value is given; the last two are MAY:

| bound | answer | recommended |
|---|---|---|
| subscriber streams per cohort — the fan-out set | `FULL` to the next `Join` — except a `Join` declaring the admin's `addr`, admitted **outside the bound as a pending stream**: attached, in no fan-out set, receiving nothing, until its first publication under its challenge upgrades it, or the **claim deadline** disconnects it, with a short blocklist, counted (`claim_timeout`) | implementation-defined; claim deadline 30 s, long enough for a wallet prompt (?) |
| live cohorts per broker | `FULL` to a cohort-creating `Join` | implementation-defined |
| **cohorts per peer connection** — a peer cannot flood the broker with bogus cohorts while keeping one legitimate stream open | `FULL` | 16 |
| **streams per peer connection per cohort** — one connection cannot fill a cohort's fan-out set with declared identities | `FULL` | 2 (?) |
| **inactivity deadline** — reclaims a cohort, see *Lifetime* | reset | 10 min |
| outbound queue per subscriber stream, one writer; a full queue resets that stream | reset | 64 frames |
| a peer connection with no live stream | MAY be disconnected at the transport | — |
| a cohort with no attached streams | MAY be reclaimed at once | — |

Any peer can make a broker allocate a cohort simply by joining, which is why the second,
third and fifth bounds exist together: a cohort costs a map entry, a peer can hold only
a bounded number of them, and none survives idleness. The pending stream is what keeps
an audience that fills the cohort while the admin is away — or an old stream of the
admin's that the transport has not yet reaped — from locking the admin out, and it is
not a slot anyone can squat: it receives nothing, costs a map entry and a challenge for
one claim deadline, and one connection holds a bounded number of streams per cohort.
Declaring the admin's address buys exactly that. The broker has no
delivery obligation: a reset for a full queue is a recoverable liveness fault, and
blocking fan-out on one slow subscriber would punish the cohort.

### Relation to SWIP-60

BPS-lite is the **base** of the BPS family and SWIP-60 is its full singlehop protocol.
The relation is subset, and it is kept in one direction only — **later revisions extend
this wire, they never change it**:

- a BPS-lite peer sends only frames the full protocol accepts, and a BPS-lite broker
  accepts only what this SWIP defines: a spec value outside this SWIP is `REJECTED`, a
  field this SWIP does not define is ignored, so a fuller spec is served as the lite spec
  its known fields spell — a feed-topic cohort whose admin later publishes a roster is,
  at a BPS-lite broker, a live stream whose roster is dropped (`wrong_challenge`) and
  whose grantees' first updates are violations, their streams reset; an admin that wants
  a roster needs a full broker;
- a BPS-lite publisher and subscriber at a full broker are conformant peers of a
  single-publisher live-stream cohort; the full broker's additions (the admin's service
  messages) reach them as frames they drop;
- validation here is stricter, never looser: the cursor refuses out-of-order
  retransmits; no frame a BPS-lite broker accepts is one a full broker refuses.

What SWIP-60 adds on this wire: cohort parameters (`publishers`, `history`, `closed`),
the admin's service feed (roster, end of stream) as `Broadcast` frames whose payload is a
service message, the claim by any rostered address and none at all under `ALL`, pending
streams for rostered addresses, and the Bee API.

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
cohort's identity, the broker is never trusted about it, `Ack` is a status and a
challenge, and the first-joiner-creates rule is the natural one.

**Why a challenge, and what it protects.** A static signature — over the topic and the
admin, say — would be replayable by design, and the argument that a replayed role can
publish only what its owner already signed is true and beside the point: replaying the
admin's signed updates is *history*, and a first-time viewer receiving them from the
beginning is caught up, not deceived. What a replayed signature buys is an **identity**:
a stream the broker treats as the admin's — exempt from the fan-out bound and its queue
policy, and in SWIP-60 admitted to a `closed` cohort and promoted by a roster. A challenge issued for this stream and answered by a signature
under it is what makes the identity worth exactly the key.

**Why the challenge is random, per stream.** A challenge derived from a broker secret
and the address is issued without being stored, and it is the same on every stream the
address opens while the broker runs — which is the flaw: whoever once captured the
admin's answer to it (the node that bridged the admin, say) can present it again after
the admin drops, and holds the admin's identity at this broker until it restarts. A
challenge drawn at random for the stream is answered on that stream or nowhere; the
broker keeps it as long as the stream, which it keeps anyway, and nothing survives the
stream to be replayed.

**Why the challenge salts the feed, and the first publication is the claim.** A
challenge answered once, by a claim, protects the claim; the updates that follow are
signed for the channel, and whoever captured them from one session can present them in
another — to a broker whose cursor has restarted after a reclaim, they are fresh. Salting
the topic with the challenge signs every update for the session it was published in, so
there is nothing to replay: an update carries the challenge in the clear in its `id`
slot, the broker requires its own, and a chunk of another session, another broker or the
channel's own feed fails that check before any signature is looked at. Once every update
answers the challenge, the first one is the claim, and a claim that is anything else — a
chunk with a kind, a frame of its own, a credential in `Join` — is a second thing to
specify, sign, verify and replay. Salting the *topic* — `keccak256(topic ‖ challenge)`
is a topic like any other — keeps the session feed an ordinary feed, so that a
subscriber that saves the run has a feed it can replay with ordinary tooling, under a
topic every chunk of it names. What it costs: the publisher signs once per stream it
holds, and the live chunks are the session feed's, not the channel's — a publisher that
wants the run persisted under the channel's own topic signs the same wrapped payloads
again under `keccak256(topic ‖ index)`, which is one signature each over a chunk it
already has (?).

**Why the identity is on the stream, and the address is declared.** A peer connection is
a node; a stream is a (node, cohort) pair; the identity that matters is the key that
signs the messages on that stream. Declaring the address in `Join` admits as pending
only a stream that says it is the admin's, and tells the broker which address to hold
the stream's first publication to. Binding the identity to the stream is what lets one
node carry different identities on different streams — and, in SWIP-60, what lets a
subscriber stream be upgraded by its first publication when the admin grants it.

**Why the frame carries no address.** The ordinary SOC validation checks that the signer
hashes, with the id, to the chunk's address; a receiver that only recovered a signer
would accept any signature at all. But the address is not information the sender has and
the receiver lacks: publishing is restricted to known owners — the admin here, a claimed
or declared address in SWIP-60 — so every receiver forms the expected address itself and
holds the chunk to it. That is the same check with the owner forced, and 32 bytes fewer
on every frame.

**Why no reply to a claim.** After the handshake each direction carries one frame type,
and the wire has no envelope. A reply would be a second broker-to-peer type on a stream
that carries deliveries, with nothing to tell them apart. It is also unnecessary: streams
are ordered, so a publisher sends its first publication and its second together and
learns the outcome from whether the stream survives.

**Why no loopback.** A publisher knows what it published. Echoing it costs a frame per
message on the stream whose back-pressure matters most, and buys no confirmation: a
rejected frame produces no echo either.

**Why the cursor, not a window.** A bounded seen-set is a memory bound with a replay hole
at its edge, and it exists because the general protocol admits many publishers and
duplicate paths. One publisher on one hop has neither. The feed index is a total order,
and "at least the next" is both the dedup rule and the memory bound.

**Why inactivity, and only inactivity.** An end that is *signed* by the admin is one of the
admin's service messages, of which this SWIP has none; an end that is *inferred* from the
admin's stream
turns every transport hiccup into a stream-ending event for the whole audience. So there
is no end: a cohort is a map entry that lives while it is used and is reclaimed when it is
not. What that gives up — "over" versus "paused" — is the application's to carry until the
service feed arrives.

## Security considerations

Those of SWIP-60, restricted to its live-stream configuration (admin set, the admin
alone publishes, open audience).

**The publisher role takes the key, every time, and the session takes it again.** Every
update, the first included, is a chunk signed by the publisher's key under a challenge
that exists on one stream. What can be captured and replayed, by whom, and what stops
it:

| replayed | by whom | where | result | stopped by |
|---|---|---|---|---|
| a session's updates, the first included | anyone who received them — every subscriber, the node that bridged the admin, a relay, the broker itself | any other stream: another node, the same node reconnecting, this broker after a restart or a reclaim, another broker, another cohort | refused before any signature is checked — dropped and counted on a stream declaring the admin's address, a violation on any other | the challenge in the `id` slot: the receiving stream's differs, and an update is signed for its session's feed |
| a session's updates, at an index the publisher reused in a later session | a broker that carried the earlier session | a subscriber, in place of the later session's update | delivered: the subscriber cannot tell sessions apart | the publisher never reusing an index; then the earlier update is below every returning subscriber's cursor, and history to a first-time one |
| the challenge | anyone, by joining and declaring the admin's address | this broker | harmless: it proves nothing without the key; the declaration buys a pending stream, which receives nothing, until the claim deadline, then a blocklist | the first publication, not the challenge, is the credential |
| the challenge, forwarded | a relay or impostor broker the publisher was pointed at: it joins the honest broker as the admin, hands the challenge it receives to the publisher as its own, and forwards what the publisher signs under it | the honest broker | the publisher's own updates reach the honest broker, as the publisher's — the relay is a transparent hop that can withhold, not author; the publisher published to the audience it meant to and one more | nothing needed: a relay of a public broadcast is what SWIP-61 makes of every node, and there is no identity to steal, only updates to carry |
| an update of the channel's own feed, `keccak256(topic ‖ index)` | anyone holding it | any stream | refused | the `id` slot: 24 zero bytes are no stream's challenge, and the channel's topic is no session's |
| the admin's updates, on the admin's own publisher stream | the admin's node, or the admin | this session | dropped as retransmits, counted | the cursor |
| the admin's updates, on another node's publisher stream | a second node the admin publishes from | this broker | accepted: each stream has its own challenge, and the admin signed for each | nothing needed: that is the admin publishing twice |
| the admin's updates, in the channel's own feed | the admin, a broker or a subscriber that saved them | storage, to first-time viewers | delivered — **history**, genuine updates in order, a late viewer caught up | nothing needed; returning viewers keep their cursor per `(topic, admin)`, first-time freshness is the payload's (SWIP-65) |
| a `Join` | anyone | anywhere | attaches or creates, as any join does — no privilege | nothing needed; the bounds and the inactivity deadline |

**No confidentiality**: the broker and every subscriber see plaintext; applications
encrypt payloads. **The broker withholds, never forges**, and a withheld update is
visible as a gap in the index. **No end signal**: a broker can end a cohort for its
audience by resetting their streams, which is withholding, nothing more. **Resource
bounds are policy; the four capacity bounds, the inactivity deadline and the queue bound
are required** (above); the cursor
removes the dedup-window bound and its edge, and the challenge is 24 bytes per stream
the broker holds anyway; a pending stream is a map entry and a challenge for one claim
deadline, and delivers nothing. A subscriber that publishes is a protocol
violation and is blocklisted; a squatted cohort is one map entry for one inactivity
deadline, and a peer can hold only a bounded number of them and of streams per cohort.

## Conformance (definition of done)

An implementation is BPS-lite conformant when:

1. a broker accepts a `Join` whose spec is `{topic, FEED_TOPIC, admin}` and answers any
   other binding or an absent `admin` with `REJECTED`, ignoring fields it does not define;
2. a `Join` for a spec with no live cohort creates it, whoever sends it; a `Join` with a
   byte-identical canonical serialisation attaches to it; no status other than `OK`,
   `FULL` and `REJECTED` is ever sent;
3. every `Ack{OK}` carries a challenge of exactly 24 bytes, never all zero, drawn at
   random for that stream, held for the stream's life and never persisted or reused,
   and no `Join` carries or is answered on any credential;
4. a `Join` declaring the admin's `addr` is admitted outside the fan-out bound as a
   pending stream that receives nothing; its first `Broadcast` under its challenge is
   its claim: it upgrades the stream to a publisher stream iff, with
   `id = keccak256(keccak256(topic ‖ challenge) ‖ index)`, the chunk validates as a
   single-owner chunk at `keccak256(id ‖ admin)`; it is then delivered or counted as a
   retransmit like any publication; no reply is sent;
5. a frame on a subscriber stream, and a frame under the challenge on a pending stream
   that does not validate, is dropped, counted (`wrong_stream`), the stream reset, the
   peer blocklisted; a frame not under the stream's challenge, on a pending or a
   publisher stream, is dropped and counted (`wrong_challenge`) and nothing else;
6. a `Broadcast` on a publisher stream is accepted iff its slot begins with the stream's
   challenge, the index in the slot is at least the cursor, and the chunk validates as a
   single-owner chunk at the address the broker forms itself,
   `keccak256(keccak256(keccak256(topic ‖ challenge) ‖ index) ‖ admin)`; accepted frames
   set the cursor past their index and are delivered unchanged to every subscriber
   stream in the cohort, and to no publisher stream;
7. `n < cursor` is counted as a retransmit, not a violation; a slot not beginning with
   the stream's challenge is dropped and counted, not a violation; there is no other
   dedup state; gaps are accepted; index 0 is accepted on a fresh cohort;
8. a cohort with no accepted message for the inactivity deadline is reclaimed, every
   stream in it reset; a publisher stream going away does not end the cohort;
9. the capacity bounds are enforced — streams per cohort, cohorts per broker, cohorts
   per peer connection, streams per peer connection per cohort — `FULL` is issued at
   capacity and nothing else is; a pending stream is disconnected if it has not claimed
   within the claim deadline;
10. a subscriber re-verifies every delivery against the spec it joined with and its own
    cursor, reconstructing the session topic and the id from the topic and the slot, and
    compares the slot's challenge with nothing;
11. a publisher signs every update under the challenge of the stream it sends it on,
    discards or re-signs what it had queued for a stream that was reset, and never
    reuses an index across sessions;
12. a BPS-lite publisher and subscriber interoperate with a full SWIP-60 broker on a
    single-publisher cohort.

A broker MUST expose per-cohort counters for the silent outcomes — `wrong_challenge` (a
frame on a publisher or pending stream whose slot does not begin with the stream's
challenge),
`invalid_soc` (a chunk that does not validate at the expected address: bad signature,
wrong owner or wrong digest alike), `wrong_stream` (a frame on a subscriber stream, or a
claim that did not validate), `claim_timeout` (a pending stream
disconnected at the claim deadline), `retransmit`, `queue_reset` — since items 5–7 and 9
are unobservable from the wire without them.

## Out of scope (deliberately)

The admin's service messages (roster, end of stream) and the Bee API bridge; multiple
publishers and the claim by a rostered address; the self-indexed payload construction,
gap recovery and persistence of [SWIP-65](https://github.com/ethersphere/SWIPs/pull/106);
multihop ([SWIP-61](https://github.com/ethersphere/SWIPs/pull/105)); history; bandwidth
incentives; broker discovery ([SWIP-59](https://github.com/ethersphere/SWIPs/pull/103));
confidentiality of any kind. Each extends this SWIP's wire without changing it.

## Backwards compatibility

New protocol; no existing behaviour changes. Every message and field number here is
kept by the fuller protocol, which extends by adding fields, values and messages and
never by changing these; a BPS-lite peer ignores fields it does not define.

## References

Full singlehop protocol: [SWIP-60, PR #104](https://github.com/ethersphere/SWIPs/pull/104)
· carriage: [SWIP-65 self-indexed feeds, PR #106](https://github.com/ethersphere/SWIPs/pull/106)
· first draft of this SWIP: [PR #111](https://github.com/ethersphere/SWIPs/pull/111)
· origin: [PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub"
· implementation: bee [#5626](https://github.com/ethersphere/bee/pull/5626) (groundwork:
bee [#5597](https://github.com/ethersphere/bee/pull/5597), [#5435](https://github.com/ethersphere/bee/pull/5435))

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
