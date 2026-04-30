---
SWIP: <to be assigned>
title: PubSub protocol
author: Viktor Tóth (@nugaon), Viktor Trón (@zelig)
discussions-to: <URL>
status: Draft
type: Standards Track (Networking)
created: 2026-04-30
---

## Simple Summary

A real-time messaging feature for dApps: WebSocket clients publish and subscribe to topic streams through Bee nodes, which act as the transport layer by leveraging their existing libp2p connections and bandwidth incentive system.

## Abstract

One designated node operates as a **Broker**: it accepts long-lived p2p streams and broadcasts them to all connected receivers. Other nodes connect as either a **Publisher** (send + receive) or a **Subscriber** (receive only). A WebSocket API on each Bee node serves as the bidirectional bridge between dApps and the p2p stream. Message format, validation and handshake logic are defined by a pluggable `Mode`; the initial mode `gsoc-ephemeral` uses SOC-style signing to authenticate pubsub messages in transit — these are not stored on the Swarm network as GSOC chunks. This SWIP also covers a decentralised broker discovery mechanism that locates a suitable broker for a topic based on Kademlia routing, with load balancing across multiple brokers deferred to a later milestone.

## Motivation

Swarm has two event-based primitives — GSOC and PSS — but both require full-node operation: the events arrive via Kademlia routing as part of pull/push syncing, which light clients do not participate in. For anyone not running a full node the only option is polling storage, which is slow and fundamentally not real-time. This leaves two unaddressed needs: real-time message exchange that does not require storing chunks on the network, and a way to channel network events that full nodes observe naturally out to light clients.

A brokered pub/sub layer fills several gaps at once:

- **Real-time applications** can exchange messages without long-term storage or polling.
- **Swarm network events** (e.g. incoming GSOC notifications) can be fanned out to light clients that would otherwise never see them.
- **Bandwidth incentives** — brokers are compensated for the data they transmit, creating a sustainable relay economy within Swarm.
- **Store-less uploads** — a publisher mode could let light clients push chunks to the network and pay by bandwidth rather than postage stamp.

The mode system ensures the protocol is not locked to any single message format and can evolve to cover these use cases incrementally.

## Specification

### Roles

```
Subscriber ──► (p2p stream, read-only)  ──►┐
                                            Broker  ──► rebroadcast to all subscribers
Publisher  ──► (p2p stream, read+write) ──►┘
```

| Role | Description |
|---|---|
| **Broker** | Opt-in (`--pubsub-broker-mode`). Validates publisher identity; re-broadcasts to all subscribers. |
| **Subscriber** | Dials broker; receives all broadcasts. |
| **Publisher** | Upgraded subscriber; sends mode-specific messages to the broker; also receives broadcasts. |

### Protocol

- **libp2p**: `pubsub/1.0.0`, stream name `msg`
- Topic address and mode are negotiated via **libp2p stream headers** (not the stream name)

#### Stream headers (client → broker)

| Key | Value |
|---|---|
| `pubsub-topic-address` | 32-byte topic address |
| `pubsub-mode` | 1-byte mode ID |
| `pubsub-readwrite` | `0x01` publisher / `0x00` subscriber |
| `pubsub-gsoc-owner` | 20-byte ETH address _(GSOC-Ephemeral mode, publisher only)_ |
| `pubsub-gsoc-id` | 32-byte SOC ID _(GSOC-Ephemeral mode, publisher only)_ |

#### Wire format

All broker→subscriber frames share a common 1-byte type prefix. `0x01` is permanently reserved at the service level (ping, valid across all modes); the broker sends a ping every 30 s to keep the long-lived stream alive. 
Mode-specific types start at `0x02`. 

```
Broker → any subscriber:
[ 0x01 ]   ping  (service level, all modes — no further fields)
[ 0x02+ ]  mode-specific frame
```

Publisher→Broker framing is mode-specific and carries **no message type prefix** — the broker knows the stream is a publisher stream from the `pubsub-readwrite` header set at connect time.

#### GSOC Ephemeral mode (mode 1)

Messages are SOC chunks. The topic address is `soc.CreateAddress(socID, ownerAddr)`, so only the holder of the topic private key can publish. The broker verifies the ECDSA signature on every message before broadcasting.

