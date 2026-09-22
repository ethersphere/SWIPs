---
SWIP: 60
title: BPS singlehop — brokered broadcast pub/sub, the full singlehop protocol
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-08-03
---

<!-- Full singlehop SWIP of the Broadcast Pub/Sub (BPS) family: the decomposition of the
monolithic PubSub SWIP (ethersphere/SWIPs PR #93) into work-package-sized SWIPs. Extends
the base wire of SWIP-74 (BPS-lite, PR #111) and changes nothing in it. Companion
protobuf: assets/swip-60/bps.proto (revision 8, derived from SWIP-74's block). -->

- **Business line**: real-time topic streams for dApps without storing chunks or polling —
  enough on its own for the five cohort shapes it defines: **jam** (a closed set of authors:
  collaborative remix editing, a strudel livecoding session, a multiparty game),
  **spectator-jam** (the same before an audience), **live-stream** (one author, an audience),
  **group-chat** (everyone speaks) and **implicit** (a live feed with no authority at all).
  An admin grants and revokes authors while a cohort runs, without redefining it.
- **Dev line**: implement one libp2p protocol (`pubsub/1.0.0`, messages in
  [bps.proto](assets/swip-60/bps.proto)) plus a WebSocket bridge on the Bee API; done when
  a broker, publishers and subscribers interoperate per the conformance section. Groundwork
  exists in bee [#5435](https://github.com/ethersphere/bee/pull/5435).
- **Base**: [SWIP-74 BPS-lite](https://github.com/ethersphere/SWIPs/pull/111) — one
  publisher over a feed, one broker, one hop, three frames. This SWIP adds cohort
  parameters, the admin's service feed and the Bee API on top of that wire and never
  changes it: a SWIP-74 peer is a conformant peer of the live-stream configuration below.
- Bandwidth-incentive integration is a separate SWIP (bps-bw-incentives).
- Broker discovery integration is from a separate SWIP (bps-broker-discovery, building on
  [SWIP-59 MEX](https://github.com/ethersphere/SWIPs/pull/103)).

## Simple Summary

A real-time messaging protocol: WebSocket clients publish and subscribe to topic streams
through Bee nodes. One full node per cohort acts as **broker**, re-broadcasting each message
over direct, long-lived p2p streams to a capacity-bounded set of connected peers. Messages are
single-owner chunks, so every subscriber verifies authorship end-to-end; the broker can
withhold, never forge.

## Motivation

Swarm's event primitives (GSOC, PSS) require full-node operation; light clients can only
poll storage. [SWIP-74](https://github.com/ethersphere/SWIPs/pull/111) is the smallest
protocol that fixes this for one publisher; BPS singlehop is the smallest that fixes it for
every cohort shape, on the same wire: one broker, direct streams, authenticated messages,
an admin's control plane, an explicit capacity bound. Everything larger — multihop trees,
adaptive reorganisation, incentives, discovery — is layered on top by later SWIPs without
changing the semantics defined here.

## Specification

### The contract

Per topic-cohort:

- messages come from **publishers, and publishers only**;
- they arrive at **all subscribers**.

### Cohort genesis: the parameters

A cohort is fully described by a `CohortSpec` ([bps.proto](assets/swip-60/bps.proto)), fixed
the moment the first peer brings it to a BPS-speaking full node, and **immutable for the
cohort's lifetime**. **The spec is the cohort's identity**: every joiner carries it, and
two specs that differ in any field are two cohorts, even on one topic. There is no mode
enum; **modes are combinations of these parameters**.

| parameter | values | meaning |
|---|---|---|
| `topic` | 32 bytes | interpreted per `binding` |
| `binding` | `MNEMONIC` / `ANCHOR` / `SOC_ID` / `OWNER` / `FEED_TOPIC` | what the topic binds to; fixes which SOCs qualify as messages and the dedup rule |
| `admin` | eth address | the cohort's authority and a member of its publisher set — not necessarily the first to join. **Absent ⇒ implicit authorship**, and the two fields below do not apply |
| `publishers` | `ALL` or unset | set: anyone attached may author. Unset: the admin, and whoever its roster ever names — **a cohort is multi-publisher iff its admin ever publishes a roster**, and nobody needs to know in advance |
| `closed` | bool, unset = open | set: no audience — a joiner whose identity is not the admin's or on the roster is refused |
| `history` | bool | deliver matching chunks already in the local store (mechanism in bps-history; a singlehop broker MAY refuse) |

**The publisher list is deliberately not here.** It is dynamic — an admin grants and revokes
while the cohort runs — and this spec is immutable, so it cannot live in it without making
every roster change a new cohort. It is also not public in the way the rest of the spec is:
the owner of a stream, or of a co-edited file, is naturally known to its subscribers, but the
other grantees are not. The roster therefore travels as **admin-signed service messages on a
feed of its own** (below), where it changes without the cohort changing, and where a
subscriber verifies it against the admin's key rather than against the broker's word.

#### The five configurations

| configuration | `admin` | `publishers` | `closed` | who may author |
|---|---|---|---|---|
| **jam** | set | unset | true | admin + current grantees; nobody else attends |
| **spectator-jam** | set | unset | unset | admin + current grantees, before an audience |
| **live-stream** | set | unset | unset | the admin alone, before an audience — **SWIP-74's cohort**: a spectator-jam whose admin never publishes a roster |
| **group-chat** | set | `ALL` | unset | anyone attached — each peer signs its own SOCs |
| **implicit** | absent | — | unset | whoever the binding's SOC shape admits |

Live-stream and spectator-jam are one spec: nothing in it promises a single author in
advance, and nothing needs to — the audience verifies every message against the admin's
key and the roster it has seen, and a roster that never comes is a stream with one
author. `closed` does real work only where a roster decides authorship — the jam rows,
which is exactly the audience / no-audience distinction. Under `ALL` and under implicit
authorship every attached peer is already a potential author, so excluding non-publishers
excludes nobody; a spec MUST leave it unset there — a broker answers a `closed` `ALL` or
implicit spec with `REJECTED`.

**The admin is always in the publisher set**, and being a publisher obliges nobody to
publish — no peer waits on another — so a practically non-publishing **moderator** needs no
role of its own: it is simply an admin that never sends.

Binding semantics (dedup rule in parentheses):

- **`MNEMONIC`** — the topic constrains nothing: it names the cohort and no more. Any SOC
  from any owner qualifies (dedup on chunk address). This is what `ALL` needs. Authorship is
  unrestricted but never *unattributable*: every message is still SOC-signed, so a group chat
  knows exactly who said what without there being an authorised set to check it against.
- **`ANCHOR`** — topic = full SOC/GSOC address; all messages share one address (dedup on
  the wrapped CAC — the guard against unsolicited republication of old SOCs, sound only
  under an application-level requirement: payloads are distinct, i.e. the application
  includes some index in the payload). **Under explicit authorship the address check does
  not apply**: several owners cannot share one SOC address, so the topic is a rendezvous,
  legitimacy is roster membership (below), and only the wrapped-CAC dedup remains.
- **`SOC_ID`** — topic = SOC id; any owner with `PO(socAddr(id, owner), anchor) ≥ PO_MIN`
  qualifies (dedup on chunk address).
- **`OWNER`** — topic = `keccak256(owner)`; any id under the same PO constraint — MIC
  semantics (dedup on chunk address). The broker never inverts the hash: it recovers
  the owner from the SOC signature and checks `keccak256(owner) == topic`; the topic
  doubles as the PO anchor.
- **`FEED_TOPIC`** — id = `keccak256(topic ‖ index)`; feed-update streams, graffiti MIC
  (dedup on chunk address).

Under **explicit authorship** legitimacy is membership of the current roster, not proximity:
the PO constraint does not apply. Under **implicit authorship** nothing is checked against a
roster — there is none, and no admin either — and authorship is decided by **the shape of the
SOC** the binding fixes:

| binding | SOC shape | implicit publishers | who qualifies |
|---|---|---|---|
| `MNEMONIC` | any | **any** | anyone; the cohort has no authority and no roster |
| `ANCHOR` | GSOC | **one** | the holder of the shared GSOC key — one address, one identity |
| `OWNER` | MIC | **one** | the owner the topic names (`topic = keccak256(owner)`); the id varies |
| `FEED_TOPIC` | feed | **one** | the feed's owner; the id is `keccak256(topic ‖ index)` |
| `SOC_ID` | MOC | **many** | any owner that mines `PO(socAddr(id, owner), anchor) ≥ PO_MIN`; the id is fixed, the owner varies |

Where authorship is explicit and dedup is on the wrapped CAC (`ANCHOR`), the SOC id does no
protocol work: it is **unconstrained**, and publishers MAY use it as a plain sequence number.
The full sequential construction — signed as a feed update, carried as a bare index, making
missed updates detectable and recoverable — is **self-indexed feeds,
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)**.

The proximity constraint for implicit bindings is a **protocol constant**, not a cohort
parameter: `PO_MIN = 16`. (Making it a parameter invited proto3's unset-equals-0
footgun — an omitted value silently disabling the constraint — and no use case varies
it.)

Broker **capacity is deliberately not a cohort parameter**: a cohort cannot dictate a
remote node's connection count. Each broker enforces its own per-cohort stream limit and
answers `FULL` when it is exhausted — to a `Join` without a publisher's `Auth`: the
audience cannot lock the admin, or a rostered publisher, out of its own cohort.

**Cohort lifetime** is broker-side in the same way, with one exception. A cohort is not
tied to whoever joined first, nor to its admin's stream: it ends by **inactivity** — the
broker reclaims a cohort on which no publisher stream has had a message accepted for its
inactivity deadline, and MAY reclaim one with no attached streams at once (SWIP-74,
*Resource bounds*) — which is unobservable beyond a fresh cohort on the next `Join`. The
exception is the **end-of-stream** service message, by which an admin ends its own cohort
deliberately and *attributably* (below), and which is what distinguishes "over" from "the
broker stopped relaying".

### The service feed: the admin's control plane

Everything the admin says about the cohort — that it exists, who may write to it, and that it
is over — travels as SOCs on a feed the admin owns:

```
owner = admin        id = keccak256("bps-service:v1" ‖ topic ‖ index)
```

| index | message | carries |
|---|---|---|
| `n` | **roster** | the full publisher set as of version `n` |
| last | **end-of-stream** | the cohort is closed by its admin |

The feed starts at index 0 with the first roster or the end of stream; a cohort whose
admin has published nothing has an empty service feed, and the admin alone may write.
Each service message carries its own index in the payload, so its id is verifiable
without an out-of-band hint. Three properties follow, and each of them is the point:

- **The spec is nobody's word, and the admin is authenticated.** Every joiner brings the
  spec in its `Join`, so a broker cannot serve a peer a cohort it did not name; `admin`
  is an address anyone can read, its `Auth` at join is a recovered signature, and every
  message and every service message carries its signature. Nothing in the handshake
  needs to be trusted.
- **It is a feed, not a single mutable slot.** The obvious alternative — one constant-id SOC
  overwritten in place — makes a stale roster **undetectable**, which would reintroduce
  forging-by-omission at the one point that decides who may write. Sequential indices make
  gaps visible, so withholding stays a *liveness* fault like every other withholding in this
  protocol, and **self-indexing** feeds ([SWIP-65](https://github.com/ethersphere/SWIPs/pull/106))
  carry the construction.
- **The roster is verified end-to-end, like every message.** Service messages are ordinary
  SOCs on the ordinary path — storable, re-fetchable, and checked with the same code as any
  broadcast. A broker relays them; it cannot author them.

**`Ack` is a status, and the roster is the first delivery.** On every newly attached
stream not bound to the admin's identity the broker delivers the **latest service SOC** as
the first `Message` before any other **(?)**; a joiner learns who may write from the
admin, not from the broker, before it has received a single message, and a cohort with an
empty service feed delivers nothing first — the admin alone may write.

#### `Auth`: recovered, not asserted, and not tied to a node

`Auth` carries **a signature and no address**: the owner is the ecrecover output, so
presenting it is possession of a key, not a claim about one — identity and proof arrive in
the same operation and the handshake stays one frame each way, with no challenge round trip.

```
owner = ecrecover( H( "bps-join:v1" ‖ topic ‖ admin ), signature )
```

The preimage is deliberately **static, and free of any node identity**. Signing over the
libp2p peer id would make the credential unreplayable, but at the cost of welding the
publishing identity to the node holding the stream: the same key could not be used from a
second node without re-signing, and every join would link an eth identity to a peer id for
anyone watching. Neither is acceptable — an owner's identity is its own, not its node's.

The consequence, taken deliberately: a static preimage is **replayable**. It costs little:
a replayed role can publish only what its owner already signed, which the binding's dedup
refuses within a cohort's life and the subscriber's own cursor catches across one (Security
considerations). What `Auth` buys is that the broker need not carry peers whose frames could
only ever be dropped; **authorship rests on the message signature, never on the
handshake.**

The **`"bps-join:v1"` domain separator is load-bearing**. These are the same secp256k1 keys
that sign SOCs, over the preimage `id ‖ wrappedAddress`. Without separation a join signature
could be reinterpreted as a chunk signature, or a chunk signature coaxed out of a peer and
replayed as a join. The prefix makes the two preimage spaces disjoint by construction.

The identity `Auth` proves is **bound to the stream it arrives on, not to the peer
connection**: one node may carry different identities on different cohorts, and a stream
without `Auth` has none. Under implicit authorship there is no `Auth` at all: the SOC
itself is the credential, and its shape is checked on every `Message`.

### The first frame settles the role

A peer's role is fixed by its **first frame**, `Join` — the only handshake frame there is
— carrying the full `CohortSpec` and, if the peer claims an identity, an `Auth`. The
broker compares the spec with its live cohorts: **no match → the cohort is created** with
the joiner attached; **match → the joiner is attached**. Anyone whose `Join` is accepted
may create — in an open cohort that includes a spectator arriving before the admin, and a
cohort costs the broker a map entry until the inactivity deadline reclaims it; under
`closed` a `REJECTED` `Join` creates nothing, so the admin's is the first accepted one.
Cohorts are keyed by the **whole spec**, so pre-creating a topic under a wrong admin
squats nothing — the genuine spec is a different cohort.

Then the stream's role, from the address `Auth` recovers, matched against `admin` and the
**current roster**:

| outcome | `closed` unset | `closed` set |
|---|---|---|
| recovered address is the admin's, or in the roster | joins as **publisher** | joins as **publisher** |
| no match, or no `Auth` | joins as **spectator**, read-only — the identity, if any, stays bound to the stream and a later roster naming it promotes the stream in place | `REJECTED` |

`closed` is the only configuration in which a peer is turned away for *who it is*, and it
is enforceable precisely because `Auth` is recovered rather than asserted. Everywhere else
`REJECTED` means the *spec* is unacceptable — a value outside this SWIP, or a reserved
field set — and `FULL` means capacity, nothing more.

#### Grant and revocation

An admin changes the roster by publishing the next service message; the cohort spec never
changes. A **grant** takes effect for the granted peer on its next join, or immediately if it
is already attached as a spectator whose `Join` carried its `Auth` — the identity is bound to
the stream, so the stream is promoted in place.

A **revocation** has two phases, and the boundary between them is the moment the reduced
roster reaches subscribers:

1. **Before it is published**, the revoked peer has no way to know it has been revoked —
   nothing has told it. Its `Message` frames are therefore **dropped and tolerated**:
   silently ignored, no penalty, the connection untouched. There is nothing else a broker can
   honestly do, because the peer is not misbehaving.
2. **After it is published**, the peer has been told — it receives the service message like
   every other subscriber, on the same feed. Publishing from that point is a **protocol
   violation**, and the broker MUST break the connection.

The announcement is therefore not only for the audience's benefit: **it is what converts an
unknowing publisher into a violating one.** A broker that tore the stream down before
publishing the reduced roster would be punishing a peer for a rule it had not been given; a
broker that never publishes it leaves everyone — the revokee included — in a state where the
violation can never begin, which is an ordinary, visible withholding fault. The penalty
itself is the protocol's existing one: repeated invalid frames end the connection
(blocklisting policy).

Announcing first also makes the revocation legible to everyone else: subscribers learn *why*
a publisher fell silent from an admin-signed message rather than inferring it from a
disconnection they cannot attribute.


### Roles and capacity

- **Broker**: the first full node contacted; root of the (here, depth = 1) multicast tree.
  Enforces its own capacity. **At capacity it MUST answer `Join` with a refusal**
  (`FULL`) — for the per-cohort stream bound, a `Join` whose `Auth` recovers to the admin
  or to a rostered publisher is admitted past it, as in SWIP-74; referral to another
  attachment point is reserved for bps-multihop — a singlehop-only broker simply refuses. Because any peer can make a broker allocate a
  cohort simply by joining, a conformant broker also bounds **how many cohorts it will
  create** and **how many one peer connection may hold**, and **reclaims idle ones** —
  SWIP-74's bounds, all independent policy.
- **Admin**: the address the spec names — not necessarily the first to join — always a
  member of the publisher set, and the cohort's only authority: it grants, revokes and
  ends, each by publishing a service message. Its address is public in the spec — as a
  stream's or a co-edited file's owner naturally is — while its grantees' are not. An
  admin that never sends is a **moderator**; no separate role is needed, since being a
  publisher obliges nobody to publish.
- **Publisher**: sends and receives — every `Message` of the cohort except its own, on
  any of its streams. At
  depth = 1 every peer is attached to the broker, so publishers are too — this is a
  **consequence of singlehop, not a protocol invariant**. bps-multihop lifts it by
  forwarding `Message` frames rootward as well as leafward, so a publisher may sit
  several hops out; that is what lets an everyone-publishes cohort grow past one
  broker's capacity. Attachment is in any case necessary, not sufficient — under
  explicit authorship, the current roster decides.
- **Spectator**: receives only; joins with the same `Join` as everyone, carrying the
  spec it was invited with, and the broker delivers the latest roster as its first
  frame, so the cohort, its roster and every message are verified end-to-end. Every
  peer receives, so publishing is the *additional* capability and this role is what
  remains without it; a `closed` cohort has none.

### Information flow

```mermaid
sequenceDiagram
    autonumber
    participant PD as publisher dApp
    participant PN as publisher's bee node<br/>(WS bridge)
    participant B as broker<br/>(root, full node)
    participant SN as subscriber's bee node<br/>(WS bridge + mux)
    participant SD as subscriber dApp(s)

    PN->>B: Join(CohortSpec, Auth)
    Note over PN,B: the spec is the cohort's identity: the first Join creates it,<br/>later ones attach; at depth = 1 every publisher is attached to the broker
    B-->>PN: Ack(OK)
    SN->>B: Join(CohortSpec, Auth?)
    B-->>SN: Ack(OK)
    B->>SN: Message(latest ROSTER) — the admin's word, relayed
    Note over B,SN: spec in hand + admin-signed roster ⇒<br/>subscriber verifies every message end-to-end

    PD->>PN: WS: payload
    PN->>B: Message(SOC)
    B->>B: validate: SOC sig ⊨ topic binding<br/>(+ dedup per binding)

    par fan-out to every stream of the cohort not bound to the publishing identity
        B->>SN: Message(SOC) — every frame self-contained
        SN->>SN: mux: one p2p stream → N WS sessions
        SN->>SD: WS: payload
    end
    Note over B,PN: other publishers' streams receive it the same way;<br/>the author's own never do
```

The broadcast is **end-to-end authenticated**: every subscriber re-verifies the SOC
signature against the topic binding regardless of path.

### Wire protocol

Messages are defined in [bps.proto](assets/swip-60/bps.proto). Framing notes:

- Transport: libp2p stream `pubsub/1.0.0`, one stream per (peer, cohort),
  protobuf-over-libp2p as bee protocols elsewhere. The first and only handshake frame on
  a fresh stream is **`Join`**, carrying the full `CohortSpec` and optionally an `Auth`;
  the broker answers with `Ack{status}`, and delivers the latest service SOC as the
  stream's first `Message`, so the joiner verifies the roster against the admin rather
  than the broker. The three frames — `Join`, `Ack`, `Message` — and the two types they
  carry are SWIP-74's; this SWIP adds fields and values, never frames.
- **`Join` creates or attaches**, keyed by the whole spec: a spec no live cohort has
  creates one, a byte-identical spec attaches, and there is no "unknown topic".
  Implicit-publisher cohorts rely on this — the first subscriber creates, so a client
  need not know whether it is first — and so does every audience member arriving before
  its admin.
- **Stream model rationale**: per-cohort streams give per-cohort flow control, teardown
  and role typing, and match bee's protocol idiom. Because every frame carries the full
  SOC (self-contained, no per-stream handshake state), a later move to topic-muxed
  streams requires no format change.
- Every `Message` carries the **full chunk** as opaque chunk data (SWIP-74), validated by
  the ordinary SOC code; there is no handshake/data frame split. Deliveries go to every
  stream of the cohort except those bound to the publishing identity: a publisher never
  receives its own messages back, on whichever of its streams it sent them (SWIP-74).
- No BPS-level keepalive or RTT probing: liveness is the transport's job, and latency
  metrics for reorganisation policies are sourced there too.
- Broker validation on a `Message`: SOC signature verifies against the topic binding, PO
  constraint holds where applicable, the stream's identity is a legitimate publisher (the
  admin or a rostered address; anyone under `ALL`; the binding's SOC shape under implicit
  authorship). Invalid ⇒ drop and count; repeated invalid ⇒ disconnect (blocklisting
  policy). A message that passes and is a **duplicate** per the binding's dedup rule is
  dropped and counted as a retransmit, never as invalid — an admin reconnecting after a
  reset legitimately resends (SWIP-74); a broker MAY reset a stream whose retransmit rate
  exceeds its policy. A `Message` on a stream whose identity may not publish — none, or one
  neither the admin's nor rostered — is a protocol violation: dropped, the stream reset,
  the peer blocklisted (SWIP-74).
- **Service messages** ride the same frame and are recognised before the content path: a
  `Message` on a stream bound to `admin` whose payload decodes as a `ServiceMessage` and
  whose id equals `keccak256("bps-service:v1" ‖ topic ‖ payload.index)` is a service SOC.
  It is accepted iff it validates as a SOC under that id, its owner is `admin`, and
  `payload.index` exceeds the service feed's cursor (initially absent: index 0 is
  accepted); otherwise it is invalid. Under `FEED_TOPIC` the two paths are told apart by
  the id slot alone — a feed update carries a bare index (24 leading zero bytes), a
  service SOC its full id — which is why a SWIP-74 broker drops the latter rather than
  punishing it.
- **The dedup *horizon* is implementation-defined, but it MUST be bounded**: the binding
  fixes what counts as a duplicate, not how far back the broker remembers, and an
  unbounded seen-set is a memory-exhaustion vector. A broker keeps a bounded window over
  recent message identifiers; the accepted consequence is that a legitimate publisher can
  overrun that window and replay an evicted message. Applications that cannot tolerate
  replay carry their own sequencing — which the sequential construction of
  [SWIP-65](https://github.com/ethersphere/SWIPs/pull/106) gives for free. A SWIP-74
  broker is stricter on its one configuration — a per-cohort **cursor**, `index > cursor`,
  no window at all — which this SWIP does not adopt: with several publisher feeds on one
  topic, and with the reordering of [SWIP-61](https://github.com/ethersphere/SWIPs/pull/105),
  a full broker dedups on chunk address and passes retransmits through, and the subscriber's
  own cursor does the rest.

### API (WebSocket bridge)

One endpoint pair on the Bee API. Endpoint shape follows bee
[#5435](https://github.com/ethersphere/bee/pull/5435), generalised from its single
hardcoded mode to the full parameter space; serialization conventions follow the SOC
subscription family — GSOC/MIC/MOC (bee
[#5486](https://github.com/ethersphere/bee/pull/5486),
[#5497](https://github.com/ethersphere/bee/pull/5497)) — whose `/mic/subscribe/{owner}`
and `/moc/subscribe/{id}` endpoints are the storage-fed counterparts of the `OWNER` and
`SOC_ID` bindings, so a dApp switches between stored and live feeds without
reformatting. All p2p framing is transparent to WS clients; one p2p stream is muxed to
N local WS sessions per topic.

**`GET /pubsub/{topic}`** — upgrades to a WebSocket session on the topic. `{topic}` is
the 32-byte topic hex-encoded, or an arbitrary string hashed to 32 bytes (mnemonic
topics). Query parameters:

| parameter | maps to | meaning |
|---|---|---|
| `peer` | — | broker underlay multiaddr; required until broker discovery exists (bps-broker-discovery) — early deployments configure it |
| `binding`, `admin`, `publishers`, `closed`, `history` | `CohortSpec` | **the spec, on every session**: `binding` always, the others where the spec sets them — the spec is the cohort's identity and the invite carries it; the node sends `Join` with the assembled spec, which creates or attaches, and keys its sessions by the whole spec, not the topic. `admin` omitted ⇒ implicit authorship. No publisher list here — it is not part of the spec |
| `auth` (+ `id` where the binding does not fix it) | `Auth` | 65-byte join signature over `H("bps-join:v1" ‖ topic ‖ admin)`. **Binds an identity to the session's stream**: read–write iff that identity is the admin's or currently rostered (or the cohort is `ALL`), read-only otherwise and promoted in place when a later roster names it; absent, a spectator with no identity. Signed client-side, like every other signature here — the node holds no publisher keys, and the signature is over no node identity, so the same key works from any node |

**`POST /pubsub/{topic}/service`** — the admin's control plane: submits a service message
(`ROSTER` or `END_OF_STREAM`) as the next update on the service feed. The SOC is signed
client-side by the admin key; the node relays it on the cohort whose `admin` that key is.
Granting or revoking a publisher is one call here and touches no cohort parameter.

Headers:

- `swarm-keep-alive` (seconds, default 60): ping period of the **local WS link only** —
  not to be confused with the p2p layer, which has no keepalive.
- `swarm-soc-fields` (per bee [#5497](https://github.com/ethersphere/bee/pull/5497)):
  comma-separated SOC fields serialized per outbound message — `address`,
  `recoveredPubKey`, `identifier`, `signature`, `wrappedAddress`, `span`, `payload`;
  default `payload`. This is how dApps on implicit-binding streams (`OWNER`, `SOC_ID`,
  feed) attribute messages — no BPS-specific frame format.
- `swarm-cache-wrapped-chunk` (per bee
  [#5497](https://github.com/ethersphere/bee/pull/5497)): when true, the wrapped chunk
  of every incoming message is stored in the local cache, resolvable through the bytes
  endpoint — for streams whose messages reference content larger than one chunk.

**`GET /pubsub/`** — lists the node's active topics: topic address, cohort parameters,
own role (broker / subscriber), connected peers.

**Signing — the key-holding rule.** Message signing is the dApp's business: **the node
never holds publisher keys**. Inbound (publisher → node): `sig ‖ span ‖ payload`,
signed client-side (bee-js). Where the binding does not fix the SOC id, the frame is
prefixed with it — for feed bindings the prefix is the bare index, the signed id being
the feed id `keccak256(topic ‖ index)` (self-indexed feeds,
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106));
under explicit regimes with `ANCHOR` binding the id does no work and there is no
prefix. The node assembles the SOC, validates it exactly as a broker would, and
publishes. End-to-end verification against the `CohortSpec` the session supplied — the
spec the node sent in `Join` — is performed by the local node — node and dApp are one
trust domain.

**Worked API calls — the jam cohort** (see Configurations below). Seat A joins — its
`auth` recovers to `admin` ⇒ read–write; the spec creates the cohort, since under `closed`
nobody else's `Join` is accepted before A's:

```
wss://node:1633/pubsub/jam-tuesday?peer=<broker-multiaddr>
    &binding=anchor&admin=0xA…&closed=true&auth=0x3f2a…
```

Seats B–D join with the same spec and their own `auth`:

```
wss://node:1633/pubsub/jam-tuesday?peer=<broker-multiaddr>
    &binding=anchor&admin=0xA…&closed=true&auth=0x9c14…
```

Seats B–D are not named in this URL and never appear in a cohort parameter: A grants them
with a `POST /pubsub/jam-tuesday/service` carrying a `ROSTER` message, and can revoke or add a
fifth seat later without any of the above changing. Each seat is sorted into the publisher
role by the address recovered from its `auth`; because the cohort is `closed`, a peer with no
listed key is `REJECTED` rather than admitted read-only. The join URL minus `auth` is the
complete out-of-band invite (spec + broker) until broker discovery exists — and it is
genuinely an invite: only a holder of a rostered key can turn it into a session at all.
A live MIC — all SOCs of one owner, the light-client twin
of `/mic/subscribe/{owner}` — is the implicit case: every subscriber joins with
`?binding=owner`, no `admin` and no `auth` (the first creates, the rest attach),
topic = `keccak256(owner)`, read-only, `swarm-soc-fields: identifier,payload`.

### Configurations (worked examples)

The five configurations, as `CohortSpec` rows.

**Jam** — a 4-seat collaborative remix edit, a strudel livecoding session, a multiparty game.

```
binding: ANCHOR (topic = mnemonic anchor)   admin: 0xA…
closed: true   history: false
```

Seat A joins; B, C and D are granted by a `ROSTER` service message, and each is sorted into
the publisher role on joining because the address recovered from its `Auth` is on the roster
it can verify against A's key. A fifth peer is `REJECTED` — this is the one configuration in
which a peer is refused for who it is, and it is enforceable because `Auth` is recovered, not
asserted. A may grant a fifth seat, or revoke one, without the cohort spec changing at all.
Confidentiality is still not on offer: the broker holds plaintext, and a jam that needs it
encrypts payloads.

**Spectator-jam** — the same, opened to an audience.

```
binding: ANCHOR   admin: 0xA…
history: false
```

Identical authorship, but an unrecognised joiner is admitted read-only instead of refused —
and, if its `Join` carried an `Auth`, promoted in place when a later roster names it.
The audience verifies the roster from the admin's feed, so it knows exactly whose messages
are legitimate without trusting the broker.

**Live-stream** — single publisher, open audience.

```
binding: FEED_TOPIC (sequential index)   admin: the streamer
history: false
```

This is [SWIP-74](https://github.com/ethersphere/SWIPs/pull/111)'s cohort exactly, and a
SWIP-74 peer is a conformant peer of it. The spec is the same as a spectator-jam's: the
streamer simply never publishes a roster, so it stays the only author, and the audience
verifies every message against its key regardless. What this SWIP adds is the end: the
streamer ends it with an `END_OF_STREAM` service message, which is what distinguishes
"over" from "the broker stopped relaying" — and from SWIP-74's inactivity reclaim.

**Group-chat** — anyone attached may speak.

```
binding: MNEMONIC (the topic is just the cohort's name)   admin: 0xA…
publishers: ALL   history: false
```

No roster, no `Auth`, no constraint on the SOCs: each peer signs and sends its own. The topic
binds nothing — it names the cohort, and that is all it does. Authorship is unrestricted but
never *unattributable*: every message is SOC-signed, so the chat knows exactly who said what
without there being an authorised set to check against. The admin here is not a gatekeeper —
it cannot be, since everyone may write — but it still owns the service feed, so it can end
the cohort. This is the row that outgrows a single broker fastest, and the one
[SWIP-61](https://github.com/ethersphere/SWIPs/pull/105) exists to scale: with publications
forwarded from the leaves towards the root, a member need not be attached to the broker to
speak. Where a cohort wants no authorship guarantees at all, see "why not gossipsub".

**Implicit** — no admin, no roster, no authority.

```
binding: OWNER (topic = keccak256(owner))   admin: absent
history: false
```

A live MIC: all SOCs of one owner, the light-client twin of `/mic/subscribe/{owner}`. There
is no admin, so no service feed, no grants and no end-of-stream — nothing to authenticate,
because **the chunk carries its own legitimacy** and the binding's SOC shape is the whole
check. `SOC_ID` gives the multi-author version of this (MOC: id fixed, each publisher mining
its own owner into the anchor neighbourhood — own-identity writers, as in
[SWIP-66](https://github.com/ethersphere/SWIPs/pull/107)), and `MNEMONIC` the unconstrained
one, which is group-chat minus the authority to end it.

### The modes — enumerated as combinations of dimension choices

Known use cases attach here; each mode is nothing more than a row — a combination of
publisher/subscriber info, topic match type, and history. (`+/−` = both configurations
meaningful.)

| configuration | binding | audience (`closed` unset) | history | use case |
|---|---|---|---|---|
| live-stream | feed topic, index sequential | + | — | live video streaming |
| spectator-jam | feed topic, index sequential | + | — | live videoconference |
| jam | anchor | — | +/— | private co-authoring, remix editing |
| group-chat | mnemonic — no constraint | + | +/— | multi-party / group chat |
| implicit | anchor (ephemeral GSOC) | + | +/— | anythread comments / troll-box |
| implicit | id fixed, owner mined (MOC) | + | +/— | own-identity writers on a shared id |
| implicit | id = `keccak256(topic ‖ index)` | + | +/— | following one or more feeds |
| implicit | feed special, mined index | + | +/— | following graffiti soc |
| implicit | owner (MIC) | + | +/— | tags, adverts |

At depth = 1 the broker's capacity bounds **both** directions: the audience by its stream
count, and — since every publisher is attached to it — the publisher count too. Scaling
either past one broker is bps-multihop's business
([SWIP-61](https://github.com/ethersphere/SWIPs/pull/105)), which forwards `Message`
frames rootward as well as leafward. The everyone-publishes rows above — group chat,
videoconference, troll-box — are the ones that need it.

The implicit rows and history are specified in bps-implicit-publisher and bps-history
respectively — with the split that **this** SWIP fixes *who* an implicit publisher is (the
binding-to-SOC-shape table above, and the cardinality that follows from it), because that is
validation the broker cannot operate without, while bps-implicit-publisher keeps the
event-sourcing mechanism built on top.

## Rationale: why not gossipsub

libp2p ships gossipsub, a battle-tested mesh multicast. BPS builds its own protocol
because gossipsub's core mechanisms — flooding to a random mesh, IHAVE/IWANT
pull-recovery — are exactly what an incentivised network rejects: **no node wants to pay
for a message it did not ask for.** That one economic fact dissolves gossipsub's
machinery: metered edges mean no redundant paths and no transport-level duplicates; a
cohort's `CohortSpec` scopes every session; authentication is structural (SOC-signed
against the topic binding), so brokers and relays forward without being trusted — an
intermediate can withhold, never forge; and withholding is a liveness fault recoverable
by re-pointing or relocating the topic. Multihop forwarding (bps-multihop) adds capacity
without reintroducing flooding: every edge still pays upstream, every node still receives
only its topic's stream — and publishing from depth > 1 is metered the same way, priced by
depth (bps-bw-incentives).

**And in the happy case the tree wins on traffic, not only on trust.** A publish in a
multihop cohort travels **rootward** from wherever it originates and then **leafward** to
everyone: each edge carries the message **exactly once**. A single-parented tree therefore
needs no duplicate suppression at all — no seen-set, no IHAVE/IWANT pull-recovery, no
mesh-degree multiplier applied at every hop. Gossipsub pays D copies per node by
construction and recovers the remainder by asking. Where the tree is well matched to the
underlay — a **closely knit topology**, peers whose tree edges are also their short paths —
rootward-then-leafward is simply the cheaper delivery, and a publisher sitting at depth d
pays those d hops once, on the way up. Duplicates in BPS are a deliberate purchase rather
than a structural cost: dual parenting in
[SWIP-61](https://github.com/ethersphere/SWIPs/pull/105) buys withholding-masking with a
second copy, and that is the case in which the dedup horizon above earns its keep.

**The concession.** Where an application genuinely wants *gossip* — a large symmetric
cohort with no publisher structure, every member a source, message-level flooding the
point, and no interest in who signed what — **libp2p gossipsub is the better tool and the
application should simply use it.** BPS is not trying to win that comparison. It earns its
keep where the cohort has shape: authorship that is structurally authenticated (SOC-signed
against the topic binding, verifiable regardless of path, so an intermediate can withhold
but never forge), edges that are bounded and metered, messages that are chunks and so
re-fetchable from storage, and a `CohortSpec` that states who may write. The implicit cohort
exists for symmetric groups that want *those* properties — a group chat whose messages are
verifiable signed chunks — not to reimplement a mesh.

## Security considerations

**The spec is nobody's word, and the admin is authenticated.** Every joiner carries the
spec in its `Join`, so a broker cannot serve a peer a cohort it did not name, and a
cohort somebody else pre-creates under a wrong admin is simply a different cohort.
`admin` is a public address; its `Auth` at join is a recovered signature, and every
message and every roster it publishes carries its signature. Nothing else in the
handshake needs to be trusted, because the roster arrives the same way — signed by the
admin, on a feed whose gaps are visible.

**The publisher role is proved, not asserted.** `Auth` carries a signature and no address:
the owner is recovered from it, so presenting it is possession of a key. The preimage is
static and carries **no node identity** — deliberately. Binding it to the libp2p peer id
would make it unreplayable, but would weld the publishing identity to the node holding the
stream: the key could not be used from a second node without re-signing, and every join would
link an eth identity to a peer id for anyone watching. An owner's identity is its own, not
its node's.

The accepted consequence: a static preimage is **replayable**, and a replayed role can
publish only what its owner already signed — worthless within a cohort's life, where the
binding's dedup refuses it, and a matter for the subscriber's own cursor across cohorts
(SWIP-74, *Security considerations*). Which is the deeper point —

**Defence in depth is the real guarantee.** Even a peer that obtains the publisher role gains
nothing by it: every message is validated on arrival against the SOC signature and the
current roster (or, for an implicit cohort, the binding's SOC shape). `Auth` spares the
broker from carrying peers whose frames could only ever be dropped; **authorship rests on the
message signature, never on the handshake.** A **challenge round trip** is therefore not
specified: it would cost a frame in an otherwise one-each-way establishment to harden a
credential that grants nothing on its own.

**Audience control exists in exactly one form, and it is not confidentiality.**
`closed` refuses a joiner outside the roster, and is enforceable because `Auth` is
recovered rather than asserted. It bounds *attendance at this broker*, nothing more. **BPS
provides no confidentiality at any layer**: the broker sees every message in plaintext, and so
does everyone it admits. Applications needing a bounded audience **encrypt payloads** — SOC
wrapping is orthogonal to payload encryption, and key distribution is the application's
business. A jam is private because it encrypts, not because it refuses spectators.

**Revocation is announced before it is enforced, and the announcement is what makes
enforcement legitimate.** Between an admin's revocation and the reduced roster reaching
subscribers, the revoked peer cannot know its status has changed: its frames are dropped and
tolerated, with no penalty and no teardown, because it is not misbehaving. Once the roster is
published the peer has been told — on the same feed as everyone else — so publishing after
that is a protocol violation and the connection is broken. A broker that disconnected first
would be punishing a peer for a rule it had not been given; a broker that never publishes the
roster leaves the violation unable to begin at all, which is an ordinary, visible withholding
fault. Announcing first also makes the revocation legible to the rest of the cohort, which
learns *why* a publisher fell silent from an admin-signed message rather than from an
unattributable disconnection.

**Resource bounds are broker policy, and all are required.** A conformant broker bounds
its per-cohort stream count (`FULL`), the number of cohorts it will create and the number
one peer connection may hold (any peer can make it allocate a cohort simply by joining),
and reclaims idle cohorts — SWIP-74's bounds — and bounds its dedup window (see the
horizon note above), which SWIP-74's one configuration replaces with a cursor. The bounded
dedup window admits replay of an evicted message by an already-legitimate publisher: a
cohort-internal nuisance, not a break of authorship.

## Out of scope (deliberately)

Multihop relaying and referral (bps-multihop), reorganisation policies (SWATCH, SPORE —
policy SWIPs over this protocol's events and actions, no new frames), bandwidth incentives
(bps-bw-incentives), broker discovery (SWIP-59 MEX; early deployments hardcode brokers),
history delivery mechanism (bps-history), implicit-publisher event sourcing
(bps-implicit-publisher), and **confidentiality of any kind** — encrypt payloads, see
Security considerations. Dynamic publisher lists are **no longer out of scope**: grants and
revocations are the service feed's business, and neither changes the cohort.

## Conformance (definition of done)

An implementation is conformant when:

1. a broker enforces SWIP-74's bounds — streams per cohort, cohorts per broker, cohorts
   per peer connection, the inactivity deadline — plus publisher legitimacy, per-binding
   validation and dedup;
2. a subscriber re-verifies every message end-to-end — against the `CohortSpec` it
   joined with and the admin-signed roster it received — and detects (only) liveness
   faults;
3. the **five** configurations above — jam, spectator-jam, live-stream, group-chat and
   implicit — interoperate across independent implementations against the frames in
   [bps.proto](assets/swip-60/bps.proto);
4. a `FULL` refusal is issued at capacity — and nothing else is (no referral);
5. the WS bridge round-trips each worked configuration end to end — join, publish,
   receive — with all signing on the client side (the node holds no publisher keys);
6. the handshake is one `Join` carrying the full spec, creating the cohort or attaching
   to it, keyed by the whole spec; `Ack` is a status; a newly attached stream receives
   the latest service SOC as its first `Message` **(?)**;
7. an absent `admin` is treated as implicit authorship — validated strictly per the
   binding's SOC shape — and a present one authenticated by its `Auth` at join and by its
   signature on every service message, both of which MUST recover to it;
8. `Auth` is verified by recovery over `H("bps-join:v1" ‖ topic ‖ admin)`, the identity
   is bound to the stream, and a joiner outside the roster is admitted read-only where the
   cohort is not `closed` — promoted in place if a later roster names it — and `REJECTED`
   where it is — the only refusal for identity in the protocol;
9. an admin grants and revokes by publishing `ROSTER` service messages; a revoked
   publisher's frames are **dropped and tolerated** until the reduced roster is published,
   and its connection is broken only if it publishes **after** that point;
10. a subscriber takes the roster from the admin's service feed, never from the broker, and
    treats an index gap in that feed as a liveness fault.

## Backwards compatibility

New protocol; no existing behaviour changes. This SWIP extends the wire of
[SWIP-74](https://github.com/ethersphere/SWIPs/pull/111) and changes nothing in it: a
SWIP-74 peer at a full broker is a conformant peer of the live-stream configuration, and a
SWIP-74 broker refuses at the handshake every spec that differs from
`{topic, FEED_TOPIC, admin}`. The one thing it cannot refuse there is a feed-topic cohort
whose admin later publishes a roster — the spec is the same — and it serves that as a live
stream: the roster and the grantees' updates are dropped as invalid, so an admin that wants
a roster needs a full broker. Reserved `Message` fields hold the multihop control plane,
so bps-multihop extends without a version bump —
[SWIP-61](https://github.com/ethersphere/SWIPs/pull/105) is to be re-based on the `Message`
frame, a rename of its `Publish`/`Broadcast`; self-contained frames mean a change of stream
model needs no format change either.

## References

Wire: [bps.proto](assets/swip-60/bps.proto) · base:
[SWIP-74 BPS-lite, PR #111](https://github.com/ethersphere/SWIPs/pull/111) · origin:
[PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" · broker discovery:
[SWIP-59 MEX, PR #103](https://github.com/ethersphere/SWIPs/pull/103) · implementation:
bee [#5435](https://github.com/ethersphere/bee/pull/5435), bee-js
[#1151](https://github.com/ethersphere/bee-js/pull/1151)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
