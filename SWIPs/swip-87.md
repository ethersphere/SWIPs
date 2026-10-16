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
Rev 3 (2026-10-16), after an adversarial review: a grant upgrades in place again — a
grantee joins as a spectator, receives, and authenticates where it is once a roster
naming it has been delivered there; a rostered address can also just listen, and the
client never has to guess its role; pending is the admin's, and a rostered identity's
only past a full fan-out set; revocation still closes. A `ROSTER` and an `EOS` are delivered back to their sender. An `EOS` ends the
cohort at once: every stream is told, pending ones included, and nothing more is read.
The admin republishes its roster on every new stream. Open points are marked (?). -->

- **Business line**: a live stream with more than one voice — a panel, a co-hosted show,
  a band jamming, a newsroom ticker with several editors, a game whose server is
  replicated — under one author who decides, at any moment and visibly to everyone,
  who else may speak; and a stream that can be **ended**, attributably, instead of
  going quiet.
- **Dev line**: on top of SWIP-74, two more kinds on the same `Broadcast` frame —
  `ROSTER` and `EOS`, the admin's service feeds — one payload message, `Roster`, and the
  broker and subscriber rules they need: grantees upgrading their stream in place after
  the roster cue, a cursor per publisher, delivery to publisher streams, revocation by
  roster, the end of a channel. **No new frame, no new field in `Join` or `Ack`, no change to the cohort
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
others publish. A grantee needs no new stream: it listens like anyone, and once a roster
naming it arrives, its `AUTH` upgrades the stream it holds. A roster that drops an
address closes that address's publisher streams once the reduced roster has been written
to them; what they send meanwhile is dropped, not punished. The admin can also end the
channel with an
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
| **grant**, **revocation** | the admin adding or removing an address by publishing the next roster; a grant takes effect at the grantee's `AUTH`, sent on a stream the roster has reached, which it upgrades in place; a revocation when the broker accepts the reduced roster, which closes the revoked publisher streams |
| **role** | **pending stream** — declared the admin's address, not yet authenticated: outside the fan-out bound, receives nothing, sends nothing but its `AUTH` (SWIP-74). **Spectator stream** — any other identity, rostered or not: receives every delivery; sends nothing but, once a roster naming its identity has been delivered on it, its `AUTH`, which upgrades it. **Publisher stream** — authenticated: sends publications and heartbeats and, if it is the admin's, service messages; **receives every delivery not its own**. **Revoked stream** — a publisher stream whose address a roster dropped: written that roster, then closed; nothing it sends is read. **Ended stream** — any stream of a cohort an `EOS` ended: written the `EOS`, then closed; nothing it sends is read |
| **receiving stream** | a spectator or a publisher stream: one that deliveries are enqueued on |
| **fan-out set** | the spectator streams of a cohort, bounded per cohort — a rostered identity is admitted past the bound; publisher streams receive outside it, bounded per address |
| **delivery** | an accepted frame forwarded unchanged: a `DATA` to every receiving stream whose declared identity is not the author's, a `ROSTER` or `EOS` to every receiving stream, its sender's included |
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
                        // authenticates a pending stream, or a spectator stream a
                        // delivered roster names; a heartbeat on a publisher
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
are empty chunks at index 0. Each kind counts its own indices.

**A cohort is multi-publisher iff its admin ever publishes a roster.** Until it does, the
admin is the only publisher and the cohort is a SWIP-74 cohort, frame for frame. Nothing
in the spec announces it, so no one has to know in advance, and an audience joining a
live stream does not learn the cohort's future from its invite.

**The roster is full state.** Each `ROSTER` names every address that may publish besides
the admin; an address it does not name is not a publisher, whatever an earlier one said.
Entries are 20 bytes each; an entry equal to the admin's address, and a repeated entry,
change nothing. The chunk's payload bounds a roster to what fits in 4096 bytes — 186
addresses. A gap in the roster indices is therefore not a fault: the latest roster says
everything the missing ones did. The admin MUST NOT reuse a roster index across
sessions: a subscriber cannot tell sessions apart, and its roster cursor is what keeps
an earlier roster from standing in for a later one.

