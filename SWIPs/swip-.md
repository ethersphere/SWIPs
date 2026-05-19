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

The broker–subscriber stream is a metered channel: the subscriber pays the broker/forwarder per chunk via chequebook cheques (incorporating Swarm's bandwidth incentive model).

- Subscription connection query returns incentive params (price in PLUR/chunk, cheque threshold).
- Bee gains a pubsub cashout option for accumulated cheques.
- Light clients require a funded chequebook and a blockchain connection.

### Milestone 3 — Decentralised broker discovery

Make the broker underlay address parameter optional. Instead of the client hardcoding a broker, it discovers connection data from a specific broker node using a MOC-based dead-drop handshake (see MOC [SWIP-42](https://github.com/ethersphere/SWIPs/pull/80)). Unlike neighbourhood-broadcast approaches, the request targets a single broker: the subscriber mines a SOC owner key so the resulting chunk address is closest to the broker's overlay address. During push-sync the chunk is delivered directly to the closest node (analogous to [bee#5081](https://github.com/ethersphere/bee/pull/5081)), ensuring the broker receives it without neighbourhood-wide replication. The subscriber encrypts the payload to the broker's public key, and the broker responds by overwriting the same chunk address.

#### On-chain broker registry

The subscriber must know the target broker's overlay address and public key before initiating discovery. A smart contract — either extending the balanced neighbourhood registry ([SWIP-39](https://github.com/ethersphere/SWIPs/pull/74)) with pubkey field or deployed as a standalone PubSub registry — maps topics to broker nodes. Each registry entry contains:

| Field | Description |
|---|---|
| `overlay` | 32-byte Swarm overlay address |
| `pubkey` | 65-byte secp256k1 public key (Swarm key) |

Brokers register on-chain when they opt into `--pubsub-broker-mode`. The subscriber queries the registry to obtain `(overlay_B, PK_B)` for a chosen broker.

The broker's secp256k1 public key must be the same key whose private counterpart the node uses for Swarm chunk-level operations (its Swarm key), so that ECIES decryption in the detection step works without additional key management.

#### Protocol constants

```
SOC_ID = keccak256("PUBSUB-REQUEST")        // 32-byte fixed SOC identifier
```

All discovery requests across the network share this single SOC ID. Isolation between concurrent sessions is achieved by the uniqueness of the mined owner key, not by the ID.

#### Workflow

```
Subscriber (S)                                       Broker (B)
    │                                                     │
    │  1. Registry lookup                                 │
    │     (overlay_B, PK_B) ◄── on-chain registry         │
    │                                                     │
    │  2. Mine secp256k1 key pair (k, K = k·G):           │
    │     a      = ethAddr(K)                             │
    │     SOC_a  = keccak256(SOC_ID ‖ a)                  │
    │     PO(SOC_a, overlay_B) ≥ depth + 1                │
    │                                                     │
    │  3. Build request payload P:                        │
    │     { topic, k, chequebook_addr, ... }              │
    │     C_req = ECIES_Encrypt(PK_B, P)                  │
    │                                                     │
    │── 4. Upload MOC(id=SOC_ID, key=k, data=C_req) ────►│
    │      (pull/push sync routes to B's neighbourhood)   │
    │                                                     │
    │                      5. Detect incoming SOC:         │
    │                         id == SOC_ID ?               │
    │                         chunk in my neighbourhood ?  │
    │                         ECIES_Decrypt(sk_B, C_req)   │
    │                         → success: chunk is for me   │
    │                         → failure: ignore            │
    │                                                     │
    │                      6. Extract k from payload       │
    │                         Build response R:            │
    │                         { overlay, underlay,         │
    │                           incentive_params,          │
    │                           hive_conn_list }           │
    │                         sym_key = keccak256(k)       │
    │                         C_res = AES-256-GCM(sym_key, │
    │                                   nonce, R)          │
    │                         Sign new SOC with k          │
    │                         → same SOC_a (overwrites)    │
    │                                                     │
    │                     ─── 7. Store response SOC       │
    │                         locally (same chunk addr)    │
    │                                                     │
    │◄── 8. Fetch SOC_a ─────────────────────────────────│
    │       Decrypt: AES-256-GCM(keccak256(k), nonce,     │
    │                             C_res) → R              │
    │       Extract broker connection info                 │
    │                                                     │
    │── 9. libp2p connect(underlay_B) ───────────────────►│
```

#### Mining the request key

The subscriber iterates secp256k1 private keys deterministically starting from a seed derived from its own public key until the resulting SOC address is closest to the target broker's overlay:

```
seed ← keccak256(PK_subscriber)           // deterministic starting point
i    ← 0
repeat:
    k   ← keccak256(seed ‖ i)             // 32-byte candidate private key
    K   ← secp256k1_pubkey(k)
    a   ← keccak256(K) [12:]              // 20-byte Ethereum address
    sa  ← keccak256(SOC_ID ‖ a)           // 32-byte SOC chunk address
    i   ← i + 1
until PO(sa, overlay_B) ≥ storage_depth + 1
```

Each iteration requires one secp256k1 scalar multiplication plus two Keccak-256 hashes. The expected number of iterations is `2^d` for a target depth `d`. At depth 12 this is ~4 096 iterations — well under a second on commodity hardware.

#### Request encryption — ECIES on secp256k1

The request payload is encrypted with the Elliptic Curve Integrated Encryption Scheme (ECIES) — the same scheme and library used in Ethereum's devp2p/RLPx handshake (`go-ethereum/crypto/ecies`):

1. Generate ephemeral key pair `(e, E = e·G)`.
2. Shared secret `S = ECDH(e, PK_B)`.
3. Key derivation: `(enc_key ‖ mac_key) = HKDF-SHA256(S)`.
4. `ciphertext = AES-128-CTR(enc_key, plaintext)`.
5. `tag = HMAC-SHA256(mac_key, ciphertext)`.
6. Output: `E ‖ ciphertext ‖ tag`.

Only the holder of `sk_B` can derive the shared secret and decrypt. The ephemeral key `e` is discarded after encryption, providing forward secrecy per discovery session. Neighbourhood peers that store or forward the chunk cannot read its contents.

#### Response encryption — AES-256-GCM (symmetric)

The response is encrypted symmetrically using the mined private key `k` as key material. Both parties possess `k`: the subscriber mined it; the broker extracted it from the ECIES payload.

```
sym_key = keccak256(k)                          // 32 bytes → AES-256 key
nonce   = keccak256(keccak256(k)) [:12]         // 12 bytes, deterministic
C_res   = AES-256-GCM_Encrypt(sym_key, nonce, response_payload)
```

AES-256-GCM provides authenticated encryption: on decryption the subscriber verifies both confidentiality and integrity. Because `k` is unique per discovery session (freshly mined), the `(sym_key, nonce)` pair is never reused, satisfying GCM's uniqueness requirement.

No party other than the subscriber and the target broker can derive `sym_key`, since `k` was transmitted inside the ECIES envelope.

#### Broker detection logic

A node running in broker mode applies the following filter to every incoming SOC chunk synced to its neighbourhood:

1. **ID check** — SOC ID equals `keccak256("PUBSUB-REQUEST")`?
2. **Neighbourhood check** — chunk address within this node's storage responsibility?
3. **Decryption attempt** — `ECIES_Decrypt(sk_self, payload)`. Failure means the chunk is addressed to a different broker; discard silently.
4. **Payload validation** — extract `(topic, k, ...)`. Verify that `keccak256(SOC_ID ‖ ethAddr(k·G))` matches the chunk address.
5. **Response** — construct, encrypt, and store the modified response MOC signed with `k`.

Step 3 is the key isolation mechanism: even though all broker nodes in the neighbourhood may see the same constant SOC ID, only the broker whose public key was used for ECIES encryption can successfully decrypt and act on the request.

#### Postage stamps

The subscriber needs a postage stamp for the MOC request upload. The broker needs a postage stamp for the MOC response upload. Once [SWIP-36](https://github.com/ethersphere/SWIPs/pull/70) (free uploads) is adopted, both stamp requirements can be lifted.

#### Known limitations

1. **Single-node targeting** — The request reaches exactly one broker. If that broker is offline or unresponsive, the subscriber must time out and retry with another registry entry or initiating multiple parallel requests toward different brokers.
2. **On-chain dependency** — The subscriber must read the broker registry contract to learn `(overlay, pubkey)`. Light clients already require blockchain access for Swarm (postage stamp verification), so the marginal cost is low. The registry can be cached or mirrored off-chain.
3. **Concurrent requester collision** — If two subscribers targeting the same broker mine the same owner key (i.e. arrive at the same SOC address), the second request overwrites the first. Because key derivation is seeded from the subscriber's own public key, this can only happen if two nodes share the same Swarm key — an invalid network state. In practice the probability is negligible
4. **ECIES decryption cost** — The SOC ID `keccak256("PUBSUB-REQUEST")` is a global constant shared by all discovery requests. Every broker node must attempt ECIES decryption (one ECDH scalar multiplication) on every incoming SOC with this ID that falls within its neighbourhood, even if the chunk is addressed to a different broker. The cost scales with the number of concurrent discovery requests across all brokers in a neighbourhood. Under normal load this is negligible, but the asymmetry is exploitable (see point 6).
5. **Replay attacks** — A neighbourhood peer that observes a discovery request chunk can re-upload the identical bytes, causing the broker to re-process the request and overwrite its previous response. The attacker cannot read the request (ECIES-encrypted) or the response (AES-256-GCM-encrypted with `k`), so the damage is limited to wasted broker computation and potential disruption if the legitimate subscriber has not yet fetched the response. Implementations should consider deduplicating detection by chunk address to suppress repeated processing.
6. **DoS via discovery flooding** — An attacker can cheaply mine many keys targeting a specific broker's neighbourhood and flood it with discovery request chunks. Each chunk forces an ECIES decryption attempt on the broker. The attacker's cost is key mining (~2^d iterations at depth d) plus a postage stamp per chunk; the broker's cost is one ECDH operation per chunk. Postage stamp economics provide a baseline rate limit, but brokers may additionally rate-limit detection processing or require a proof-of-work token inside the ECIES payload.

New API endpoint: `GET /pubsub/discover/{topic}?mode=<id>` — returns broker connection data for the given topic.

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
