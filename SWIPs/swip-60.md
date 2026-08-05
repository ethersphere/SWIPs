---
SWIP: 60
title: BPS singlehop — brokered broadcast pub/sub, base protocol
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track (Networking)
created: 2026-08-03
---

<!-- Base SWIP of the Broadcast Pub/Sub (BPS) family: the decomposition of the monolithic
PubSub SWIP (ethersphere/SWIPs PR #93) into work-package-sized SWIPs. Companion protobuf:
assets/swip-60/bps.proto. -->

- **Business line**: real-time topic streams for dApps without storing chunks or polling —
  enough on its own for small closed collaboration cohorts (collaborative remix editing, a
  strudel livecoding session, multiparty games) and basic single-publisher limited-audience
  live streaming.
- **Dev line**: implement one libp2p protocol (`pubsub/1.0.0`, messages in
  [bps.proto](assets/swip-60/bps.proto)) plus a WebSocket bridge on the Bee API; done when
  a broker, publishers and subscribers interoperate per the conformance section. Groundwork
  exists in bee [#5435](https://github.com/ethersphere/bee/pull/5435).
- Bandwidth-incentive integration is a separate SWIP (bps-bw-incentives).
- Broker discovery integration is from a separate SWIP (bps-broker-discovery, building on
  [SWIP-59 MEX](https://github.com/ethersphere/SWIPs/pull/103)).

## Simple Summary

A real-time messaging protocol: WebSocket clients publish and subscribe to topic streams
through Bee nodes. One full node per topic acts as **broker**, re-broadcasting each message
over direct, long-lived p2p streams to a capacity-bounded set of connected peers. Messages are
single-owner chunks, so every subscriber verifies authorship end-to-end; the broker can
withhold, never forge.

## Motivation

Swarm's event primitives (GSOC, PSS) require full-node operation; light clients can only
poll storage. BPS singlehop is the smallest protocol that fixes this: one broker, direct
streams, authenticated messages, an explicit capacity bound. Everything larger — multihop
trees, adaptive reorganisation, incentives, discovery — is layered on top by later SWIPs
without changing the semantics defined here.

## Specification

### The contract

Per topic-cohort:

- messages come from **publishers, and publishers only**;
- they arrive at **all subscribers**.

### Cohort genesis: the parameters

A cohort is fully described by a `CohortSpec` ([bps.proto](assets/swip-60/bps.proto)),
fixed the moment the first peer contacts a BPS-speaking full node with a topic. There is
no mode enum; **modes are combinations of these parameters**.

| parameter | values | meaning |
|---|---|---|
| `topic` | 32 bytes | interpreted per `binding` |
| `binding` | `ANCHOR` / `SOC_ID` / `OWNER` / `FEED_TOPIC` | what the topic binds to; fixes which SOCs qualify as messages and the dedup rule |
| `publishers` | `EXPLICIT_SINGLE` / `EXPLICIT_LIST` / `IMPLICIT` / `ALL` | who may author |
| `admin` + `publisher_list` | eth addresses | set iff explicit publishers; with `EXPLICIT_LIST` the full publisher set is **fixed at genesis** (dynamic grants/revocations are deferred to a later revision) |
| `history` | bool | deliver matching chunks already in the local store (mechanism in bps-history; a singlehop broker MAY refuse) |
| `po_min` | uint (default 16) | proximity constraint for implicit bindings: `PO(socAddr, anchor) ≥ po_min` |
| `closed` | bool | no audience: subscribers are restricted to the publisher set (all and only publishers subscribe) |

Broker **capacity is deliberately not a cohort parameter**: a cohort cannot dictate a
remote node's connection count. Each broker enforces its own per-topic stream limit and
answers `FULL` when it is exhausted.

Binding semantics (dedup rule in parentheses):

- **`ANCHOR`** — topic = full SOC/GSOC address; all messages share one address (dedup on
  the wrapped CAC).
- **`SOC_ID`** — topic = SOC id; any owner with `PO(socAddr(id, owner), anchor) ≥ po_min`
  qualifies (dedup on chunk address).
- **`OWNER`** — topic = SOC owner; any id under the same PO constraint — MIC semantics
  (dedup on chunk address).
- **`FEED_TOPIC`** — id = `keccak256(topic ‖ index)`; feed-update streams, graffiti MIC
  (dedup on chunk address).

### Roles and capacity

- **Broker**: the first full node contacted; root of the (here, depth = 1) multicast tree.
  Enforces its own per-topic capacity. **At capacity it MUST answer `Open`/`Subscribe`
  with a refusal** (`FULL`); referral to another attachment point is reserved for
  bps-multihop — a singlehop-only broker simply refuses.
- **Opener**: the one peer that fixes the `CohortSpec` (`Open`); with explicit publisher
  regimes the opener publishes.
- **Publisher**: sends and receives. MUST be directly connected to the broker; direct
  connection is necessary, not sufficient — with explicit publishers, the genesis list
  decides.
- **Subscriber**: receives only; joins by naming the topic (`Subscribe`) and carries no
  cohort metadata — the broker echoes the `CohortSpec` back so every message can be
  verified end-to-end. Does not exist in `closed` cohorts.

### Information flow

```mermaid
sequenceDiagram
    autonumber
    participant PD as publisher dApp
    participant PN as publisher's bee node<br/>(WS bridge)
    participant B as broker<br/>(root, full node)
    participant SN as subscriber's bee node<br/>(WS bridge + mux)
    participant SD as subscriber dApp(s)

    PN->>B: Open(CohortSpec, auth)
    Note over PN,B: opener fixes the cohort; publisher ⇒<br/>direct connection to broker
    B-->>PN: Ack(OK)
    SN->>B: Subscribe(topic)
    B-->>SN: Ack(OK, CohortSpec)
    Note over B,SN: echoed spec ⇒ subscriber verifies<br/>every message end-to-end

    PD->>PN: WS: payload
    PN->>B: Publish(SOC)
    B->>B: validate: SOC sig ⊨ topic binding<br/>(+ dedup per binding)

    par fan-out to every subscriber stream
        B->>SN: Broadcast(SOC) — every frame self-contained
        SN->>SN: mux: one p2p stream → N WS sessions
        SN->>SD: WS: payload
    and publisher's own subscription (if subscriber too)
        B->>PN: Broadcast(SOC)
        PN->>PD: WS: payload
    end
```

The broadcast is **end-to-end authenticated**: every subscriber re-verifies the SOC
signature against the topic binding regardless of path.

### Wire protocol

Messages are defined in [bps.proto](assets/swip-60/bps.proto). Framing notes:

- Transport: libp2p stream `pubsub/1.0.0`, one stream per (peer, topic),
  protobuf-over-libp2p as bee protocols elsewhere. The first message on a fresh stream is
  `Open` (fixes a new cohort) or `Subscribe` (joins one — topic only, no cohort
  metadata); the broker answers with `Ack`, echoing the `CohortSpec` to subscribers.
- **Stream model rationale**: per-topic streams give per-cohort flow control, teardown
  and role typing, and match bee's protocol idiom. Because every frame carries the full
  SOC (self-contained, no per-stream handshake state), a later move to topic-muxed
  streams requires no format change.
- Every `Broadcast` frame carries the **full SOC** (id, owner, signature, span, payload);
  there is no handshake/data frame split.
- No BPS-level keepalive or RTT probing: liveness is the transport's job, and latency
  metrics for reorganisation policies are sourced there too.
- Broker validation on `Publish`: SOC signature verifies against the topic binding, PO
  constraint holds where applicable, sender is a legitimate publisher, message is not a
  duplicate per the binding's dedup rule. Invalid ⇒ drop; repeated invalid ⇒ disconnect
  (blocklisting policy).

### API (WebSocket bridge)

WS clients see raw mode payloads only; all p2p framing is transparent. One p2p stream is
muxed to N local WS sessions per topic. Endpoint shape per bee
[#5435](https://github.com/ethersphere/bee/pull/5435).

### Configurations (worked examples)

Modes are rows over the parameters; two normative examples:

**The 4-seat jam cohort** — collaborative remix editing, a strudel livecoding session, a
multiparty game.

```
binding: ANCHOR (topic = mnemonic anchor)   publishers: EXPLICIT_LIST (admin + 3)
closed: true (all and only publishers subscribe)   history: false
```

Every seat sends and receives; there is no audience; the genesis list **is** the seat
bound — a fifth peer's `Subscribe` gets `REJECTED`.

**Basic live streaming** — single publisher, open audience:

```
binding: FEED_TOPIC (sequential index)   publishers: EXPLICIT_SINGLE
closed: false   history: false
```

### The modes — enumerated as combinations of dimension choices

Known use cases attach here; each mode is nothing more than a row — a combination of
publisher/subscriber info, topic match type, and history. (`+/−` = both configurations
meaningful.)

| # of pubs | pubs implicit? | subscribers | topic / anchor match | history | use case |
|---|---|---|---|---|---|
| 1 | — | all | feed topic, index sequential | — | live video streaming |
| any | — | all | feed topic, index sequential | — | live videoconference  |
| — | + | all | feed topic | +/— | tags, adverts; private co-authoring |
| all | — | all | topic a mere mnemonic of the cohort | +/— | gossip cohort for multi-party / group chat |
| any | + | all | anchor (ephemeral GSOC) | +/— | anythread comments / troll-box |
| any | + | all | ID = `keccak256(topic ‖ index)` | +/— | following one or more feeds |
| — | + | all | feed special, mined index | +/— | following graffiti soc  |

The audience is bounded by the broker's capacity; scaling past it is bps-multihop's
business.

Rows requiring implicit publishers or history are specified in bps-implicit-publisher and
bps-history respectively.

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
only its topic's stream.

## Out of scope (deliberately)

Multihop relaying and referral (bps-multihop), reorganisation policies (SWATCH, SPORE —
policy SWIPs over this protocol's events and actions, no new frames), bandwidth incentives
(bps-bw-incentives), broker discovery (SWIP-59 MEX; early deployments hardcode brokers),
history delivery mechanism (bps-history), implicit-publisher event sourcing
(bps-implicit-publisher), and **dynamic publisher-list changes** — grants/revocations
after genesis are deferred to a later revision; the `EXPLICIT_LIST` set is fixed at
`Open`.

## Conformance (definition of done)

An implementation is conformant when:

1. a broker enforces its per-topic capacity, publisher legitimacy, per-binding validation
   and dedup;
2. a subscriber re-verifies every message end-to-end (against the `Ack`-echoed
   `CohortSpec`) and detects (only) liveness faults;
3. the two worked configurations above interoperate across independent implementations
   against the frames in [bps.proto](assets/swip-60/bps.proto);
4. a `FULL` refusal is issued at capacity — and nothing else is (no referral).

## Backwards compatibility

New protocol; no existing behaviour changes. Reserved `Broadcast` frame fields hold the
multihop control plane, so bps-multihop extends without a version bump; self-contained
frames mean a change of stream model needs no format change either.

## References

Wire: [bps.proto](assets/swip-60/bps.proto) · origin:
[PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" · broker discovery:
[SWIP-59 MEX, PR #103](https://github.com/ethersphere/SWIPs/pull/103) · implementation:
bee [#5435](https://github.com/ethersphere/bee/pull/5435), bee-js
[#1151](https://github.com/ethersphere/bee-js/pull/1151)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