**The admin republishes its roster on every new stream.** A broker's roster lives as
long as its cohort, and a cohort is reclaimed by inactivity, forgotten at a restart, and
created afresh by whichever `Join` comes first — so an admin that has a roster MUST
publish it, at its next roster index, right after the `AUTH` on every publisher stream
it opens. A roster is full state, so publishing the same set again changes nothing at a
broker that already has it, and restores it at one that does not; without it every
grantee would be locked out of a fresh cohort until the admin next changed the roster.

**An `EOS` ends the channel, not a session.** A subscriber compares a frame's challenge
with nothing, so the end of any session of the channel is as good to it as this one's:
an admin that means to publish again after an `EOS` MUST take another topic.

### Roles

A stream's role is settled by its declared `identity` against the principal, by the
roster, and by its `AUTH`. Only an upgrade happens in place; a revocation closes.

| `identity` | at `Join` | the `AUTH` | anything else |
|---|---|---|---|
| the admin's | **pending**, outside the fan-out bound, receives nothing (SWIP-74) | upgrades it to a **publisher stream**, which receives the latest roster first, then every delivery not its own | violation (`wrong_stream`) |
| any other | **spectator**, within the fan-out bound; receives the latest roster first, then every delivery | a violation, until a roster naming the identity has been accepted and delivered on the stream; then it upgrades it to a **publisher stream** in place | violation (`wrong_stream`) |
| rostered, the fan-out set full | **pending**, outside the bound: receives the roster that names it at once, and nothing else | upgrades it to a **publisher stream**, as for the admin; without it by the auth deadline the stream is reset, not blocklisted | violation (`wrong_stream`) |

**A grant takes effect at the grantee's `AUTH`, on the stream the roster reached.** A
grantee joins like anyone — rostered or not yet — and listens. When a roster naming its
address is delivered on its stream, it may send its `AUTH` there, and the broker
accepts it iff the identity is rostered when the `AUTH` arrives: the stream becomes a
publisher stream, leaves the fan-out set, and goes on receiving. Nothing is re-sent; the
stream has the roster already. A rostered address that never authenticates is a
spectator like any other: it may simply listen, and no deadline applies to it. Only when
the fan-out set is full is a rostered identity's `Join` admitted past it, and then as a
**pending** stream — the roster that names it, nothing else, and the auth deadline —
because a roster is public: were a rostered `Join` admitted past the bound as a
spectator, anyone could open any number of streams under a grantee's address and be fed
past the bound. A pending stream of a rostered identity that does not authenticate in
time has cost the broker what a `FULL` would have, and is reset without a blocklist.

**The roster is the cue.** A peer other than the admin MUST NOT send its `AUTH` on a
stream before a roster naming its address has been delivered **on that stream**. The
broker has accepted any roster it delivers, so an `AUTH` sent after the cue is never
early. It is what keeps a grantee from authenticating at a broker that does not yet hold
the roster — one it was told about out of band, or in multihop (SWIP-61) a hop the
roster has not reached: there an `AUTH` from a spectator no roster names is a violation.
In multihop the cue is enough, because rosters travel outward from the root: a hop that
has delivered a roster has every hop inward of it holding that roster or a later one.
The admin needs no cue.

**An `AUTH` that races its revocation is not punished.** A spectator that sent its `AUTH`
after the roster naming it, but whose identity a later roster dropped before the `AUTH`
arrived, was honest: the broker closes the stream — it is a **revoked stream** — and
drops the `AUTH` (`revoked`). The peer rejoins to listen. An `AUTH` from a spectator that
no roster has ever named on that stream is a violation.

### Validation

The broker keeps, per cohort, a **cursor per publisher** — the lowest `DATA` index it
accepts next from that address, initially 0 — for the admin and every currently rostered
address, and a **cursor per service kind**, the **roster cursor**, initially 0, and the
**`EOS` cursor**, which an accepted `EOS` sets past 0 and so ends the cohort. A
`Broadcast` arriving at the broker is accepted iff, in order — SWIP-74's steps,
extended:

