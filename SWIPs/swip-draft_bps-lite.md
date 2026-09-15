---
SWIP: <to be assigned>
title: BPS-lite — single-publisher brokered broadcast
author: acud (@acud)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-09-14
---

<!-- A single-publisher profile of brokered broadcast pub/sub, specified standalone.
Companion: SWIP-60 "BPS singlehop" (PR #104), from which this takes its frames and
against which it deliberately diverges. The protobuf is inline in this document;
there is no companion asset file. -->

## Simple Summary

One broker, one publisher, many subscribers, one hop. A publisher opens a topic on a
broker and pushes single-owner chunks; everyone else connects and reads. Nothing else.

## Abstract

BPS-lite is a real-time broadcast protocol in which a cohort is a topic and a topic is
a single-owner chunk address. The peer that opens a cohort is its publisher for as long
as that stream lives; every other peer is a read-only subscriber. Authorship needs no
credential, no publisher list and no handshake authentication: under the `ANCHOR`
binding the topic already names the only key that can produce a chunk hashing to it, so
authorship is re-established from the signature on every message. The cohort's lifetime
is its publisher's stream, which removes orphan cohorts and bounds `Open` as an
allocation primitive.

It is a deliberate subset of the design space [SWIP-60][swip60] covers, specified as
its own document rather than as a profile: the wire format below is complete, and where
BPS-lite differs from SWIP-60 — most importantly in making `ANCHOR`'s address
constraint unconditional — BPS-lite's rule governs. No compatibility is claimed in
either direction.

## Motivation

SWIP-60 spans five cohort shapes, four topic bindings, four publisher regimes, an admin
control plane and a history flag. That parameter space is the right target for the
reference implementation and the wrong one for a second, independent implementation:
most of it is untested surface for anyone whose application is one author broadcasting
to an audience — a live feed, a price ticker, a game's server-authoritative state, a
log tail.

BPS-lite names the single point in that space which needs none of the machinery, and
shows that pinning it collapses the spec rather than merely constraining it. Three
questions SWIP-60 leaves open — the dedup horizon, cohort lifetime, and `Open` as an
unbounded allocation primitive — are answered here, and one property SWIP-60 claims
(`closed` as confidentiality over an unauthenticated handshake) is dropped rather than
restated. The result is a target roughly a tenth the size, which a second team can
implement and conformance-test without tracking the full spec's revisions.

## Specification

The key words MUST, MUST NOT, REQUIRED, SHOULD, RECOMMENDED and MAY are to be
interpreted as described in RFC 2119.

### Roles and topology

One broker node. One publisher peer. N subscriber peers. Every peer dials the broker
directly over a single libp2p stream per (peer, topic), protocol id
`pubsub/1.0.0` — the same id SWIP-60 uses, shared deliberately: see *Backwards
compatibility*. No relaying, no referral, no broker discovery: depth is 1 by
construction.

The publisher and the broker are distinct peers. Brokering for oneself is out of scope.

**The peer that opened a cohort is its publisher for as long as that stream lives.**
The role is a property of the stream, not of a field in the spec: subscriber streams are
read-only and the broker MUST NOT read `Publish` frames from them.

### Wire format

This section is normative and complete: BPS-lite is defined by the messages below and
by nothing else. No import, no companion `.proto`, no field inherited by reference.
Reserved field numbers are SWIP-60's, kept reserved so that a frame from a full-spec
implementation is refused rather than silently misread as a valid BPS-lite frame.

```proto
// BPS-lite — single-publisher brokered broadcast. Complete wire format.
//
// Enum zero values (*_UNSPECIFIED): proto3 requires a zero value; it is
// deliberately NOT a legitimate wire value. It exists so that an unset field is
// detectable and no implementation can silently rely on a default. Receivers
// MUST reject any message carrying one.

syntax = "proto3";

package bps;

// ---------------------------------------------------------------- cohort

// What the topic binds to. BPS-lite has exactly one binding: the topic is the
// full SOC address. Unlike SWIP-60 the constraint is unconditional — there is
// no publisher regime that can relax it.
enum TopicBinding {
  TOPIC_BINDING_UNSPECIFIED = 0; // invalid on the wire
  ANCHOR                    = 1; // topic = SOC address; dedup on the wrapped CAC
}

// Fixed by the cohort's opener; immutable for the cohort's lifetime.
// A cohort is a topic: there is no publisher field, because under ANCHOR the
// topic already names the only key that can author for it.
message CohortSpec {
  bytes        topic   = 1; // 32B: the SOC address, keccak256(id || owner)
  TopicBinding binding = 2; // must be ANCHOR
  reserved 3, 4, 5, 6, 7, 8; // SWIP-60: publishers, history, admin,
                             // publisher_list, po_min, closed
}

// ------------------------------------------------------------- handshake

// Opener -> broker: the one peer that fixes the cohort. The stream carrying
// this frame is the cohort's publisher for as long as it lives.
message Open {
  CohortSpec cohort   = 1;
  reserved 2;               // SWIP-60: auth. BPS-lite authenticates nothing at
                            // handshake time; authorship is checked per message.
  bool       loopback = 3;  // deliver the cohort's own Broadcast frames back
}

// Joiner -> broker: names the topic — nothing more. Subscriber streams are
// read-only; there is no role to claim here.
message Subscribe {
  bytes topic = 1; // 32 bytes
  reserved 2;      // SWIP-60: auth. A frame carrying it is REJECTED.
}

// Peer -> broker: the first frame on a fresh stream. Open and Subscribe are
// otherwise indistinguishable on the wire — both encode as a single
// length-delimited field 1, and proto3's permissive unmarshalling makes a
// wrong guess succeed silently.
message Hello {
  oneof handshake {
    Open      open      = 1;
    Subscribe subscribe = 2;
  }
}

enum Status {
  STATUS_UNSPECIFIED = 0; // invalid on the wire
  OK                 = 1;
  FULL               = 2; // broker at a capacity limit: subscribers, or cohorts
  UNKNOWN_TOPIC      = 3; // Subscribe for a topic with no live publisher
  REJECTED           = 4; // unacceptable spec, or a reserved field set
}

// Broker -> peer, answering Open or Subscribe. One per stream; a non-OK Ack
// ends the stream.
message Ack {
  Status     status = 1;
  CohortSpec cohort = 2; // set iff status == OK
}

// --------------------------------------------------------------- traffic

// A full single-owner chunk in transit. Every frame is self-contained.
message Soc {
  bytes id        = 1; // 32 bytes
  bytes owner     = 2; // 20 bytes
  bytes signature = 3; // 65 bytes
  bytes span      = 4; // 8 bytes LE
  bytes payload   = 5; // wrapped-CAC data, <= 4096 bytes
}

// Publisher -> broker. Accepted only on the stream that opened the cohort.
message Publish {
  Soc soc = 1;
}

// Broker -> peer.
message Broadcast {
  oneof frame {
    Soc soc = 1;
    // 2-15 reserved in SWIP-60 for the multihop control plane; BPS-lite is
    // singlehop and defines none of them.
  }
}
```

Everything after the handshake is direction-typed and needs no envelope: peer to
broker is always `Publish`, broker to peer is always `Broadcast`.

A cohort spec carries two live fields. There is no publisher field, no publisher
list, no publisher regime, no `history`, no `closed`, no `PO_MIN`. Per-topic capacity
is broker policy and is not on the wire at all.

`Open` carries no credential: nothing at handshake time can prove control of a key,
so BPS-lite does not ask. `Subscribe` carrying the reserved field 2 is `REJECTED` —
there is no second publisher to authenticate, and no role to claim at handshake time.

### Handshake

Publisher-first. The publisher fixes the cohort; subscribers join it.

```
publisher                              broker
 |  Hello{Open{spec, loopback}}         |
 |------------------------------------->|   validate spec; create cohort;
 |                                      |   this stream is the publisher
 |            Ack{OK, spec}             |
 |<-------------------------------------|
 |  Publish{soc} ...                    |
 |            Broadcast{soc} ...        |   iff loopback was requested
 |<-------------------------------------|

subscriber                             broker
 |  Hello{Subscribe{topic}}             |
 |------------------------------------->|   UNKNOWN_TOPIC if no publisher has opened
 |            Ack{OK, spec}             |
 |<-------------------------------------|
 |            Broadcast{soc} ...        |
```

Rules:

- A non-`OK` `Ack` ends the stream. On `OK` the stream is retained.
- A `Subscribe` carrying reserved field 2 (SWIP-60's `auth`) is `REJECTED`.
- **`Open` on a live topic with an identical spec transfers the publisher role to the
  new stream**: the broker answers `OK`, retains the cohort and its dedup window, and
  resets the previous publisher stream. A publisher recovering from a dropped
  connection therefore needs no distinct reattach frame, and a stale half-open stream
  closing later is not the current publisher stream and has no effect. An `Open` with
  a different spec for a live topic is `REJECTED`.
- A subscriber arriving before the publisher gets `UNKNOWN_TOPIC` and retries. The
  broker holds no pre-registration state.
- A peer receiving `UNKNOWN_TOPIC` or `FULL` MUST wait before retrying: randomized
  exponential backoff from 1s to 30s, full jitter. A broker MAY reset a stream from a
  peer that retries faster. Without this, every publisher restart resets N subscriber
  streams at once and they all return immediately.
- The publisher's own stream receives the cohort's `Broadcast` frames only if it asked
  for them (`Open.loopback`, default false). See *Capacity and slow peers* for why it
  is opt-in.

### Message validation

A `Publish` is accepted iff, in order:

1. it arrived on the stream that opened the cohort;
2. the `Soc` decodes and its signature recovers an owner;
3. the SOC address, `keccak256(id || owner)`, equals `spec.topic` — the `ANCHOR` rule;
4. the wrapped CAC's BMT root matches its payload;
5. the CAC address is not in the cohort's dedup window.

Failures 1–4 are protocol violations: the message is dropped, counted per peer, and
exposed through the implementation's invalid-message hook. Failure 1 additionally
resets the offending stream. No blocklisting is mandated. Failure 5 is ordinary — a
retransmitting publisher — and is counted separately.

Note what is *not* here: no comparison of the recovered owner against a declared
publisher. Under `ANCHOR` the topic is a SOC address, so step 3 already constrains the
owner — producing a SOC that hashes to `spec.topic` under a different key is a keccak
preimage. An owner check would be a second test that can only fail where step 3 has
already failed.

On acceptance the broker enqueues a `Broadcast` on every subscriber stream in the
cohort, and on the publisher's own stream if it requested loopback.

### Cohort lifetime

**A cohort exists exactly as long as its current publisher's stream.** When that
stream closes or resets, the broker destroys the cohort and resets every subscriber
stream. Subscribers reconnect and receive `UNKNOWN_TOPIC` until the publisher returns.
A stream that has been superseded by a role transfer is not the current publisher
stream: its later close is a no-op.

This is the largest simplification the single-publisher restriction buys. It removes
orphan cohorts and any reclamation policy, and it bounds `Open` as an allocation
primitive: a peer can hold only as many live cohorts as it holds open streams.

### Dedup

A bounded LRU of accepted CAC addresses, per cohort. Implementations MUST bound it;
1024 entries is RECOMMENDED. A role transfer retains the window.

Replay is prevented by the stream-role rule, not by the window: a captured `Broadcast`
re-`Publish`ed by an observer carries the genuine publisher's signature and passes
steps 2–4, but is refused at step 1 because it arrives on a subscriber stream —
whatever its age. The window bounds duplicate suppression for a retransmitting
publisher only, and 1024 is chosen against that benign case.

### Capacity and slow peers

Per-topic subscriber capacity is broker policy, not a cohort parameter. At the limit
the broker answers `FULL` and nothing else; referral is bps-multihop's business.
A broker MUST also bound the number of live cohorts it will create; the lifetime rule
above makes that bound enforceable, and an `Open` at that bound is answered `FULL`.

Each retained subscriber stream has a bounded outbound queue (64 frames RECOMMENDED)
drained by a single writer. A full queue resets that stream. The broker has no
delivery obligation: withholding is a recoverable liveness fault, not a correctness
failure, and blocking fan-out on one slow subscriber would punish the cohort.

The publisher's stream is exempt from that reset. It is the cohort's lifetime, so a
policy that is merely lossy for a subscriber is fatal for everyone: a publisher that
does not drain its own loopback echo — a fast publisher, a single-threaded client, a
bridge applying backpressure — would otherwise destroy its own cohort. A full queue on
the publisher's stream drops the frame and increments a counter. Loopback is opt-in for
the same reason.

Loopback is an echo of *accepted* messages, not delivery confirmation: rejected
`Publish` frames are dropped silently and produce no frame at all, so a publisher
cannot distinguish rejection from delivery by watching its echo. An acknowledged write
path would be an `Ack`-per-`Publish` design, which BPS-lite does not have.

### Status codes

| condition | status |
|---|---|
| handshake accepted | `OK` |
| broker at a capacity limit — per-topic subscribers for `Subscribe`, live cohorts for `Open` | `FULL` |
| `Subscribe` for a topic with no live publisher | `UNKNOWN_TOPIC` |
| unacceptable spec, differing spec on re-`Open`, a reserved field set | `REJECTED` |

A `STATUS_UNSPECIFIED` or any other zero enum value received on the wire is rejected:
the proto's zero values are deliberately not legitimate wire values.

## Rationale

### Authorship without a credential

BPS-lite has no publisher field and no handshake credential. A cohort's topic is a SOC
address; the only key that can produce a SOC hashing to it is the one that owns it.
Authorship is a property of the topic, established on the write path by step 3 and
re-checked on every message, and the handshake asserts nothing.

Two consequences worth stating. Anyone may `Open` any topic, including a topic whose
key they do not hold — but such a cohort can never accept a message, and the genuine
publisher's `Open` takes the role from them under the transfer rule above, so squatting
costs the squatter a stream and buys nothing. And BPS-lite makes no confidentiality
claim: broadcasts are readable by any subscriber, audience control is the application's
business, and SWIP-60's `closed` flag — which does make such a claim on an
unauthenticated handshake — is deliberately absent.

### Differences from SWIP-60

Non-normative, for readers arriving from the full spec. Three things differ:

- **No `PublisherRegime`, and no publisher set.** SWIP-60's `publishers`, `admin`,
  `publisher_list`, `history` and `closed` have no counterpart. `CohortSpec` is
  `{topic, binding}`.
- **`ANCHOR`'s address constraint is unconditional.** SWIP-60 relaxes it under an
  explicit publisher regime, where the topic becomes a rendezvous and legitimacy comes
  from list membership instead. BPS-lite has no list, so the constraint always applies.
  This is the trap for anyone reusing SWIP-60's `anchorBinding` unmodified: its
  explicit-regime early return would leave a BPS-lite cohort with no address check at
  all.
- **The publisher role is bound to the opening stream**, and transfers on re-`Open`.
  SWIP-60 leaves cohort lifetime and reattachment unspecified.

The first two are what make the spec small; the third is what makes it operable. Each
is a divergence, not a restriction: a SWIP-60 implementation pointed at a BPS-lite
cohort would accept messages BPS-lite refuses, and a SWIP-60 client's `Open` carries
fields BPS-lite reserves. Hence a separate document — but not a separate protocol id.
BPS-lite and SWIP-60 are two specifications of one protocol, `pubsub/1.0.0`, and a peer
dials it without knowing which it will meet. The first frame settles that: a BPS-lite
broker answers a SWIP-60 `Open` with `REJECTED`, because every field the fuller spec
adds is a field this one reserves. Refusal at the handshake is the compatibility story,
and it is why those numbers are reserved rather than reused.

### Why the publisher field is absent

Under `ANCHOR` the topic is `keccak256(id || owner)`. Comparing a message's recovered
owner against a declared publisher is then a test that can only fail where the address
check has already failed, short of a keccak preimage. Carrying the field would cost a
20-byte field, a validation step, an owner comparison on re-`Open`, and — because the
field is asserted and never proved — a paragraph explaining what it does not mean. The
topic does the work; the field is deleted.

### Why loopback is opt-in

The publisher's stream is the cohort's lifetime, so the queue-overflow policy that is
merely lossy for a subscriber is fatal for the whole cohort. A publisher that does not
drain its own echo would destroy what it is publishing to. Making the echo opt-in and
exempting that stream from the reset removes a failure mode that has no analogue on the
subscriber side.

## Backwards compatibility

BPS-lite introduces no incompatibility with any deployed protocol: Swarm has no
broadcast pub/sub in production.

It shares the `pubsub/1.0.0` protocol id with [SWIP-60][swip60] while **not** being
wire-compatible with it. That is a deliberate choice, and it puts the whole weight of
the compatibility story on the first frame of a stream:

- A SWIP-60 `Open` sets `CohortSpec` fields 3–8 and `Open` field 2, all of which
  BPS-lite reserves, so it is `REJECTED` rather than silently decoded with those fields
  dropped — which is what proto3's permissive unmarshalling would otherwise do, leaving
  a peer that asked for a five-author closed cohort holding an open single-publisher
  one. The reserved numbers are what make the refusal reliable, and they are the reason
  a BPS-lite broker MUST reject a frame carrying them rather than ignore it.
- A BPS-lite `Open` is a valid SWIP-60 `Open` — `{topic, binding}` with everything else
  unset. A SWIP-60 broker would accept it, and then not enforce the address constraint
  (see the next bullet). A BPS-lite publisher therefore gets weaker guarantees from a
  full-spec broker than from a conformant one, silently. Applications that depend on
  the `ANCHOR` rule should treat an unexpected `Ack` shape as a mismatch.
- BPS-lite's `ANCHOR` applies its address constraint unconditionally; SWIP-60 relaxes
  it under an explicit publisher regime. An implementation reusing SWIP-60 `ANCHOR`
  code unmodified would perform no address check at all under BPS-lite, which is the
  one silent failure this divergence can cause. It is called out again in *Differences
  from SWIP-60* above.

Should BPS-lite and SWIP-60 later converge, the reserved field numbers leave the
migration path open: a future revision can un-reserve them with their SWIP-60 meanings
intact.

## Test cases

An implementation is BPS-lite conformant if it exhibits all of:

1. `Open` with `binding != ANCHOR` → `REJECTED`.
2. `Open` carrying a reserved field, or a `CohortSpec` carrying one → `REJECTED`.
3. `Subscribe` carrying reserved field 2 → `REJECTED`.
4. `Subscribe` before any `Open` → `UNKNOWN_TOPIC`.
5. Re-`Open` on a live topic with an identical spec → `OK`; the prior publisher stream
   is reset; the cohort and its dedup window survive. A differing spec → `REJECTED`.
6. A superseded publisher stream closing after a role transfer → cohort unaffected.
7. Current publisher stream closes → every subscriber stream reset, topic subsequently
   `UNKNOWN_TOPIC`.
8. `Publish` whose SOC address is not `spec.topic` → dropped and counted.
9. `Publish` on a subscriber stream → dropped, counted, and that stream reset.
10. A duplicate CAC within the dedup window → dropped, counted separately.
11. Subscriber arriving at per-topic capacity → `FULL`, with no referral frame. `Open`
    at the live-cohort bound → `FULL`.
12. Publisher stream outbound queue full → frame dropped, stream retained, cohort alive.
13. `Open` without `loopback` → the publisher receives no `Broadcast` frames.

A broker MUST expose per-cohort counters for the silent-drop outcomes —
`invalid_address`, `invalid_signature`, `invalid_cac`, `wrong_stream`, `duplicate`,
`queue_dropped`. Points 8–10 and 12 are unobservable from the wire without them, so the
counters are part of the conformance surface rather than an implementation detail.

## Implementation

Groundwork exists in the bee prototype `pkg/bps` ([bee #5435][bee5435]), written against
SWIP-60. It is a superset of this spec in most places and diverges in one:

`pkg/bps` is a superset of this spec in some places and diverges in one: it implements
`ANCHOR` and `FEED_TOPIC` bindings, `EXPLICIT_SINGLE` and `EXPLICIT_LIST` regimes, the
`Hello` envelope and a WS bridge. Most of the work is subtraction:

| file | under BPS-lite |
|---|---|
| `publisher.go` | `authorizePublisher` goes entirely — there is no publisher to authorize against, only the topic |
| `binding.go` | `anchorBinding` only; the registry stays as the extension seam with one entry. `qualifies` **loses its explicit-regime early return**: the address check becomes unconditional |
| `cohort.go` | `Publishers`, `sortedCopy`, the regime switch in `ValidateSpec` and the publisher-list branch of `SpecEqual` go; `ValidateSpec` checks two fields |
| `broker.go` | `admit` sets the publisher role from the `Open` path rather than from `auth != nil`; the `PublisherAuth`-is-not-a-credential commentary goes with it |
| `broker.go` | gains a `publisher *peerStream` on the cohort: teardown fires only when the *current* publisher stream closes, and re-`Open` transfers it |
| `broker.go` | gains the queue-reset exemption for the publisher's stream |

Two behaviors are new — the lifetime rule and role transfer. Everything else is removal.

[swip60]: https://github.com/ethersphere/SWIPs/pull/104
[bee5435]: https://github.com/ethersphere/bee/pull/5435

## References

Parent design space: [SWIP-60 "BPS singlehop — brokered broadcast pub/sub, base
protocol", PR #104][swip60] · origin:
[PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" · implementation:
bee [#5435][bee5435]

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
