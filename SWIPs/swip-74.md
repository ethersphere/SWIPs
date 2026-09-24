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
challenge; rev 2 wrongly replaced it with a static signature). SWIP-60 (PR #104) is the
full singlehop protocol and extends this wire without changing it; see "Relation to
SWIP-60". Open points are marked (?). -->

- **Business line**: a live stream on Swarm — one author, an audience, real time, no
  storage round trip and no polling: video/audio streaming, a price ticker, a game's
  server-authoritative state, a log tail. The stream is a feed, so the same updates can
  later be persisted and replayed from storage by anyone who missed the live run.
- **Dev line**: implement one libp2p protocol, `pubsub/1.0.0`, with the four frames
  below — one broker, direct streams, one publisher that proves its key by signing a
  challenge, read-only subscribers — and nothing else: **no history, no bandwidth
  incentive, no service messages, no Bee API, one hop, one mode.** Done when a broker, a
  publisher and subscribers from independent implementations interoperate per the
  conformance section. Everything the family adds — service messages and the Bee API,
  multiple publishers, self-indexed feeds, multihop — extends this wire without changing
  it.
- **DISC change**: NO. A new p2p protocol surface; no storage, retrieval or incentive
  change.

## Simple Summary

BPS-lite is a real-time broadcast protocol: a kind of push notification on a *channel*
that anyone can subscribe to and one participant can publish on. Each channel defines
its own cohort — a set of nodes connected through a unique central broadcaster node, the
**broker**; every node in the cohort is directly connected to the broker, hence
*singlehop*. A channel is identified by its spec — a feed topic and the address of its
**admin**. Anyone joins by sending that spec, and a peer that means to publish also names
the address it will publish as; the broker answers with a **challenge** it derives from a
secret it never stores, and the publisher claims its stream by signing it. Its messages
are single-owner chunks that are the higher-index updates of the feed the topic names,
carried with their bare index; the broker accepts each one iff its index is at least the
channel's cursor, the chunk validates as a single-owner chunk under the feed's id, and its
owner is the admin, and delivers it unchanged to every subscriber stream — never to a
publisher's. All other joiners are subscribers and verify the same way, end to end: the
broker can withhold, never forge. A channel ends when it goes idle.

## Motivation

SWIP-60 spans several cohort configurations, five topic bindings, a roster control plane
on a service feed, a history flag and the Bee API. That is the right target for the
reference implementation and too much for a second, independent one whose application
is one author broadcasting to an audience. BPS-lite names that one configuration and
specifies only what it needs, so that a second team can implement and conformance-test
it from four frames — and so that it stays the **base** of the family: nothing here is
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
- **Subscriber**: joins by naming the cohort, receives, never publishes. A publication
  from a subscriber stream is a protocol violation.
- **Publisher and broker are distinct nodes**; brokering for oneself is out of scope.

### The cohort spec

Three fields, no others:

| field | value |
|---|---|
| `topic` | 32 bytes: the feed topic |
| `binding` | `FEED_TOPIC`: the signed id of every message is `keccak256(topic ‖ index)` |
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
  FEED_TOPIC                = 4; // signed id = keccak256(topic || index)
}

// The cohort's identity. Fixed by whoever joins first; immutable; keyed by its
// canonical serialisation.
message CohortSpec {
  bytes        topic   = 1; // 32 bytes
  TopicBinding binding = 2; // FEED_TOPIC
  bytes        admin   = 3; // 20 bytes, required
}

// A secp256k1 signature, as a SOC's: r || s || v.
message Auth {
  bytes  r = 1; // 32 bytes
  bytes  s = 2; // 32 bytes
  uint32 v = 3; // 27 or 28
}