0. it did not arrive on a **revoked or ended stream** — a frame from one is dropped
   unread and counted (`revoked`, `ended`), never a violation: it was sent before the
   peer read the roster or the `EOS` that closed the stream;
1. it arrived on a **publisher stream** — and, if its kind is `ROSTER` or `EOS`, on the
   **admin's** — or it is an `AUTH` on a **pending stream**, or on a **spectator stream
   whose identity the roster names** (one whose identity a roster named on that stream
   but the latest no longer does is revoked, as above); any other frame is a protocol
   violation: dropped, counted (`wrong_stream`), the stream reset, the peer blocklisted
   per the node's policy;
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
   `ROSTER` and `EOS` and the stream's declared `identity` for `DATA` and `AUTH`. An
   `AUTH` or an `EOS` chunk moreover has span 0 and no payload. A failure is a protocol
   violation (`invalid_soc`);
6. for `ROSTER`, the payload **decodes as a `Roster`** of 20-byte entries — otherwise the
   frame is dropped and counted (`invalid_roster`), moves no cursor and changes nothing.
   The chunk is validated before its payload is read: an admin-signed chunk that does
   not decode is the admin's mistake, not a forgery.

Then, by kind:

- **`AUTH`** — upgrades a pending stream, or a spectator stream the roster names, to a
  publisher stream; on a publisher stream it is a heartbeat. It is never delivered,
  moves no cursor, and counts as activity. A pending stream that upgrades receives the
  latest roster as its first delivery; a spectator has it already.
- **`DATA`** — sets its publisher's cursor to `n + 1` and is delivered.
- **`ROSTER`** — sets the roster cursor to `n + 1`; its set **replaces** the broker's;
  it is delivered — to its sender too — and enqueued on every pending stream it names;
  every publisher or pending stream whose `identity` it no longer names is **revoked**
  (below); the cursors of addresses it no longer names are forgotten.
- **`EOS`** — **ends the cohort at once**: it is delivered to every receiving stream —
  its sender's too — and enqueued on every pending stream; every stream of the cohort
  becomes an **ended stream**, from which nothing more is read; the broker forgets the
  cohort and closes every stream once its queue — the `EOS` last — has been written,
  within the **flush deadline**. A `Join` arriving meanwhile names a cohort that no
  longer exists, and creates a fresh one.

**Delivery.** An accepted `DATA` frame is enqueued, unchanged, on **every receiving
stream whose declared identity is not the author's** — spectators included. A publisher
never gets its own updates back, on whichever of its streams they were sent; it receives
everybody else's — which is what a publisher stream adds to SWIP-74, where it received
nothing. An accepted `ROSTER` or `EOS` is enqueued on **every receiving stream, its
sender's included**: where it lands in a stream is where it took effect in that
stream's order, which is what every receiver admits by — the admin included, whose own
stream may still be delivering an update the broker accepted from a grantee just before
the roster that revoked it.

**The latest roster is the first delivery** on every stream as it starts receiving — at
attach for a spectator, at its `AUTH` for the admin's pending stream — before any other
frame. A cohort whose admin has published no roster delivers nothing first. So a
joiner learns who may write from the admin, not from the broker, before it receives a
single update.

**Cursors are per address, never per stream or per session**, as in SWIP-74: a
publisher holding two streams — two nodes, or a reconnect — is arbitrated by its one
cursor. The table holds the admin and the rostered addresses and nothing else, so it
is bounded by the roster. A revoked address's cursor is forgotten; if a later roster
names it again, the broker's cursor for it starts at 0 — harmless, since a publisher
never reuses a `DATA` index, and every subscriber keeps its own cursor per publisher.

### Revocation

