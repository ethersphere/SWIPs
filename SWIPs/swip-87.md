---
SWIP: 87
title: BPS explicit multi-publisher — the admin's roster and end of stream over BPS-lite
author: Viktor Trón (@zelig)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-10-12
requires: 74
---

<!-- Rev 1 (2026-10-12). The second step of the Broadcast Pub/Sub (BPS) family: SWIP-74
(BPS-lite, PR #111) plus the admin's control plane — a roster naming who else may
publish, and an end of stream — and nothing else. It is the roster slice of SWIP-60
(PR #104), lifted out so that it can be implemented and conformance-tested on its own:
every frame, field and value here is SWIP-60's, and a SWIP-87 peer is a conformant
SWIP-60 peer on a feed-topic cohort with an admin. Departures from SWIP-60 rev 13, to be
carried back to it: no grace period on revocation; roles change only by rejoining; the
broker keeps cursors for the admin and the currently rostered addresses only. Rev 2
(2026-10-13): a stream's role is fixed at `Join` and by its `AUTH`, and nothing changes it
in place — a spectator a roster names rejoins to publish, and a stream whose address a
roster drops is written that roster and closed, what it sends meanwhile dropped
unpunished (a frame in flight, or in multihop a relay that has not yet seen the roster,
is not a violation); a stream being closed writes its queue within a flush deadline.
Open points are marked (?). -->

- **Business line**: a live stream with more than one voice — a panel, a co-hosted show,
  a band jamming, a newsroom ticker with several editors, a game whose server is
  replicated — under one author who decides, at any moment and visibly to everyone,
  who else may speak; and a stream that can be **ended**, attributably, instead of
  going quiet.
- **Dev line**: on top of SWIP-74, two more kinds on the same `Broadcast` frame —
  `ROSTER` and `EOS`, the admin's service feeds — one payload message, `Roster`, and the
  broker and subscriber rules they need: pending streams for rostered addresses, a
  cursor per publisher, delivery to publisher streams, revocation by roster, the end of
  a channel. **No new frame, no new field in `Join` or `Ack`, no change to the cohort
  spec.** Done when a broker, publishers and subscribers from independent
  implementations interoperate per the conformance section.
- **DISC change**: NO. Extends a p2p protocol surface; no storage, retrieval or
  incentive change.

## Simple Summary

In BPS-lite a channel has one publisher, its admin. Here the admin may name others: it
publishes a **roster** — the complete set of addresses that may publish besides itself —
as a signed chunk on a feed of its own, and the broker and every subscriber take it from
there. A stream that declares a rostered address authenticates with its `AUTH` exactly
as the admin's does and then publishes under its own key, at its own index, on its own
feed salted with its own challenge; every receiver admits an update iff its signer is the
admin or on the latest roster the admin signed. Publisher streams now receive what the
others publish. A roster that drops an address closes that address's streams once the
reduced roster has been written to them; what they send meanwhile is dropped, not
punished. Roles never change in place: a grantee rejoins to publish, a revoked peer to
listen. The admin can also end the channel with an
**`EOS`**: an empty signed chunk that the broker delivers to every stream before it
reclaims the cohort — the one clean way to close a stream for everyone.

## Motivation

SWIP-74 gives one author a live audience. The next thing every application asks for is a
second voice, and then a way to say "over". SWIP-60 has both, together with a group-chat
regime, closed cohorts, history, four more topic bindings and implicit authorship — a
specification a second team cannot implement in one go. The roster and the end of
stream are the part of SWIP-60 that needs nothing else of it: the cohort spec stays
SWIP-74's three fields, the handshake is untouched, and what changes is which addresses
a broker holds a stream's chunks to and who receives them.

Taking this slice on its own also settles, in a small text, the two rules that the rest
of SWIP-60 relies on: that a cohort is multi-publisher **iff its admin ever publishes a
roster** — so that nobody has to know in advance — and that the roster is the **admin's
word, relayed**: signed, indexed, verified end to end, never the broker's.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, RECOMMENDED and MAY are to be interpreted
as described in RFC 2119. **This SWIP extends SWIP-74 and reads with it**: everything
SWIP-74 specifies holds unless a section here says otherwise, and where a section here
restates a SWIP-74 rule with an addition, the restatement is normative.

### Terms

SWIP-74's terms, with these additions and changes:

| term | meaning |
|---|---|
| **admin** | the `principal`: the cohort's authority, the only writer of its service feeds, always a publisher |
| **service feed**, service message | the admin's control plane: `ROSTER` and `EOS`, each a kind with its own session feed, the owner of every service chunk forced to the admin |
| **roster** | the complete set of addresses that may publish besides the admin, as of one index: the payload of a `ROSTER` chunk; full state, not a delta |
| **rostered** | named by the latest roster the broker has accepted — at a subscriber, the latest it has accepted |
| **publisher** | the admin, or a rostered address |
| **`EOS`** | end of stream: the empty chunk at index 0 of the admin's `EOS` feed; ends the channel, attributably and for good |
| **grant**, **revocation** | the admin adding or removing an address by publishing the next roster; a grant takes effect at the grantee's `AUTH` on a stream it joins after seeing the roster, a revocation when the broker accepts the reduced roster, which closes the revoked streams |
| **role** | **pending stream** — declared a publisher's address, not yet authenticated: outside the fan-out bound, receives nothing but the roster that names it, sends nothing but its `AUTH`. **Publisher stream** — authenticated: sends publications and heartbeats and, if it is the admin's, service messages; **receives every delivery not its own**. **Spectator stream** — SWIP-74's subscriber stream: declared an address that is not a publisher's; within the bound, receives, sends nothing; a roster naming it later does not change it — the peer rejoins. **Revoked stream** — a pending or publisher stream whose address a roster dropped: written that roster, then closed; nothing it sends is read |
| **receiving stream** | a spectator or a publisher stream: one that deliveries are enqueued on |
| **fan-out set** | the spectator streams of a cohort, bounded per cohort; publisher streams receive outside it, bounded per address |
| **delivery** | an accepted frame forwarded unchanged: a `DATA` to every receiving stream not bound to the publishing identity, a `ROSTER` or `EOS` to every receiving stream but the one it came on |
| **cursor** | the lowest index accepted next, one per feed: at the broker one per publisher's `DATA` feed and one per service kind, at a subscriber the same, kept across streams and sessions |

### The contract

Per cohort: messages come from **the admin and the addresses on its latest roster, and
from no one else**; they arrive at **every receiving stream but their author's**; each
publisher's messages are **feed updates in increasing index order**; who may publish is
**the admin's signed word**, and so is the end.

### Wire format

Normative. SWIP-74's three frames — `Join`, `Ack`, `Broadcast` — and `CohortSpec`,
`TopicBinding` and `Status` are unchanged. `Kind` gains two values, and one message is
added as the payload of a `ROSTER` chunk. Numbers are SWIP-60's.

```proto
// What a chunk on this wire is.
enum Kind {
  KIND_UNSPECIFIED = 0; // invalid on the wire
  DATA             = 1; // an update of a publisher's feed
  AUTH             = 2; // the empty chunk at index 0 of the session's AUTH feed:
                        // authenticates a pending stream; a heartbeat on a publisher
                        // stream; never delivered
  EOS              = 3; // the empty chunk at index 0 of the admin's EOS feed: the
                        // channel is closed, attributably and for good
  ROSTER           = 4; // from the admin: the publisher set as of this index;
                        // payload = Roster
}

// The payload of a ROSTER chunk.
message Roster {
  repeated bytes publishers = 1; // 20-byte addresses: the complete set excluding the
                                 // admin, who is always a publisher. Full state, not a
                                 // delta: a reader needs only the latest it can verify.
}
```

A service chunk is an ordinary single-owner chunk on its kind's session feed, exactly as
SWIP-74 derives it:

```
prefix  = "bps-service:v1" ‖ kind           kind as one byte: 0x03 EOS, 0x04 ROSTER
topic_s = keccak256(prefix ‖ topic ‖ challenge)
id      = keccak256(topic_s ‖ index)        index 8 bytes big-endian
owner   = principal                         forced, in every case
```

### The service feeds

Everything the admin says about the cohort travels as chunks it signs, on feeds it
owns, one per kind:

| kind | index | payload | effect |
|---|---|---|---|
| `ROSTER` | `n`, sequential from 0 | `Roster` | the publisher set from now on is the admin and the addresses listed |
| `EOS` | 0 | none: span 0 | the channel is ended |

They are `Broadcast` frames like any other, sent on the admin's publisher stream under
that stream's challenge. The kind is in the id's preimage, so a roster cannot be passed
off as an end of stream, nor either as an update, nor an `AUTH` as an `EOS` though both
are empty chunks at index 0. Each kind counts its own indices, so a gap in the rosters
is a missing roster and nothing else.

**A cohort is multi-publisher iff its admin ever publishes a roster.** Until it does, the
admin is the only publisher and the cohort is a SWIP-74 cohort, frame for frame. Nothing
in the spec announces it, so no one has to know in advance, and an audience joining a
live stream does not learn the cohort's future from its invite.

**The roster is full state.** Each `ROSTER` names every address that may publish besides
the admin; an address it does not name is not a publisher, whatever an earlier one said.
Entries are 20 bytes each; an entry equal to the admin's address, and a repeated entry,
change nothing. The chunk's payload bounds a roster to what fits in 4096 bytes — 186
addresses. The admin MUST NOT reuse a roster index across sessions: a subscriber cannot
tell sessions apart, and its roster cursor is what keeps an earlier roster from
standing in for a later one.

**An `EOS` ends the channel, not a session.** A subscriber compares a frame's challenge
with nothing, so the end of any session of the channel is as good to it as this one's:
an admin that means to publish again after an `EOS` takes another topic (?).

### Roles

A stream's role is settled by its declared `identity` against the principal and the
**roster the broker holds at its `Join`**, and by its `AUTH` — and by nothing else: a
later roster never upgrades a stream, and revokes one only by closing it.

| `identity` | at `Join` | after a valid `AUTH` | any other frame before it |
|---|---|---|---|
| the admin's | **pending**, outside the fan-out bound, receives nothing | **publisher stream**; receives the latest roster first, then every delivery not its own | violation (`wrong_stream`) |
| rostered | **pending**, outside the fan-out bound; the latest roster — which names it — is delivered to it at once | **publisher stream**, as above | violation (`wrong_stream`) |
| neither | **spectator**, within the bound; receives the latest roster first, then every delivery | — any frame is a violation, an `AUTH` included, whatever a later roster says | violation (`wrong_stream`) |

**A grant takes effect at the grantee's `AUTH` on a stream it joins after the grant.** A
grantee learns of its grant from a roster delivered on a stream it holds — as a spectator,
or from an earlier session — and **rejoins**: the new `Join` declares its address, which
the broker now holds rostered, so the stream is pending, and the broker delivers it the
roster at once. The broker accepts the `AUTH` on a pending stream iff its identity is
still rostered when the `AUTH` arrives; it waits for nothing else. The spectator stream the
grantee held is not upgraded; the grantee SHOULD close it once its `AUTH` is sent, so
that it hears no gap meanwhile (?).

**The roster is the cue.** A peer other than the admin MUST NOT send its `AUTH` on a
stream before a roster naming its address has been delivered **on that stream** — on a
pending stream the broker's first frame. The broker does not enforce it and need not: an
`AUTH` on a pending stream is accepted iff the identity is rostered. It is what keeps a
grantee from authenticating at a broker that has not yet accepted the roster — one it
was told about out of band, or in multihop (SWIP-61) a hop the roster has not reached:
there its `Join` made a spectator, whose `AUTH` is a violation. A pending stream's first
delivery is the roster naming it; a spectator's first is the latest roster, which does
not. The admin needs no cue.

### Validation

The broker keeps, per cohort, a **cursor per publisher** — the lowest `DATA` index it
accepts next from that address, initially 0 — for the admin and every currently rostered
address, and a **cursor per service kind**, the **roster cursor** and the **`EOS`
cursor**, initially 0. A `Broadcast` arriving at the broker is accepted iff, in order —
SWIP-74's steps, extended:

0. it did not arrive on a **revoked stream** — a frame from one is dropped unread and
   counted (`revoked`), never a violation: it was sent before the peer read the roster
   that revoked it;
1. it arrived on a **publisher stream** — and, if its kind is `ROSTER` or `EOS`, on the
   **admin's** — or it is an `AUTH` on a **pending stream**; any other frame is a
   protocol violation: dropped, counted (`wrong_stream`), the stream reset, the peer
   blocklisted per the node's policy;
2. its `kind` is `DATA`, `AUTH`, `EOS` or `ROSTER` — another is dropped and counted
   (`unknown_kind`);
3. its `challenge` is **the stream's** — otherwise it is dropped and counted
   (`wrong_challenge`), and the broker MAY reset the stream;
4. its `index` is **at least its feed's cursor** — for `DATA` the cursor of the stream's
   authenticated address, for `ROSTER` the roster cursor — otherwise it is a
   retransmit, dropped and counted (`retransmit`); and `n < 2⁶⁴−1`; an `AUTH` and an
   `EOS` are at index 0, anything else is a violation under step 5;
5. the chunk's id is the one **derived from the frame**, and the chunk **validates as a
   single-owner chunk** at `keccak256(id ‖ owner)`, where the owner is the **admin** for
   `ROSTER` and `EOS` and the stream's declared `identity` for `DATA` and `AUTH` — on a
   publisher stream, the address it authenticated as. An `AUTH` or an `EOS` chunk
   moreover has span 0 and no payload. A failure is a protocol violation (`invalid_soc`);
6. for `ROSTER`, the payload **decodes as a `Roster`** of 20-byte entries — otherwise the
   frame is dropped and counted (`invalid_roster`), moves no cursor and changes nothing.
   The chunk is validated before its payload is read: an admin-signed chunk that does
   not decode is the admin's mistake, not a forgery.

Then, by kind:

- **`AUTH`** — upgrades a pending stream to a publisher stream; on a publisher stream it
  is a heartbeat. It is never delivered, moves no cursor, and counts as activity. A
  pending stream that upgrades receives the latest roster as its first delivery, unless
  it was given that roster as its cue.
- **`DATA`** — sets its publisher's cursor to `n + 1` and is delivered.
- **`ROSTER`** — sets the roster cursor to `n + 1`; its set **replaces** the broker's;
  it is delivered; and then, in this order: (a) it is enqueued at once on every pending
  stream it names; (b) every publisher or pending stream whose `identity` it no longer
  names is **revoked** (below); (c) the cursors of addresses it no longer names are
  forgotten.
- **`EOS`** — is delivered, and then the broker forgets the cohort and closes every
  stream in it once its queue — the `EOS` last — has been written: closed, not reset,
  so that the end reaches everyone; a stream whose queue is not written within the
  **flush deadline** is reset.

**Delivery.** An accepted `DATA` frame is enqueued, unchanged, on **every receiving
stream not bound to the publishing identity**: every spectator, and every publisher
stream but those authenticated as the address the frame was published under. A
publisher never gets its own updates back, on whichever of its streams they were sent;
it receives everybody else's — which is what a publisher stream adds to SWIP-74, where
it received nothing. An accepted `ROSTER` or `EOS` is enqueued on **every receiving
stream but the one it came on** — the admin's other publisher streams included, since
the roster is what every receiver admits by, and an admin publishing from two nodes
must hold it on both. The stream that sent a roster is not sent it back: its sender
admits by the roster it published.

**The latest roster is the first delivery** on every stream as it starts receiving — at
attach for a spectator, at its `AUTH` for a pending stream, unless it is the roster the
stream was already given as its cue — before any other frame, and is delivered at once
to a pending stream whose `identity` it names, its one delivery before its `AUTH`. A cohort whose admin has published no roster delivers
nothing first. So a joiner learns who may write from the admin, not from the broker,
before it receives a single update.

**Cursors are per address, never per stream or per session**, as in SWIP-74: a
publisher holding two streams — two nodes, or a reconnect — is arbitrated by its one
cursor. The table holds the admin and the rostered addresses and nothing else, so it
is bounded by the roster. A revoked address's cursor is forgotten; if a later roster
names it again, the broker's cursor for it starts at 0 — harmless, since a publisher
never reuses a `DATA` index, and every subscriber keeps its own cursor per publisher.

### Revocation

**A revocation takes effect when the broker accepts the roster that makes it, and it
closes the revoked streams.** At that moment every publisher or pending stream bound to
the revoked address becomes a **revoked stream**: the reduced roster is written to it —
a publisher stream receives it as a delivery, a pending one has it enqueued — and once
its queue is written the broker **closes** it, within the flush deadline, and resets it
if the peer does not take it in time. Nothing the stream sends after the revocation is
read for its content: a frame from a revoked stream is **dropped and counted
(`revoked`), never a violation**. There is no grace period and no timer of the peer's:
receiving the reduced roster is the notice, and the close is the enforcement.

The peer reads the roster that dropped it, then the end of its stream, and rejoins as
a spectator if it means to keep listening — its address is no longer rostered, so its
`Join` makes one. A peer SHOULD close its stream on reading a roster that drops it,
which spares the broker the flush.

**A revoked frame is dropped, not punished**, because it may be honest. On a direct
stream it is a frame the publisher had in flight before the roster reached it. In
multihop (SWIP-61) it is worse: rosters travel outward from the root, so a relay that
has not yet received the reduced roster still accepts the revoked publisher's updates
and forwards them inward, to hops that have; punishing them would punish the relay for
being behind. The rule a hop applies is the same on both: a frame by an address it no
longer admits is dropped and counted, and the stream that carried it is closed if it
was the revoked publisher's own.

The revocation is visible to everyone: every subscriber receives the reduced roster,
signed by the admin, and learns from it why a publisher fell silent, rather than
inferring it from a disconnection it cannot attribute.

### Subscribers

A subscriber — any peer on a receiving stream, a publisher's included — re-verifies
every delivery end to end, whatever the broker did:

- it derives the id from the frame's kind, challenge and index and the cohort's topic,
  and requires the chunk's to equal it; it compares the challenge with nothing;
- for **`ROSTER` and `EOS`** the owner is forced: the chunk MUST validate at
  `keccak256(id ‖ principal)`; a service chunk by any other owner is invalid. A
  `ROSTER` that validates but does not decode is dropped; an `EOS` with a payload or
  at another index is invalid;
- for **`DATA`** it recovers the owner from the signature over `id ‖ wrappedAddress`,
  forms `keccak256(id ‖ owner)` as the chunk's address and validates against it, and
  accepts iff that owner is **admissible**: the admin, or an address on the latest
  roster it has accepted;
- it keeps a **cursor per publisher** and a **cursor per service kind** — the roster
  cursor and the `EOS` cursor — per `(topic, admin)`, **across streams and sessions**,
  and drops what is below them; a roster at or above the roster cursor replaces its
  admissible set; an `EOS` sets the `EOS` cursor past 0 and the subscriber treats the
  channel as ended — a channel it has seen end it does not rejoin;
- it drops an `AUTH` and a kind it does not know;
- a publisher admits by the rosters it receives and, if it is the admin, by those it
  publishes, which the broker does not send back on the stream they came on;
- a peer that sees its address added to a roster rejoins to publish, with the cursors
  and the roster of this session; one that sees its address dropped stops publishing,
  and its stream is closed;
- an index gap in the roster feed is a liveness fault, and the subscriber does not
  admit on a roster it knows to be stale (?);
- a delivery that does not validate, or whose owner it does not admit, is a broker
  forwarding what it should have refused: the subscriber MUST reset the stream, and
  SHOULD NOT rejoin that broker for the cohort (?).

The ordering makes admission exact: a broker that follows this SWIP delivers a roster
granting an address before any update from it — the grantee's `AUTH` follows the roster,
and its updates the `AUTH` — and a roster revoking an address after its last accepted
update; a subscriber that sees an update from an address before the roster that admits
it, or after the roster that revokes it, has been shown something no honest broker
sends.

### Lifetime: the end of stream

SWIP-74's inactivity rule holds, and the `EOS` adds the one end that is **signed**: the
admin's, attributable, final. On accepting an `EOS` the broker delivers it to every
receiving stream but the sender's and then forgets the cohort, closing every stream in
it once its queue has been written. A subscriber that accepts an `EOS` treats the channel as ended; it can tell "over"
from "paused", which in SWIP-74 only the application could. A peer whose stream is reset
after an `EOS` does not rejoin the cohort; a later `Join` of the same spec creates a
fresh cohort, which a subscriber holding the `EOS` cursor refuses to treat as the same
channel (?).

An `EOS` is the only clean way to disconnect a cohort: everything else that ends one —
the inactivity deadline, a reset, a broker restart — looks to the audience like a
fault. A peer whose stream is closed after an `EOS` has read the `EOS` first.

### Resource bounds

SWIP-74's bounds, with these changes:

| bound | answer | recommended |
|---|---|---|
| subscriber streams per cohort — the fan-out set | `FULL` to the next `Join` — except a `Join` declaring the admin's **or a rostered** address, admitted outside the bound as a pending stream | implementation-defined |
| **publisher streams per address** per cohort — publisher streams receive outside the fan-out bound, so one key holding many would buy deliveries past it | an `AUTH` that would exceed it is accepted and resets the **oldest** of that address's publisher streams | 2 — one live stream and one reconnecting |
| the outbound queue | per **receiving** stream, spectator or publisher; a full queue resets that stream | 64 frames |
| **flush deadline** — a stream being closed, by an `EOS` or a revocation, has its queue written within it | reset | 5 s (?) |

A rostered address costs the broker what the admin's does: a pending stream outside the
fan-out bound, a map entry and a challenge for one auth deadline, bounded per peer
connection and cohort; and, authenticated, a cursor and at most two receiving streams.
The roster bounds the table of cursors.

### Outcomes

Every frame the broker receives ends in exactly one of the outcomes below — SWIP-74's,
with this SWIP's rows. The wire carries no error frame.

| what arrived | from | outcome | counter | the sender sees |
|---|---|---|---|---|
| a `Join` with a spec value outside SWIP-74 or an `identity` that is not 20 bytes | anyone | `Ack{REJECTED}`, stream closed | — | `REJECTED` |
| a `Join` at a capacity bound | anyone but the admin's or a rostered identity | `Ack{FULL}`, stream closed | — | `FULL` |
| a `Join` declaring the admin's or a rostered identity when the fan-out set is full | that address's node | admitted as a pending stream outside the bound | — | `OK` and a challenge; a rostered one, the roster |
| any `Broadcast` | a spectator stream, whatever a roster says | violation | `wrong_stream` | the stream is reset |
| anything but an `AUTH` | a pending stream | violation | `wrong_stream` | the stream is reset |
| a `ROSTER` or an `EOS` | any stream but the admin's publisher stream | violation | `wrong_stream` | the stream is reset |
| any frame | a revoked stream | dropped unread | `revoked` | nothing; the stream is closed |
| a kind this SWIP does not define | a publisher stream | dropped | `unknown_kind` | nothing |
| a frame whose challenge is not the stream's | a publisher stream, or an `AUTH` on a stream that may authenticate | dropped; the broker MAY reset the stream | `wrong_challenge` | nothing, or a reset |
| a `DATA` below its publisher's cursor, or a `ROSTER` below the roster cursor | a publisher stream | dropped | `retransmit` | nothing |
| a chunk whose id is not the one derived from the frame, or that does not validate at the address formed from the id and its owner; an `AUTH` or `EOS` with a payload or not at index 0; an index of 2⁶⁴−1 | a stream that may send that kind | violation | `invalid_soc` | the stream is reset |
| a `ROSTER` that validates but does not decode as a `Roster` | the admin's publisher stream | dropped; no cursor moves | `invalid_roster` | nothing |
| no `AUTH` within the auth deadline | a pending stream | stream reset, peer blocklisted for a short time | `auth_timeout` | the stream is reset |
| a valid `AUTH` | a pending stream whose identity is rostered or the admin's | upgraded to a publisher stream; the latest roster first unless it was the cue; activity; beyond the per-address bound the oldest publisher stream of the address is reset | — | nothing |
| a valid `AUTH` | a publisher stream | activity, nothing else | — | nothing |
| a valid `DATA` at or above its publisher's cursor | a publisher stream | cursor set past it; delivered to every receiving stream not bound to the publishing identity | — | nothing |
| a valid `ROSTER` at or above the roster cursor | the admin's publisher stream | roster cursor set past it; the roster replaces the broker's; delivered to every receiving stream but the sender; enqueued at once on pending streams it names; streams of addresses it drops revoked — written the roster, then closed; their cursors forgotten | — | nothing |
| a valid `EOS` | the admin's publisher stream | delivered to every receiving stream but the sender; the cohort reclaimed, every stream closed once its queue is written | — | the stream is closed |
| a delivery a receiving stream cannot take — its queue is full | the broker | that stream is reset | `queue_reset` | the stream is reset |
| a queue not written within the flush deadline | the broker, closing a stream | that stream is reset | — | the stream is reset |
| no accepted frame for the inactivity deadline | — | the cohort is reclaimed, every stream reset | — | the stream is reset |
| a delivery of an `AUTH`, of a kind it does not know, or below its cursor | the broker, at a subscriber | dropped by the subscriber | — | — |
| a delivery that does not validate, or whose owner the subscriber's roster does not admit | the broker, at a subscriber | the subscriber resets the stream | — | — |

### API (WebSocket bridge)

Informative: the Bee node's bridge between a dApp and this wire, extending the lite pair
of WebSocket endpoints; the dApp holds every key, the node none.

**The roster is the owner's alone.** Only the principal owns the roster and `EOS` feeds,
and only the principal can add to or change the roster; the bridge says so at the
socket, before the broker does.

- **`GET /bps/publish/{owner}/{topic}?broker&identity`** — `identity` is the owner by
  default, or a **seat**: an address the owner's latest roster names. A seat connects
  after it has seen itself on a roster; the node joins knowing it rostered, waits for
  the broker's cue, and closes the socket (4002) if the broker's first frame is anything
  else. The node then sends the challenge as JSON — `challenge`, `dataTopic`,
  `authTopic`, and to the owner also `rosterTopic` and `eosTopic` — and the dApp sends
  binary frames `kind (1) ‖ index (8) ‖ soc`: `DATA` and `AUTH` signed by the identity,
  `ROSTER` and `EOS` signed by the owner and accepted from the owner's socket only (4002
  from a seat's, and for a roster that does not decode). The `AUTH` comes first, as in
  SWIP-74. A publisher stream receives: the socket delivers what the other publishers
  publish, and the owner's rosters, in the subscribe socket's frame format. The roster
  travels on the owner's publish socket rather than a socket of its own, because the
  wire requires it on the admin's publisher stream, and a second socket would hold a
  second one.
- **`GET /bps/subscribe/{owner}/{topic}?broker&identity&cursor`** — every verified
  delivery as a binary frame `kind (1) ‖ owner (20) ‖ challenge (32) ‖ index (8) ‖
  soc`: `DATA` by the owner or a seat, `ROSTER` and `EOS` by the owner. The owner and
  the kind let the dApp re-verify every chunk itself, and the rosters let it show who
  may speak. After an `EOS` both sockets close with 4004.
- Close codes: 4001 invalid soc, 4002 invalid message, 4003 broker stream closed, 4004
  end of stream.

The subscriber's position across sessions — its cursor per publisher, the roster with
its cursor, the `EOS` cursor — is kept by the node within a session; across sessions the
dApp passes the owner's `cursor` (?).

### Relation to SWIP-74 and SWIP-60

**To SWIP-74, an extension that changes nothing.** Every SWIP-74 frame, field, value and
rule holds; a cohort whose admin never publishes a roster or an `EOS` behaves exactly as
a SWIP-74 cohort — except that its publisher streams receive each other's deliveries,
which, the admin being the only publisher, never arise. A SWIP-74 publisher at a SWIP-87
broker is a conformant admin that never uses its control plane. A **SWIP-74 subscriber
in a multi-publisher cohort is not**: it drops the roster as `unknown_kind`, re-verifies
every `DATA` at the admin's address, and resets its stream at the first update from a
grantee. A cohort whose admin grants needs SWIP-87 subscribers; an admin that wants to
reach SWIP-74 subscribers does not grant (?). At a SWIP-74 broker an admin's roster and
`EOS` are dropped as `unknown_kind`, and a grantee's `Join` is a subscriber stream
there, reset at its `AUTH` — an admin that grants needs a SWIP-87 broker.

**To SWIP-60, a subset.** Everything here is SWIP-60's explicit authorship on a
`FEED_TOPIC` cohort without `publishers`, `closed` or `history`: the same kinds, the
same `Roster`, the same roles but the silent one, the same validation. SWIP-60 adds the
`ALL` regime, `closed` and the silent role, `history`, the other bindings, implicit
authorship and its API. Three rules here are to be carried back to it: roles change only
by rejoining — no spectator or silent stream authenticates in place; revocation closes
the revoked streams and drops their frames unpunished, with no grace period; and the
cursor table bounded by the roster.

## Rationale

**Why the roster is on a feed, signed by the admin.** The obvious alternative — the
broker keeps a list the admin edits by command — makes the broker the authority on who
may write, and a subscriber has no way to check it. As chunks the admin signs, on a
feed with sequential indices, the roster is verified end to end like every update, a
broker can relay it and not author it, and withholding it is a visible gap rather than
a silent edit. A single mutable slot would make a stale roster undetectable at the one
point that decides who may write.

**Why full state, not deltas.** A subscriber that joins late needs one roster, the
latest, and can verify it on its own; with deltas it would need the whole history, and
one lost delta would corrupt everything after it.

**Why a cohort is multi-publisher iff a roster is ever published.** A flag in the spec
would make "will this stream ever have guests" part of the cohort's identity, so that a
stream that adds a co-host halfway would be a different cohort with a different
audience. With the roster as the only signal, the spec stays SWIP-74's, every invite
stays valid, and the admin decides when it decides.

**Why roles change only by rejoining.** Rev 1 let a spectator a roster named
authenticate where it was, and turned a revoked publisher into a spectator in place.
Each in-place change is a transition the broker has to order against the frames in
flight: an `AUTH` racing the roster that permits it, an update racing the roster that
forbids it, a demoted stream that needs a place in a fan-out set that may be full. With
roles fixed at `Join` and by the `AUTH`, the only transition is SWIP-74's — pending to
publisher — and a grant or a revocation is a new stream or a closed one. What it costs
is a rejoin per grant or revocation: one round trip, one challenge, and the `AUTH` the
grantee signs anyway.

**Why the grantee waits for the roster.** A pending stream exists only for an address the
broker holds rostered, so the broker can accept its `AUTH` at once; but a peer that joins
before the broker has the roster — told of its grant out of band, or attached in
multihop to a hop the roster has not yet reached — gets a spectator stream, and its
`AUTH` there is a violation. The cue makes the peer's knowledge and the broker's
coincide: the roster that names it, delivered on the stream it means to authenticate.
And in multihop the cue is enough, because rosters travel outward from the root: a hop
that has delivered a roster has every hop inward of it holding the same roster or a
later one, so the grantee's updates are admitted all the way in.

**Why no grace on revocation, and why the revoked frame is dropped, not punished.** SWIP-60
rev 13 tolerated a revoked publisher's frames for a period after the reduced roster had
been written to its stream, then punished them. The window guesses when the peer has read
the roster, which the broker cannot learn — a write that returns says the frame is in the
transport's buffer, not that anyone read it — and the punishment is wrong in multihop,
where the frames of a revoked publisher keep arriving from relays that have not yet seen
the roster and are honest. Closing the revoked stream ends the question on a direct
link; dropping what arrives by an address no longer admitted ends it on every link.
Neither needs a timer of the peer's; the flush deadline is the broker's, bounding how
long it spends writing to a peer that does not read.

**Why publisher streams receive.** With one publisher a publisher stream had nothing
to receive. With several, a co-host is part of the audience: a panel in which speakers
cannot hear each other is not a panel. Giving it its own subscriber stream would double
the streams per seat and split one identity across two roles; receiving on the stream
it publishes on keeps a seat to one stream, and the per-address bound keeps that stream
from buying deliveries outside the fan-out bound.

**Why cursors only for rostered addresses.** A cursor exists to order one publisher's
updates; a revoked address publishes nothing more, so its cursor guards nothing. Keeping
it would make the table grow with every address ever granted; dropping it bounds the
table by the roster, which the chunk size bounds in turn. A re-granted publisher
restarting at 0 at the broker loses nothing: it never reuses an index, and subscribers
hold their own cursors.

**Why an `EOS`, and why it is final.** A stream that ends by inactivity ends ten minutes
after it stopped, indistinguishable from a broken connection; the audience waits, then
guesses. A signed end tells everyone at once, attributably, and lets the broker free
the cohort. It is final for the channel rather than the session because a subscriber
cannot tell sessions apart: an end it was shown once is an end it can be shown again,
so the only `EOS` that cannot be misused is one that is true for good.

## Security considerations

SWIP-74's, extended. **The roster is the admin's word**: signed by the admin's key on a
feed with sequential indices, it can be withheld by a broker and not forged; a gap is
visible; a subscriber keeps its roster cursor across streams and sessions and so cannot
be rolled back. **The head of a feed is the broker's word**: a first-time subscriber has
no cursor, and a broker colluding with a revoked publisher can present an earlier roster
as the latest to it, and that publisher as current, until a later roster is delivered —
the residual, stated. The id binds the topic and the owner, not the whole spec: an admin
SHOULD NOT run two specs on one topic, since a broker that carried one can deliver its
rosters and its end of stream into the other.

**Authorship rests on the message signature; the `AUTH` decides only who is carried as a
publisher.** Every update is validated at the broker against the address its stream
authenticated as, and again by every subscriber against the set of owners the admin's
latest roster admits.

Replay, SWIP-74's table extended by these rows:

| replayed | by whom | where | result | stopped by |
|---|---|---|---|---|
| an `AUTH` passed off as an `EOS` — both empty, at index 0 — or any kind as another | the broker | a subscriber | refused | the kind byte is in the prefix |
| a service chunk signed by anyone but the admin — a rostered seat, the broker's own key | anyone | the broker, a subscriber | a violation; refused | for every kind but `DATA` the owner is forced to the admin |
| an earlier session's `ROSTER` | a broker that carried it | a subscriber | dropped below the roster cursor; a first-time subscriber can be shown it as the latest | roster indices never reused; the roster cursor kept per `(topic, admin)`; the residual stated |
| an earlier session's `EOS` | a broker that carried it | a subscriber of a later run on the same channel | accepted — and true: the channel is ended | an `EOS` ends the channel, not a session |
| rosters or an `EOS` of another spec on the same topic and admin | a broker that carried it | a subscriber | accepted | nothing on the wire: an admin SHOULD NOT run two specs on one topic |
| a grantee's updates, after its revocation | a broker | a subscriber | refused: the owner is no longer admissible | the reduced roster precedes them; the subscriber admits against the roster it holds |
| a revoked publisher's frames | the revoked peer, or a relay behind the roster | its stream, or a relay link | dropped unread, counted; the revoked stream closed | revocation closes the stream; nothing it sends is accepted |
| a `Join` declaring a rostered address, from throwaway peer ids | a Sybil | a full cohort | a pending stream each: the roster, nothing else, then the auth deadline | pending streams are outside the fan-out bound; streams per connection per cohort are bounded |
| an `AUTH` | a spectator, rostered since its `Join` or not | its stream | a violation | an `AUTH` is accepted on a pending stream only; a grantee rejoins |
| a seat's updates from more streams than the bound | the seat's key, from many nodes | this broker | the oldest stream is reset at each `AUTH` beyond two | publisher streams per address are bounded |

**No confidentiality**, as in SWIP-74: the roster is plaintext, and with it the set of
addresses that may publish. An admin that must not disclose its grantees does not grant
on a public broker.

## Conformance (definition of done)

An implementation is SWIP-87 conformant when it is SWIP-74 conformant, items 1–3, 7, 8
and 11 unchanged, and:

1. a `Join` declaring the admin's or a currently rostered address is admitted outside the
   fan-out bound as a pending stream; one declaring a rostered address receives the
   latest roster at once, and nothing else before its `AUTH`; every other `Join` is a
   spectator stream within the bound;
2. a `Broadcast` is accepted iff it arrives on a publisher stream — `ROSTER` and `EOS`
   on the admin's only — or is an `AUTH` on a pending stream whose identity is the
   admin's or rostered; a frame from a spectator stream is a violation, whatever a later
   roster says; its kind is one of the four; its challenge is
   the stream's; its index is at least its feed's cursor — a `DATA`'s publisher's, a
   `ROSTER`'s the roster cursor — and an `AUTH` and an `EOS` are at index 0; and its
   chunk has the id derived from the frame and validates at `keccak256(id ‖ owner)`,
   the owner forced to the admin for `ROSTER` and `EOS` and the stream's identity for
   `DATA` and `AUTH`; a `ROSTER` whose payload does not decode is dropped and counted
   and changes nothing;
3. an accepted `DATA` is delivered unchanged to every receiving stream — spectator or
   publisher — not bound to the publishing identity, and an accepted `ROSTER` or `EOS`
   to every receiving stream but the one it came on; the latest roster is the first
   delivery on a stream when it starts receiving, unless the stream was given it as its
   cue;
4. an accepted `ROSTER` replaces the broker's roster, is enqueued at once on every
   pending stream it names, and revokes every publisher or pending stream of an address
   it drops: that roster is written to it, then it is closed; a frame from a revoked
   stream is dropped and counted, never a violation; the cursors of dropped addresses
   are forgotten;
5. an accepted `EOS` is delivered to every receiving stream but the sender, after which
   the cohort is forgotten and every stream closed once its queue is written, within
   the flush deadline;
6. the broker keeps a cursor per publisher — the admin and the rostered addresses — and
   one per service kind; a publisher's `DATA` below its cursor and a `ROSTER` below the
   roster cursor are retransmits;
7. an `AUTH` beyond the publisher streams one address may hold resets the oldest of
   them;
8. a subscriber verifies every delivery end to end: service chunks at the admin's
   address, `DATA` by recovering the owner and admitting it against the admin and the
   latest roster it has accepted; it keeps its cursor per publisher and per service kind
   across streams and sessions, drops what is below them, treats an `EOS` as the
   channel's end, and resets the stream on a delivery that does not validate or whose
   owner it does not admit;
9. a grantee publishes only on a stream it joined after seeing the roster that names it,
   and sends its `AUTH` there only after that roster has been delivered on it; a peer
   whose address a roster drops stops publishing; every publisher signs every chunk under its stream's
   challenge, and never reuses a `DATA` index; the admin never reuses a roster index;
10. the broker counts `invalid_roster` and `revoked` next to SWIP-74's counters;
11. a SWIP-87 broker, an admin, two grantees and subscribers from independent
    implementations interoperate through a grant, a revocation and an `EOS`.

## Out of scope (deliberately)

The `ALL` regime, `closed` cohorts and the silent role, `history`, the bindings other
than `FEED_TOPIC`, implicit authorship (all SWIP-60); multihop
([SWIP-61](https://github.com/ethersphere/SWIPs/pull/105)); self-indexed payloads and gap
recovery ([SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)); bandwidth
incentives; broker discovery; confidentiality.

## Backwards compatibility

Extends SWIP-74 by two `Kind` values and one message, both SWIP-60's; changes no frame,
field or value. A cohort that never uses them is a SWIP-74 cohort. SWIP-74 subscribers
in a cohort whose admin grants reset at the first grantee's update — see *Relation to
SWIP-74 and SWIP-60*.

## References

Base: [SWIP-74 BPS-lite, PR #111](https://github.com/ethersphere/SWIPs/pull/111)
· full singlehop protocol: [SWIP-60, PR #104](https://github.com/ethersphere/SWIPs/pull/104)
· multihop: [SWIP-61, PR #105](https://github.com/ethersphere/SWIPs/pull/105)
· self-indexed feeds: [SWIP-65, PR #106](https://github.com/ethersphere/SWIPs/pull/106)
· implementation: bee [#5626](https://github.com/ethersphere/bee/pull/5626) (BPS-lite)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