```
Publisher → Broker:
[ sig: 65 B ][ span: 8 B LE ][ payload: up to 4 KB ]

Broker → Subscriber:
[ 0x02 ][ SOC ID: 32 B ][ owner: 20 B ][ sig: 65 B ][ span: 8 B ][ payload ]  handshake (first msg)
[ 0x03 ][ sig: 65 B ][ span: 8 B ][ payload ]                                  data (subsequent)
```

The handshake frame carries SOC identity once on first broadcast; subsequent messages are data-only. The subscriber verifies `soc.CreateAddress(id, owner) == topicAddress` on handshake receipt.

### WebSocket API

```
GET /pubsub/{topic}   — WebSocket upgrade (subscriber or publisher)
GET /pubsub/          — list active topics
```

Connection parameters are accepted as HTTP headers or query params (query param fallback for browser WebSocket clients that cannot set custom headers):

- `Swarm-Pubsub-Peer` (required): multiaddr of the broker
- `Swarm-Pubsub-Gsoc-Eth-Address` + `Swarm-Pubsub-Gsoc-Topic` (optional, GSOC Ephemeral mode): enable publisher role

The WebSocket client sees the mode's raw payload; all p2p framing is transparent. For GSOC-Ephemeral mode: `[sig: 65 B][span: 8 B][payload]`.

### Multi-session multiplexer

Multiple WebSocket sessions on the same node and topic share one p2p stream:

```
WS session 1 ──┐
WS session 2 ──┤  SubscriberConn (shared stream + runMux goroutine)  ──► Broker
WS session N ──┘
```

`runMux` reads from the stream and fans out to per-session channels. Ref-counting (`refs`) ensures `FullClose` is called exactly once when the last session exits. If the stream dies, the shared conn is cleared immediately so new sessions open a fresh stream.

### Mode extensibility

The `Mode` interface decouples the protocol machinery from message semantics:

```
type Mode interface {
    Connect(...)         // open stream with appropriate headers
    HandleBroker(...)    // broker-side stream handler
    ReadBrokerMessage()  // decode one broker→subscriber frame
    FormatBroadcast()    // encode one broker→subscriber frame
    ValidatePublisher()  // verify publisher identity
    ...
}
```

New modes can be added by implementing `Mode` and registering a mode ID. Candidates include: unauthenticated broadcast, stake-gated publishing, Swarm-event fan-out, or bandwidth-incentivised chunk upload.

## Roadmap

### Milestone 1 — Direct messaging _(this SWIP)_

Two-directional messaging between a broker and its direct peers over a dedicated libp2p channel. Top-down message broadcast with per-message authentication.

Deliverables: pubsub protocol in Bee, WebSocket + topic-list API endpoints, pubsub JS library.

### Milestone 2 — Bandwidth incentives