**A revocation takes effect when the broker accepts the roster that makes it, and it
closes the revoked publisher streams.** At that moment every publisher or pending
stream bound to the revoked address becomes a **revoked stream**: the reduced roster is
written to it — delivered to a publisher stream like to every receiving stream, enqueued
on a pending one — and once its queue is written the broker **closes** it,
within the flush deadline, and resets it if the peer does not take it in time. Nothing
the stream sends after the revocation is read for its content: a frame from a revoked
stream is **dropped and counted (`revoked`), never a violation**. There is no grace
period and no timer of the peer's: receiving the reduced roster is the notice, and the
close is the enforcement. A spectator of the revoked address that has not authenticated
is left alone: it may go on listening, and is revoked only if it sends the `AUTH` it no
longer may.

The peer reads the roster that dropped it, then the end of its stream, and rejoins as
a spectator if it means to keep listening. A peer SHOULD close its stream on reading a
roster that drops it, which spares the broker the flush.

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
  roster it has received — the admin too admits by the rosters delivered to it, never
  by those it has only sent;
- it keeps a **cursor per publisher** and a **cursor per service kind** — the roster
  cursor and the `EOS` cursor — per `(topic, admin)`, **across streams and sessions**,
  and drops what is below them; a roster at or above the roster cursor replaces its
  admissible set; an `EOS` sets the `EOS` cursor past 0 and the subscriber treats the
  channel as ended — a channel it has seen end it does not rejoin;
- it drops an `AUTH` and a kind it does not know;
- a peer that sees its address on a roster delivered on its stream may send its `AUTH`
  there; one that sees its address dropped stops publishing, and its publisher stream
  is closed;
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
admin's, attributable, final. On accepting an `EOS` the broker ends the cohort at once —
every stream is told, the pending ones and the sender's included, and nothing more is
read from any — then forgets it, closing every stream once its queue has been written.
A subscriber that accepts an `EOS` treats the channel as ended; it can tell "over" from
"paused", which in SWIP-74 only the application could. A peer whose stream is closed
after an `EOS` does not rejoin the cohort; a later `Join` of the same spec creates a
fresh cohort, which a subscriber holding the `EOS` cursor refuses to treat as the same
channel.

An `EOS` is the only clean way to disconnect a cohort: everything else that ends one —
the inactivity deadline, a reset, a broker restart — looks to the audience like a
fault. A peer whose stream is closed after an `EOS` has read the `EOS` first, unless it
did not take its queue within the flush deadline.

### Resource bounds

SWIP-74's bounds, with these changes:

| bound | answer | recommended |
|---|---|---|
| subscriber streams per cohort — the fan-out set | `FULL` to the next `Join` — except a `Join` declaring the admin's or a rostered address, admitted outside the bound as a pending stream | implementation-defined |
| **publisher streams per address** per cohort — publisher streams receive outside the fan-out bound, so one key holding many would buy deliveries past it | an `AUTH` that would exceed it is accepted and resets the **oldest** of that address's publisher streams | 2 — one live stream and one reconnecting |
| the outbound queue | per **receiving** stream, spectator or publisher; a full queue resets that stream | 64 frames |
| **flush deadline** — a stream being closed, by an `EOS` or a revocation, has its queue written within it, counted from the close, a write in progress included | reset | 5 s (?) |

A rostered address costs the broker, past a full fan-out set, what the admin's does: a
pending stream receiving one frame, for one auth deadline, bounded per peer connection
and cohort; and, authenticated, a cursor and at most two publisher streams. The roster
bounds the table of cursors.

### Outcomes

Every frame the broker receives ends in exactly one of the outcomes below — SWIP-74's,
with this SWIP's rows. The wire carries no error frame.