// A publisher's claim on the stream it is sent on. `auth` signs
//   keccak256("bps-claim:v1" || S || O_B || index)
// with the key of `addr`: S the challenge the broker issued for `addr` on this
// cohort, O_B the overlay of the broker the claiming node is connected to, `index`
// eight bytes big-endian. Sent inside Join by a peer that already holds S, or as the
// next frame after Ack by one that has just received it.
message Claim {
  bytes  addr  = 1; // 20 bytes: the address claimed; equals Join.addr
  uint64 index = 2; // the publisher's cursor: its next message has an index >= this (?)
  Auth   auth  = 3;
}

// Peer -> broker: the first frame on a fresh stream. Creates the cohort if no live
// cohort has this spec, attaches to it otherwise.
message Join {
  CohortSpec cohort = 1;
  bytes      addr   = 2; // 20 bytes: the address this stream will publish as; absent:
                         // a subscriber, and no challenge is issued
  Claim      claim  = 3; // a returning publisher's claim, verified before any bound
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
  bytes  challenge = 2; // S, iff status == OK and addr was declared
}

// Both directions after the handshake: publisher -> broker is a publication, broker
// -> subscriber a delivery of the same bytes. The single-owner chunk travels whole,
// address and data, opaque to the protocol and validated by the ordinary SOC code
// once the id slot has been rewritten as the Frames section says:
//   data = id (32) || signature (65) || span (8, LE) || payload (<= 4096)
message Message {
  bytes address = 1; // 32 bytes: the SOC address, keccak256(id || owner)
  bytes data    = 2;
}
```

Four frames — `Join`, `Ack`, `Claim`, `Message` — and the two types they carry,
`CohortSpec` and `Auth`. There is no envelope: **what a frame is follows from the
stream's direction and role.** The first peer-to-broker frame is a `Join` and the first
broker-to-peer frame an `Ack`; after that a broker sends only `Message`, a subscriber
stream sends only a `Claim`, and a publisher stream sends only `Message`. A frame that
does not parse as what its stream may send is invalid.

### Handshake: `Join`, the challenge, the claim

Every peer sends `Join` as the first frame on a fresh stream, carrying the full
`CohortSpec`; a peer that means to publish also declares the address it will publish as,
in `addr` — an assertion, proved only by the signature that follows.

The broker compares the spec against its live cohorts: **no match → the cohort is
created** with the joiner attached; **match → the joiner is attached** to it. Anyone may
create, including a subscriber arriving before the admin: a publisher-less cohort costs
the broker one map entry until the inactivity deadline reclaims it, and can accept no
message. There is nothing to pre-register and no "unknown topic".

**The challenge.** For a `Join` that declares `addr`, the broker derives

```
S_C = a secret drawn once at broker boot, never persisted
S_s = keccak256(Marshal(spec))                the cohort's key
S_c = keccak256(S_C ‖ S_s)                    the cohort's secret
S   = keccak256(S_C ‖ S_c ‖ addr)             the challenge for addr on this cohort
```

and answers `Ack{OK, S}`. The broker stores nothing: it recomputes `S` from its boot
secret, the spec and the address whenever a claim arrives. `S` is therefore the same for
an address on a cohort for as long as the broker runs, from whichever node the address
joins, and differs at every other broker and after every restart. It goes to the joiner
over the encrypted stream and is useful only to the key of `addr`; anyone may obtain it
by declaring the address, and gains nothing by it.

**The claim.** A publisher claims its stream by signing, with the key of `addr`,

```
keccak256("bps-claim:v1" ‖ S ‖ O_B ‖ index)
```

where `O_B` is the overlay of the broker the claiming node is connected to and `index`
is the publisher's cursor: the claim that its next message will have a feed index of at
least `index`. The domain separator keeps the signature disjoint from SOC signatures and
any other protocol's; `S` binds it to this broker, this cohort and this address; `O_B`
binds it to the verifier, which `S` cannot, because `S` is opaque to the signer (see
Security considerations); `index` is signed so that a replayed claim moves no cursor.
The claim is sent in one of two places:

- **in `Join`**, by a peer that already holds `S` for this address at this broker — a
  reconnecting admin, from the same node or another: the broker verifies it before any
  bound is applied, and a valid claim makes the stream a publisher stream from its first
  frame. A stale claim — the broker has restarted, `S` has changed — is treated as
  absent: `Ack{OK, S}` with the new `S`, no penalty;
- **as the next frame after `Ack`**, a `Claim`, by a peer that has just received `S`.

The broker recovers the signer and checks that it equals `addr` (ecrecover never fails,
it returns *some* address, which is why the address is declared and compared) and that
`addr` is the cohort's admin — the one address that may publish here. Then the stream
**upgrades** to a **publisher stream**: it leaves the fan-out set, and the cohort's cursor
becomes `max(cursor, index)`. There is **no reply**: a publisher sends its claim and its
first publication back to back, and stream ordering guarantees the broker handles the
claim first; a claim that did not upgrade makes the publication that follows a violation,
and the reset is the answer. Anything else — a signature that does not recover to `addr`,
an `addr` that is not the admin, a second claim on a stream — is a protocol violation:
dropped, counted (`invalid_claim`), the stream reset, the peer blocklisted per the node's
policy. Several streams MAY be claimed for the admin at once — the admin from two nodes,
or reconnecting before its old stream is torn down: each is a publisher stream, and the
cursor arbitrates.

**The rest of the handshake.** `Ack{OK}` without a challenge answers a `Join` that
declared no address: the stream is a **subscriber stream**. `FULL` answers a `Join` at a
capacity bound, `REJECTED` one whose spec has a value outside this SWIP. A non-`OK` `Ack`
ends the stream; on `OK` it is retained. A peer whose stream was refused or reset MUST
back off before rejoining (randomised exponential, 1 s to 30 s, full jitter); a broker
MAY reset a stream that retries faster. Without this every reclaim or reset of a cohort
brings its whole audience back at once.

### Frames

After the handshake a broker sends `Message` and nothing else, to subscriber streams; a
publisher stream sends `Message` and nothing else; a subscriber stream sends at most one
`Claim`. A delivery is the accepted publication's bytes, unchanged.

**The frame is a whole chunk.** `address` is the SOC address and `data` the chunk data,
so that the ordinary SOC validation applies: without the address it would be vacuous,
since recovering a signer always yields *an* address, and with it a bad signature fails
because the recovered owner no longer hashes to the address.

**The `id` slot carries the bare index.** A feed update's signed id is
`keccak256(topic ‖ index)`, `index` a uint64 big-endian in 8 bytes. On the wire the
32-byte `id` slot of `data` holds that index left-padded with 24 zero bytes, and the
receiver reconstructs the signed id from the cohort's topic (the carriage of
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)). A `Message` whose `id` slot
does not have 24 leading zero bytes is not a feed update: a broker drops it as invalid; a
subscriber drops it without counting it as a violation.

### Validation: the feed cursor

The broker keeps one **cursor** per cohort: **the lowest index it will accept next**,
initially 0 — index 0 is the first update of every feed. A `Message` arriving at the
broker is accepted iff, in order:

1. it arrived on a **publisher stream** — on a subscriber stream the frame is read as a
   `Claim`, and if it is not a valid one it is a protocol violation: dropped, the stream
   reset, the peer blocklisted per the node's policy;
2. its `id` slot is a bare index `n` and **`n ≥ cursor`**;
3. with the `id` slot rewritten to `keccak256(topic ‖ n)` the chunk **validates as a
   single-owner chunk**: the wrapped chunk's BMT address matches `span ‖ payload`, the
   signature over `id ‖ wrappedAddress` recovers an owner, and `keccak256(id ‖ owner)`
   equals `address`;
4. `address` equals `keccak256(id ‖ admin)` — the owner is the admin.

On acceptance the broker sets `cursor := n + 1` and enqueues the frame on **every
subscriber stream** in the cohort. Publisher streams receive nothing: a publisher never
gets its own messages back, on whichever of its streams they were sent.

Failures of 3 and 4 are invalid frames: dropped and counted; repeated invalid frames end
the connection (blocklisting policy). A frame failing 2 with `n < cursor` is the one
benign failure — a retransmit, which an admin reconnecting after a reset legitimately
sends when it does not know what the broker last accepted — and is counted separately; a
broker MAY reset a publisher stream whose retransmit rate exceeds its policy, since the
cursor check is cheap and precedes the signature check. A frame failing 2 because the
`id` slot is not a bare index is invalid.

**There is no dedup window.** The cursor is total: a message is either at or beyond the
next expected index or it is not, and there is no eviction and no edge. **Gaps are
allowed** (`n > cursor`): they are the publisher's business, and SWIP-65 makes them
detectable and recoverable at the subscriber. A claim's `index` moves the cursor forward
to what the admin has published elsewhere, never back. This is stricter than SWIP-65's
general carriage rule, under which a broker does not enforce monotonicity; the restriction
is sound here because one publisher on one hop admits no legitimate reordering.

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
and its cursor persist, subscribers stay attached, and the admin rejoins, claiming in its
`Join` with the `S` it holds and the cursor it knows. Likewise a subscriber-only cohort
waits for its admin until the deadline reclaims it. A cohort with **no attached streams**
MAY be reclaimed at once — nothing observes the difference beyond a fresh cursor on the
next `Join`.

After a cohort is forgotten a later `Join` creates a fresh one with the cursor at 0 —
and the same `S`, since the broker derives it, so the admin's claim still holds.
Subscribers keep their own cursor across that, so a stale republication is caught at the
edge, not at the broker.

### Resource bounds

All broker policy, none on the wire. The first four bounds are REQUIRED, with the values
given RECOMMENDED where a value is given; the last two are MAY:

| bound | answer | recommended |
|---|---|---|
| subscriber streams per cohort — the fan-out set | `FULL` to the next `Join` — except **one extra stream while the admin is absent**: a `Join` declaring the admin's `addr` when no publisher stream exists is admitted over the bound, and disconnected, with a short blocklist, if it has not claimed within the **claim deadline** | implementation-defined; claim deadline 30 s, long enough for a wallet prompt (?) |
| live cohorts per broker | `FULL` to a cohort-creating `Join` | implementation-defined |
| **cohorts per peer connection** — a peer cannot flood the broker with bogus cohorts while keeping one legitimate stream open | `FULL` | 16 |
| **inactivity deadline** — reclaims a cohort, see *Lifetime* | reset | 10 min |
| outbound queue per subscriber stream, one writer; a full queue resets that stream | reset | 64 frames |
| a peer connection with no live stream | MAY be disconnected at the transport | — |
| a cohort with no attached streams | MAY be reclaimed at once | — |

Any peer can make a broker allocate a cohort simply by joining, which is why the second,
third and fourth bounds exist together: a cohort costs a map entry, a peer can hold only
a bounded number of them, and none survives idleness. The extra stream is what keeps an
audience that fills the cohort while the admin is away from locking the admin out: an
unclaimed admin is a fan-out channel like any other, and its slot exists exactly while it
is absent; a returning admin that claims in its `Join` never needs it. The broker has no
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
  at a BPS-lite broker, a live stream whose roster and grantees' updates are dropped as
  invalid; an admin that wants a roster needs a full broker;
- a BPS-lite publisher and subscriber at a full broker are conformant peers of a
  single-publisher live-stream cohort; the full broker's additions (service messages)
  reach them as frames they drop;
- validation here is stricter, never looser: the cursor refuses out-of-order
  retransmits; no frame a BPS-lite broker accepts is one a full broker refuses.

What SWIP-60 adds on this wire: cohort parameters (`publishers`, `history`, `closed`),
the admin's service feed (roster, end of stream) as `Message` frames, a claim by any
rostered address and none at all under `ALL`, one extra stream per absent rostered
publisher, and the Bee API. What it presumes of the transport, this SWIP states below as
a precondition.

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
policy, entitled to the extra slot, and in SWIP-60 admitted to a `closed` cohort and
promoted by a roster. A challenge only this broker could have issued, for this address,
signed together with the verifier's overlay, is what makes the identity worth exactly
the key. Deriving it from a boot secret and the spec is what lets the broker issue it
without storing it, and lets an address keep its claim from any node and across
reclaims.

**Why the identity is on the stream, and the address is declared.** A peer connection is
a node; a stream is a (node, cohort) pair; the identity that matters is the key that
signs the messages on that stream. Declaring the address in `Join` lets the broker derive
the challenge for it, and gives the extra slot only to a stream that says it is the
admin's. Binding the identity to the stream is what lets one node carry different
identities on different streams — and, in SWIP-60, what lets a subscriber stream be
upgraded by a claim when the admin grants it.

**Why the frame is a whole chunk.** The ordinary SOC validation checks that the signer
hashes to the address. Without the address on the frame there is nothing to hash to, and
a broker that only recovered a signer would accept any signature at all.

**Why no reply to a claim.** After the handshake each direction carries one frame type,
and the wire has no envelope. A reply would be a second broker-to-peer type on a stream
that carries deliveries, with nothing to tell them apart. It is also unnecessary: streams
are ordered, so a publisher sends its claim and its first publication together and learns
the outcome from whether the stream survives.

**Why no loopback.** A publisher knows what it published. Echoing it costs a frame per
message on the stream whose back-pressure matters most, and buys no confirmation: a
rejected frame produces no echo either.

**Why the cursor, not a window.** A bounded seen-set is a memory bound with a replay hole
at its edge, and it exists because the general protocol admits many publishers and
duplicate paths. One publisher on one hop has neither. The feed index is a total order,
and "at least the next" is both the dedup rule and the memory bound — and the claim can
declare it, because a signed lower bound is exactly what a reconnecting publisher knows.

**Why inactivity, and only inactivity.** An end that is *signed* by the admin is a service
message, which this SWIP does not have; an end that is *inferred* from the admin's stream
turns every transport hiccup into a stream-ending event for the whole audience. So there
is no end: a cohort is a map entry that lives while it is used and is reclaimed when it is
not. What that gives up — "over" versus "paused" — is the application's to carry until the
service feed arrives.

## Security considerations

Those of SWIP-60, restricted to its live-stream configuration (admin set, the admin
alone publishes, open audience).

**The publisher role takes the key, every time.** A claim is a signature over a challenge
that only this broker could have issued for this address, together with the verifier's
overlay and the publisher's cursor. What can be captured and replayed, by whom, and what
stops it:

| replayed | by whom | where | result | stopped by |
|---|---|---|---|---|
| the claim signature | a third party or another subscriber | anywhere | cannot obtain it | it travels on the encrypted stream to the broker and nowhere else |
| the claim signature | the node that bridged the admin (holds it, not the key) | this broker, while it runs, from any node | accepted — it upgrades | nothing, by design: the identity continues from another node; that node held the admin's stream anyway and can publish only what the key signed |
| the claim signature | the same node | this broker after a restart, or another broker, or another cohort here | refused: recovers to some other address | `S_C` drawn at boot and never persisted; `O_B` names the verifier; the spec is in `S` |
| the claim signature | anyone | for another address | refused | the address is in `S`, and the signer must equal the declared address |
| the claim with a changed `index` | anyone holding one | anywhere | refused | `index` is inside the signed preimage |
| the challenge, forwarded | a relay or impostor broker the publisher was pointed at: it fetches `S` from the honest broker, hands it over, forwards the signature | the honest broker | refused | the publisher signs the overlay it is talking to, the relay's, and the honest broker checks its own |
| the claim signature as a SOC signature, or the reverse | anyone | anywhere | refused | the domain separator against the SOC's `id ‖ wrappedAddress` |
| the challenge | anyone, by declaring the admin's address | this broker | harmless: `S` proves nothing without the key; the declaration buys the extra slot until the claim deadline, then a blocklist | the claim, not `S`, is the credential |
| the admin's publications | a subscriber or third party | this broker, cohort alive | violation: reset, blocklist | a publication is accepted on a publisher stream only, and that takes the key |
| the admin's publications | the admin's own node, or the admin | this broker, cohort alive | dropped as retransmits, counted | the cursor |
| the admin's publications | the admin's node, or a broker that carried the cohort | after a reclaim, or at another broker, to first-time viewers | delivered — **history**, genuine updates in order, a late viewer caught up | nothing needed; returning viewers keep their cursor per `(topic, admin)`, first-time freshness is the payload's (SWIP-65) |
| a `Join` | anyone | anywhere | attaches or creates, as any join does — no privilege | nothing needed; the bounds and the inactivity deadline |

**The transport precondition.** The forwarding row above rests on `O_B` being the overlay
the publisher's node is actually connected to, and the claim rests on the broker knowing
the peer it is talking to. A BPS node MUST verify, in the p2p handshake, that a peer's
signed address record names the connection's authenticated peer ID; a record that is
merely self-consistent — signed by the overlay's key but not tied to the connection — can
be presented by anyone who has seen it. (bee's handshake verifies the record and not the
binding as of this writing; the check is one comparison.)

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
   other binding or an absent `admin` with `REJECTED`, ignoring fields it does not define;
2. a `Join` for a spec with no live cohort creates it, whoever sends it; a `Join` with a
   byte-identical canonical serialisation attaches to it; no status other than `OK`,
   `FULL` and `REJECTED` is ever sent;
3. the challenge is derived as specified from a boot secret, the canonical spec and the
   declared address, issued iff an address was declared, and nothing is stored for it;
4. a claim — in `Join`, or as a subscriber stream's next frame — is verified over
   `keccak256("bps-claim:v1" ‖ S ‖ O_B ‖ index)`: the signer equals `addr` and `addr` is
   the admin; the stream then becomes a publisher stream and the cursor becomes
   `max(cursor, index)`; no reply is sent; a claim in `Join` is verified before any bound;
   a stale claim in `Join` is treated as absent; any other claim is a violation;
5. a frame on a subscriber stream that is not a valid claim is dropped, the stream reset,
   the peer blocklisted;
6. a `Message` on a publisher stream is accepted iff its bare index is at least the
   cursor, the chunk validates as a single-owner chunk under `keccak256(topic ‖ index)`
   with the owner hashing to `address`, and `address` is `keccak256(id ‖ admin)`; accepted
   frames set the cursor past their index and are delivered unchanged to every subscriber
   stream in the cohort, and to no publisher stream;
7. `n < cursor` is counted as a retransmit, not a violation, and there is no other dedup
   state; gaps are accepted; index 0 is accepted on a fresh cohort;
8. a cohort with no accepted message for the inactivity deadline is reclaimed, every
   stream in it reset; a publisher stream going away does not end the cohort;
9. the capacity bounds are enforced, `FULL` is issued at capacity and nothing else is;
   one extra stream is admitted for a `Join` declaring the admin's address while no
   publisher stream exists, and disconnected if it has not claimed within the claim
   deadline;
10. a subscriber re-verifies every delivery against the spec it joined with and its own
    cursor;
11. the node verifies in the p2p handshake that a peer's signed address record names the
    connection's authenticated peer ID;
12. a BPS-lite publisher and subscriber interoperate with a full SWIP-60 broker on a
    single-publisher cohort.

A broker MUST expose per-cohort counters for the silent outcomes — `invalid_index`,
`invalid_soc`, `wrong_owner`, `wrong_stream`, `invalid_claim`, `retransmit`,
`queue_reset` — since items 5–7 are unobservable from the wire without them.

## Out of scope (deliberately)

Service messages of any kind (roster, end of stream) and the Bee API bridge; multiple
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