The broker–subscriber stream is a metered channel: the subscriber pays the broker/forwarder per byte via chequebook cheques (incorporating Swarm's bandwidth incentive model).

- Subscription connection query returns incentive params (price in PLUR/byte, cheque threshold).
- Bee gains a pubsub cashout option for accumulated cheques.
- Light clients require a funded chequebook and a blockchain connection.

### Milestone 3 — Decentralised broker discovery

Make the broker underlay address parameter optional. Instead of the client hardcoding a broker, it discovers connection data from the topic's responsible neighbourhood using a two-step MIC-GSOC handshake (see MIC/MOC [SWIP-42](https://github.com/ethersphere/SWIPs/pull/80)).

```
Subscriber        Chosen broker peer (P)      Topic neighbourhood (E_a)
    │           (from current connections)                │
    │                     │                               │
    │ PubSub subscribe to │                               │
    │ Sub Resp GSOC ─────►│  mined: PO(SubRes_a, P) = 16  │
    │                     │                               │
    │── Sub Request MIC ──┼──────────────────────────────►│  PO(Req_a, E_a) >= d+1
    │   payload: E_a,     │                               │  (routed by pull/push sync)
    │   chequebook addr,  │                               │
    │   Sub Resp SOC params (ID + ephemeral key)          │
    │                     │                               │
    │                     │◄─ Sub Response GSOC(s) ───────│  brokers sign with ephemeral key
    │                     │   payload: overlay, underlay, │  (routed to P by pull/push sync)
    │                     │           incentive params,   │
    │                     │           HIVE connection list│
    │◄──── GSOC event ────│                               │
    │                     │                               │
    │── libp2p connect ───┼──────────────────────────────►│ subscriber picks a pubsub network
```

The Sub Request signing key is derived from a well-known string, requiring no out-of-band coordination:

```
SubReqKey = keccak256("SUB_REQUEST")
```

The Sub Request is a MIC chunk (SOC signed by `SubReqKey`). Its ID is mined so the chunk address falls in the topic neighbourhood; pull/push sync routes it there naturally by proximity. The Sub Request identity must be mined until `PO(Req_a, E_a) >= storage_depth + 1` (or `= 16` if the current storage depth is unavailable).

The Sub Response is a GSOC rather than a MIC deliberately: a MIC subscription listens by Ethereum address, so a well-known signing key would cause all concurrent discovery sessions on P to receive each other's responses. A GSOC subscription listens on a specific SOC address `soc.CreateAddress(randomID, ephemeralAddr)` — unique per subscriber — so responses are always isolated.

The subscriber pre-mines a Sub Response SOC identifier and generates an ephemeral key, both included in the Sub Request payload. Broker nodes in the topic neighbourhood sign the Sub Response as a GSOC using the provided ephemeral key. The subscriber listens for GSOC events on the mined Sub Response address to collect broker replies.

The Sub Response SOC address must be mined very close to P's overlay (`PO = 16`). This is required because the current GSOC implementation at the moment stores only one payload per address: if multiple brokers respond to the same address, the last writer wins and earlier responses are lost before pull syncing them. Full multi-response support would require GSOC to retain multiple payloads per address, which is left as a future improvement.

Both sides require postage stamps for their uploads: the subscriber needs a mutable stamp for the Sub Request MIC, and each responding broker needs a mutable stamp for its Sub Response GSOC. Alternatively, once [SWIP-36](https://github.com/ethersphere/SWIPs/pull/70) (free uploads) is adopted, both stamp requirements can be lifted.

New API endpoint: `GET /pubsub/discover/{topic}?mode=<id>` — returns connection data from the topic's neighbourhood.

### Milestone 4 — Load balancing and multi-level forwarding

Balance subscriber load across multiple brokers. Introduce HIVE-like forwarder discovery and a multi-level forwarding tree so traffic is distributed across willing relay nodes rather than concentrated on a single broker.

```
              Root (broker / neighbourhood node)
             /        |         \
        Relay A    Relay B    Relay C
        /    \        |
    Sub 1   Sub 2   Sub 3   ...
```

- Forwarders earn relay fees; they are incentivised to forward to more than one downstream client.
- Light-client-to-light-client connections (both behind NAT) use DCUtR with the broker as the relay, enabling direct p2p streams without a persistent intermediary.

## Rationale

- **Broker topology** keeps the subscriber implementation simple and connection count low; brokers can be specialised nodes.
- **GSOC Ephemeral mode** reuses existing SOC signing infrastructure and provides per-message authenticity without additional key exchange. It is the first mode, not the only one.
- **Shared p2p stream per topic per node** avoids redundant connections when multiple browser tabs open the same topic.
- **Type-byte framing** with a reserved service-level slot (`0x01` = ping) allows future modes to be added without breaking the keepalive mechanism.

## Backwards Compatibility

This is a new protocol (`pubsub/1.0.0`) with no overlap with existing Bee protocols. Broker mode is opt-in. No existing behaviour is affected.

## Test Cases

- Broker correctly re-broadcasts a valid publisher message to all connected subscribers.
- Broker rejects a message that fails mode validation (e.g. invalid SOC signature in GSOC-Ephemeral mode).
- Multiple WebSocket sessions on the same topic share one p2p stream (ref count increments/decrements correctly).
- Stream failure clears the shared conn; next session opens a fresh stream.
- Ping frames are consumed at service level and not forwarded to the WebSocket client.

## Implementation

Reference implementation (Milestone 1):
- Bee node: [ethersphere/bee#5435](https://github.com/ethersphere/bee/pull/5435) (`feat/pubsub` branch)
- bee-js client: [ethersphere/bee-js#1151](https://github.com/ethersphere/bee-js/pull/1151)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