| what arrived | from | outcome | counter | the sender sees |
|---|---|---|---|---|
| a `Join` with a spec value outside SWIP-74 or an `identity` that is not 20 bytes | anyone | `Ack{REJECTED}`, stream closed | — | `REJECTED` |
| a `Join` at a capacity bound | anyone but the admin's or a rostered identity | `Ack{FULL}`, stream closed | — | `FULL` |
| a `Join` declaring the admin's identity when the fan-out set is full | the admin's node | admitted as a pending stream outside the bound | — | `OK` and a challenge |
| a `Join` declaring a rostered identity when the fan-out set is full | its node | admitted as a pending stream outside the bound, given the roster at once | — | `OK`, a challenge, the roster |
| any `Broadcast` but an `AUTH` | a spectator stream | violation | `wrong_stream` | the stream is reset |
| an `AUTH` | a spectator stream no roster has named on that stream | violation | `wrong_stream` | the stream is reset |
| an `AUTH` | a spectator stream a roster named there, whose identity the latest no longer names | dropped; the stream closed | `revoked` | the stream is closed |
| anything but an `AUTH` | a pending stream | violation | `wrong_stream` | the stream is reset |
| a `ROSTER` or an `EOS` | any stream but the admin's publisher stream | violation | `wrong_stream` | the stream is reset |
| any frame | a revoked stream | dropped unread | `revoked` | nothing; the stream is closed |
| any frame | an ended stream | dropped unread | `ended` | nothing; the stream is closed |
| a kind this SWIP does not define | a publisher stream | dropped | `unknown_kind` | nothing |
| a frame whose challenge is not the stream's | a publisher stream, or an `AUTH` on a stream that may authenticate | dropped; the broker MAY reset the stream | `wrong_challenge` | nothing, or a reset |
| a `DATA` below its publisher's cursor, or a `ROSTER` below the roster cursor | a publisher stream | dropped | `retransmit` | nothing |
| a chunk whose id is not the one derived from the frame, or that does not validate at the address formed from the id and its owner; an `AUTH` or `EOS` with a payload or not at index 0; an index of 2⁶⁴−1 | a stream that may send that kind | violation | `invalid_soc` | the stream is reset |
| a `ROSTER` that validates but does not decode as a `Roster` | the admin's publisher stream | dropped; no cursor moves | `invalid_roster` | nothing |
| no `AUTH` within the auth deadline | a pending stream | stream reset — the admin's peer blocklisted for a short time, a rostered one not; an `AUTH` arriving after is not accepted | `auth_timeout` | the stream is reset |
| a valid `AUTH` | a pending stream, or a spectator stream the roster names | upgraded to a publisher stream; a pending one receives the latest roster first; activity; beyond the per-address bound the oldest publisher stream of the address is reset | — | nothing |
| a valid `AUTH` | a publisher stream | activity, nothing else | — | nothing |
| a valid `DATA` at or above its publisher's cursor | a publisher stream | cursor set past it; delivered to every receiving stream whose identity is not the author's | — | nothing |
| a valid `ROSTER` at or above the roster cursor | the admin's publisher stream | roster cursor set past it; the roster replaces the broker's; delivered to every receiving stream, the sender's included, and to every pending stream it names; publisher and pending streams of addresses it drops revoked — written the roster, then closed; their cursors forgotten | — | the roster, delivered back |
| a valid `EOS` | the admin's publisher stream | the cohort ended: delivered to every receiving stream and every pending one, every stream ended, the cohort forgotten, every stream closed once its queue is written | — | the `EOS`, then the stream is closed |
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
  default, or a **seat**: an address the owner's roster names, or will. The node joins
  and sends the challenge as JSON — `challenge`, `dataTopic`, `authTopic`, and to the
  owner also `rosterTopic` and `eosTopic` — and from then on delivers what the stream
  receives, in the subscribe socket's frame format: a seat's stream listens from the
  start, the owner's once authenticated, and the owner receives its own rosters back.
  When a roster naming a seat has reached its stream, the node sends
  `{"type":"granted"}`; the seat may then send its `AUTH`, and anything a seat sends
  before is refused (4002). The dApp sends binary frames `kind (1) ‖ index (8) ‖ soc`:
  `DATA` and `AUTH` signed by the identity, `ROSTER` and `EOS` signed by the owner and
  accepted from the owner's socket only (4002 from a seat's, and for a roster that does
  not decode). The `AUTH` comes first — for the owner within the node's auth deadline,
  shorter than the broker's, for a seat within the same span of the grant. The roster
  travels on the owner's publish socket rather than a socket of its own, because the
  wire requires it on the admin's publisher stream, and a second socket would hold a
  second one.
- **`GET /bps/subscribe/{owner}/{topic}?broker&identity&cursor`** — every verified
  delivery as a binary frame `kind (1) ‖ owner (20) ‖ challenge (32) ‖ index (8) ‖
  soc`: `DATA` by the owner or a seat, `ROSTER` and `EOS` by the owner. The owner and
  the kind let the dApp re-verify every chunk itself, and the rosters let it show who
  may speak. A rostered `identity` may subscribe: it listens like any spectator. After
  an `EOS` both sockets close with 4004.
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
`EOS` are dropped as `unknown_kind`, and a grantee's stream is a subscriber stream there,
reset at its `AUTH` — but a conforming grantee never sends one, since no roster is ever
delivered to it: an admin that grants needs a SWIP-87 broker.

**To SWIP-60, a subset.** Everything here is SWIP-60's explicit authorship on a
`FEED_TOPIC` cohort without `publishers`, `closed` or `history`: the same kinds, the
same `Roster`, the same roles but the silent one, the same validation. SWIP-60 adds the
`ALL` regime, `closed` and the silent role, `history`, the other bindings, implicit
authorship and its API. Rules here to be carried back to it: pending is the admin's alone
— a rostered identity joins as a spectator, admitted past the fan-out bound, and
upgrades in place after the roster cue; revocation closes the revoked publisher streams
and drops their frames unpunished, with no grace period; a `ROSTER` or `EOS` is
delivered back to its sender; an `EOS` ends the cohort at once, pending streams told;
the admin republishes its roster on every new stream; and the cursor table is bounded
by the roster.

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

**Why a grant upgrades in place and a revocation closes.** Rev 2 made both go through
the stream: a grantee rejoined to publish, a revoked peer was closed. The revocation
half was right and stays — frames already in flight cannot be taken back, so the stream
must close and its frames be dropped, not punished. The grant half cost more than it
saved. A grantee needed a second stream and a round trip; while it switched, it heard
nothing; a rostered address could not simply listen, because declaring it made a
pending stream that received nothing and timed out; and the client had to infer from
the order of deliveries whether its stream was pending or a spectator — which it got
wrong whenever the grantee joined before the broker held a roster, the ordinary startup
order. Upgrading in place has none of these, and the race it seemed to invite — an
`AUTH` overtaking the roster that permits it — cannot happen: a peer sends its `AUTH`
only after the roster has been delivered on that stream, by a broker that had accepted
it first. The asymmetry is principled: a grant adds a right, and the broker can wait
for the peer to use it; a revocation removes one, and must not wait for anything.

**Why the grantee waits for the roster on its own stream.** Knowing it is rostered is not
enough: the broker it is attached to may not hold the roster yet — the peer was told out
of band, or in multihop it is attached to a hop the roster has not reached — and an
`AUTH` from a spectator no roster names is a violation. The roster delivered on the
stream makes the peer's knowledge and that broker's coincide. In multihop the cue is
enough, because rosters travel outward from the root: a hop that has delivered a roster
has every hop inward of it holding the same roster or a later one, so the grantee's
updates are admitted all the way in.

**Why a roster is delivered back to its sender.** Every receiver admits updates by the
latest roster it holds, and an update and a roster are ordered only within a stream.
The admin's own stream may be carrying a grantee's update that the broker accepted just
before the roster revoking it; an admin that adopted the roster when it sent it would
see that update after its own revocation, and take an honest broker for a forging one.
The roster echoed into its stream marks exactly where it took effect, there as
everywhere.

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
| a `Join` declaring a rostered address, from throwaway peer ids | a Sybil | a full cohort | a pending stream each: the roster, nothing else, then the auth deadline | past a full set a rostered identity is pending, not a spectator; streams per connection per cohort are bounded |
| a `Join` declaring the admin's address, from throwaway peer ids | a Sybil | a full cohort | a pending stream each: nothing, then the auth deadline | SWIP-74's pending-stream bounds |
| an `AUTH` | a spectator no roster has named on that stream | its stream | a violation | an `AUTH` on a spectator is accepted only once the roster names it |
| an `AUTH` sent after the roster naming it, overtaken by the roster revoking it | an honest grantee | its stream | dropped; the stream closed | the `AUTH` is accepted iff the identity is rostered when it arrives |
| a seat's updates from more streams than the bound | the seat's key, from many nodes | this broker | the oldest stream is reset at each `AUTH` beyond two | publisher streams per address are bounded |

**No confidentiality**, as in SWIP-74: the roster is plaintext, and with it the set of
addresses that may publish. An admin that must not disclose its grantees does not grant
on a public broker.

## Conformance (definition of done)

An implementation is SWIP-87 conformant when it is SWIP-74 conformant, items 1–3, 7, 8
and 11 unchanged, and:

1. a `Join` declaring the admin's address is admitted outside the fan-out bound as a
   pending stream; every other `Join` is a spectator stream within the bound, whose
   first delivery is the latest roster — except one declaring a rostered address when
   the set is full, admitted as a pending stream that is given the roster at once,
   nothing else, and is reset without a blocklist if it has not authenticated by the
   auth deadline;
2. a `Broadcast` is accepted iff it arrives on a publisher stream — `ROSTER` and `EOS`
   on the admin's only — or is an `AUTH` on a pending stream, or on a spectator stream
   whose identity the latest roster names; an `AUTH` on a spectator stream a roster had
   named there but the latest no longer does is dropped and the stream closed; any
   other frame from a spectator stream is a violation; its kind is one of the four; its
   challenge is the stream's; its index is at least its feed's cursor — a `DATA`'s
   publisher's, a `ROSTER`'s the roster cursor — and an `AUTH` and an `EOS` are at index
   0; and its chunk has the id derived from the frame and validates at
   `keccak256(id ‖ owner)`, the owner forced to the admin for `ROSTER` and `EOS` and the
   stream's identity for `DATA` and `AUTH`; a `ROSTER` whose payload does not decode is
   dropped and counted and changes nothing;
3. an accepted `DATA` is delivered unchanged to every receiving stream whose declared
   identity is not the author's, and an accepted `ROSTER` or `EOS` to every receiving
   stream, the sender's included; the latest roster is the first delivery on a stream
   when it starts receiving;
4. an accepted `ROSTER` replaces the broker's roster and revokes every publisher stream
   of an address it drops: that roster is written to it, then it is closed; a frame
   from a revoked stream is dropped and counted, never a violation; the cursors of
   dropped addresses are forgotten;
5. an accepted `EOS` ends the cohort at once: it is delivered to every receiving stream
   and every pending one, nothing more is read from any stream of the cohort — a frame
   is dropped and counted — the cohort is forgotten, a `Join` meanwhile creates a fresh
   one, and every stream is closed once its queue is written, within the flush
   deadline, counted from the close;
6. the broker keeps a cursor per publisher — the admin and the rostered addresses — and
   one per service kind; a publisher's `DATA` below its cursor and a `ROSTER` below the
   roster cursor are retransmits;
7. an `AUTH` beyond the publisher streams one address may hold resets the oldest of
   them;
8. a subscriber verifies every delivery end to end: service chunks at the admin's
   address, `DATA` by recovering the owner and admitting it against the admin and the
   latest roster delivered to it — the admin's own included; it keeps its cursor per publisher and per service kind
   across streams and sessions, drops what is below them, treats an `EOS` as the
   channel's end, and resets the stream on a delivery that does not validate or whose
   owner it does not admit;
9. a grantee sends its `AUTH` on a stream only after a roster naming it has been
   delivered on that stream; a peer whose address a roster drops stops publishing; every
   publisher signs every chunk under its stream's challenge, and never reuses a `DATA`
   index; the admin never reuses a roster index, and publishes its current roster right
   after the `AUTH` on every publisher stream it opens;
10. the broker counts `invalid_roster`, `revoked` and `ended` next to SWIP-74's
    counters;
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
