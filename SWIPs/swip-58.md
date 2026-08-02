---
SWIP: 58
title: MEX — anchored message exchange with a previously unknown node
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track (Networking)
created: 2026-07-31
---

<!-- Extracted and generalised from the PubSub SWIP (ethersphere/SWIPs PR #93), Milestone 3. -->

## Simple Summary

Any node capable of using the push-sync and retrieval protocols — including light nodes that
are potentially non-reachable (NAT'd, sync-less) — can carry out a private, mutually
authenticated exchange of messages with a previously unknown full node in the neighbourhood
of a pre-agreed anchor address. No on-chain registry, no prior acquaintance, no direct
connectability required.

## Abstract

MEX (Message EXchange) is a two-phase rendezvous and exchange pattern built entirely from
existing Swarm primitives — mined owner chunks (MIC/MOC, SWIP-42), single-owner chunks,
push-sync with storage receipts, and retrieval:

1. **Anchored request.** The requester mines an ephemeral keypair such that a single-owner
   chunk with a well-known, constant, service-specific ID lands in the neighbourhood of the anchor.
   Push-sync routes it there; any full node providing the service detects it by the ID.
   The storage receipt travelling back to the requester reveals the responder's public key
   and overlay address — the two parties now know each other, and share an ECDH secret.
2. **Encrypted exchange.** The requester sends an encrypted request payload as a GSOC to
   the responder; the responder stores an encrypted response chunk locally at an address
   mined to be closest to itself, where the requester fetches it by ordinary retrieval.

All payloads after Phase 1 are encrypted with keys derived from the ECDH shared secret;
per-session ephemeral keys give forward secrecy. The responder needs no reachability
guarantee toward the requester: every leg of the exchange rides on push-sync or retrieval.

## Motivation

Several protocols need the same opening move: *contact whichever node is responsible for /
provides service at a given address, without knowing who that is*. Today each protocol
would have to reinvent it.

The pattern was worked out as Milestone 3 of the PubSub SWIP (broker discovery: a
subscriber locates a broker for a topic — the anchor is the topic address). This SWIP
extracts it so that it can be referenced independently: by PubSub as a dependency, and by
MIC/MOC (SWIP-42) as a clear use case — and so that the small amount of cryptography lives
here rather than distracting from the PubSub specification.

Other plausible instantiations (illustrative, not specified here): rendezvous for NAT
hole-punching coordination, contacting the registered provider of a DSN service area
(SWIP-39) — generally, any handshake with "the closest node to X that runs service Y".

Extracting the pattern into one SWIP gives these protocols a single, security-reviewed
primitive with well-defined parameters, instead of near-copies with drifting details.

## Specification

### Terminology

- **Anchor** `A` — a pre-agreed 32-byte address. Its derivation is out of scope and
  irrelevant to MEX itself — it carries meaning only for the service using it (a topic
  address, a service area, overlay-derived, hard-coded by an application, registered in a
  contract, …). MEX only requires that both parties know `A`.
- **Service ID** `SID` — a well-known 32-byte SOC identifier that scopes the exchange to a
  service, e.g. `SID = keccak256("PUBSUB-REQUEST")`. Each MEX-based protocol MUST define
  its own `SID`.
- **Requester** — the initiating node. MUST be able to push-sync chunks and retrieve chunks. MAY be a light node; MAY be non-reachable.
- **Responder** — a full node in the anchor's neighbourhood that provides the service:
  it watches incoming SOCs whose ID equals `SID` (a MIC subscription, SWIP-42).
- **Session** — one request/response exchange, identified by the requester's ephemeral key.

### Parameters

| name | default | meaning |
|---|---|---|
| `PO_MIN` | 16 | minimum proximity order for mined addresses relative to their target |
| `T_RESPONSE` | 30 s | responder's watch window for the Phase-2 GSOC |

### Prerequisites

- Responders maintain a subscription filter for incoming SOCs with `id == SID`
  (SWIP-42 MIC subscription). This is a single, network-wide filter per service.
- Targeted chunk delivery and retrieval to/from the closest responsible node
  (cf. [bee#5081](https://github.com/ethersphere/bee/pull/5081)).
- The requester needs a valid postage stamp for its two uploads (liftable if/when free
  uploads, SWIP-36, is adopted). The responder never needs a stamp: its response chunk is
  stored locally and served on retrieval.

### Phase 1 — anchored request (MOC)

1. The requester generates a random 32-byte session nonce `id_S`.
2. The requester mines an ephemeral keypair `(sk_S, pk_S)` such that
   `soc.CreateAddress(SID, ETH(pk_S))` falls within the anchor's neighbourhood
   (PO ≥ `PO_MIN` relative to `A`).
3. The requester uploads a MOC with `id = SID`, `owner = ETH(pk_S)`, payload `id_S`.
   Push-sync routes the chunk to the anchor neighbourhood.
4. A responder detects the incoming SOC (`id == SID`), stores it, extracts `id_S`, and
   associates `pk_S` with the session.
5. The responder returns a **storage receipt**; from its signature the requester extracts
   the responder's public key `pk_B` and overlay address.
6. The responder subscribes to GSOC events on `soc.CreateAddress(id_S, ETH(pk_S))`,
   timing out after `T_RESPONSE`.

### Phase 2 — encrypted exchange (GSOC + retrieval)

7. The requester mines a SOC ID `id_B` such that `soc.CreateAddress(id_B, ETH(pk_B))` is
   closest to the responder's overlay (PO ≥ `PO_MIN`).
8. The requester uploads a SOC with `id = id_S`, `owner = ETH(pk_S)`, whose payload is the
   service-specific **request message** `Q`, encrypted (see Encryption):
   `payload = AES-256-GCM(req_key, nonce_req, Q ‖ id_B)`.
9. The responder — subscribed at exactly that SOC address — receives it, decrypts, and
   obtains `Q` and `id_B`.
10. The responder verifies `soc.CreateAddress(id_B, ETH(pk_B))` lies within the anchor
    neighbourhood if the service requires it (anchor-scoped response), or within its own
    neighbourhood otherwise.
11. The responder computes the service-specific **response message** `R`, encrypts it with
    `res_key`, signs a SOC with its own key `sk_B` at address
    `soc.CreateAddress(id_B, ETH(pk_B))`, and **stores it locally** — no upload, no stamp.
12. The requester fetches `soc.CreateAddress(id_B, ETH(pk_B))` via ordinary retrieval; the
    lookup routes to the responder as closest node. The requester completes the lookup by retrieving and validating the SOC chunk, and decrypts `R`.

The content of `Q` and `R` is opaque to MEX and defined per service (connection
parameters, incentive terms, capability descriptors, further keys, …).

```mermaid
sequenceDiagram
    participant S as Requester
    participant N as Anchor neighbourhood
    participant B as Responder (full node)

    Note over S: mine (sk_S, pk_S): SOC_ADDR(SID, ETH(pk_S)) ∈ NH(A)
    S->>N: push-sync MOC(id=SID, owner=ETH(pk_S), payload=id_S)
    N->>B: sync delivers to closest service node
    B-->>S: storage receipt → pk_B, overlay_B
    Note over B: watch GSOC at SOC_ADDR(id_S, ETH(pk_S)), timeout T_RESPONSE
    Note over S: mine id_B: SOC_ADDR(id_B, ETH(pk_B)) closest to overlay_B
    S->>N: push-sync SOC(id=id_S, owner=ETH(pk_S), payload=ENC(req_key, Q ‖ id_B))
    N->>B: sync delivers
    Note over B: decrypt → Q, id_B; store SOC(id_B, ETH(pk_B), ENC(res_key, R)) locally
    S->>N: retrieve SOC_ADDR(id_B, ETH(pk_B))
    N-->>B: routed to closest node
    B-->>S: response chunk
    Note over S: decrypt R
```

### Variant: known responder — leakless first contact via PSS

When the responder's identity — public key `pk_B` and overlay — is already known to the
requester (a broker advertised or otherwise listed, a provider learned from a registry, an
identity retained from a previous exchange), the anchored discovery of Phase 1 serves no
purpose, and the exchange shortens from three legs to two:

1. The requester sends the first message as a **PSS trojan**: a content-addressed chunk
   mined so that its address falls within the responder's neighbourhood, whose payload is
   encrypted to `pk_B` and carries the requester's ephemeral `pk_S`, the request `Q`, and
   the mined response ID `id_B` (as in Phase 2).
2. The responder decrypts, and as in steps 11–12 stores the encrypted response SOC at
   `soc.CreateAddress(id_B, ETH(pk_B))` locally, where the requester fetches it by ordinary
   retrieval.

Key derivation is unchanged (`pk_S` now travels inside the trojan payload instead of a
MOC; the receipt is not needed since `pk_B` is known). The mining effort moves from
owner-key-vs-anchor to trojan-address-vs-overlay.

The property gained is stronger than anything bare MEX offers: to every observer the
trojan is indistinguishable from ordinary chunk traffic and the response is an ordinary
retrieval, so **not even the fact that a service interaction is taking place leaks** —
contrast Security consideration 2, where anchored MEX necessarily reveals the `SID`@`A`
event. Where responder identity is available, this variant is therefore the better private
connection: leakless, and one leg shorter.

The two forms compose: a single anchored exchange teaches the requester the responder's
identity, after which all further contact with that responder can take the leakless path.
The anchor leak is thus paid **at most once per responder relationship — zero or one
times**: zero when the identity is already known through advertisement, listing, or
registry; one when it must be bootstrapped in-band. Knowing the responder's identity is
never a prerequisite, merely a good-to-have that upgrades the exchange.

### Encryption

Both directions use AES-256-GCM keyed from the ECDH shared secret, computable by both
parties after Phase 1: the requester knows `sk_S` and `pk_B` (from the receipt); the
responder knows `sk_B` and `pk_S` (from the MOC).

```
shared    = ECDH(sk_S, pk_B) = ECDH(sk_B, pk_S)
req_key   = keccak256(shared ‖ 0x00)     // Phase-2 request payload
res_key   = keccak256(shared ‖ 0x01)     // response payload
nonce_req = keccak256(req_key)[:12]      // deterministic per key (12 bytes)
nonce_res = keccak256(res_key)[:12]      // deterministic per key (12 bytes)
```

Separate directional keys avoid nonce reuse. Because `sk_S` is freshly mined per session,
keys and nonces are never reused (GCM requirement) and compromise of long-term node keys
does not expose past sessions (forward secrecy on the requester side).

### Continued exchange

None is needed: MEX is deliberately a single request/response round trip. A completed
session yields mutual identity and a shared secret; anything longer-lived is a different
protocol layered on top. Non-normatively: a natural such layering is a "Signal on Swarm"
style ratchet (triple-ratchet key agreement with the *outbox feed rotated according to the
ratchet state*), which would inherit MEX's reachability properties. Specifying it is out
of scope here.

## Rationale

The two-phase MOC/GSOC construction avoids the failure modes of simpler designs:

- **No on-chain registry** — the responder's public key and overlay are learned in-band
  from the storage receipt; discovery has no blockchain dependency.
- **No concurrent-session collision** — the response is a separate chunk at a unique mined
  address per session; simultaneous requesters never interfere.
- **No caching problem** — the response is a new chunk stored locally by the responder,
  not an overwrite of the request, so stale cached copies cannot be served.
- **No single-node targeting** — any service node in the anchor neighbourhood can pick up
  the Phase-1 MOC; if one is offline, another responds.
- **Address-level over owner-level filtering** — the Phase-2 watch matches the full SOC
  address `soc.CreateAddress(id_S, ETH(pk_S))`, not merely the owner, so the responder
  processes exactly the chunk it expects.
- **Works for the unreachable** — every leg is an upload the requester pushes or a chunk
  the requester pulls (i.e. retrieves); at no point must anyone dial the requester or know wherever the message came from.

## Security Considerations

1. **Phase-1 flooding** — an attacker can flood MOCs with `id = SID` toward an anchor.
   Each costs the responder only a lightweight watch entry (timeout `T_RESPONSE`), while
   the attacker must mine a fresh keypair into the neighbourhood per chunk and pays
   bandwidth per forwarded chunk. Responders SHOULD cap concurrent pending sessions.
   Note on duplicates: push-sync delivery is inherently **at-least-once** — honest retries
   (pusher re-pushing until receipt, forwarders rerouting) deliver the same chunk to the
   closest node repeatedly, and the subscription layer dispatches every delivery regardless
   of whether the chunk is already stored (verified in bee: dispatch precedes the store's
   silent dedup). Responders MUST therefore create at most one session per chunk address —
   a correctness requirement under normal operation, which also neutralises adversarial
   **replay** of captured Phase-1 chunks (which bypasses the mining cost and is otherwise a
   zero-cost session-amplification vector; with dedup it is worth only its bandwidth).
2. **On-path observers and metadata** — Phase-1 traffic is plaintext by design: forwarders
   and anchor-neighbourhood nodes learn `SID`, `id_S`, `ETH(pk_S)` — hence the watched
   response address — and, from the returning receipt, `pk_B`. All of these are treated as
   public. None of it yields any capability against the session: a valid SOC at the watched
   address requires `sk_S`, and payload keys require a private ECDH share. The metadata
   leak is owned precisely as:
   - *what leaks*: that **some** node is initiating a `SID` exchange at anchor `A` at this
     time; the responder's identity (`pk_B`, overlay); per-anchor session timing and
     frequency.
   - *what does not*: the requester's identity — `(sk_S, pk_S)` is ephemeral and mined per
     session, `id_S` is a random nonce, so sessions link neither to the requester's node
     identity nor to each other. (As with any upload, the first-hop forwarder knows the
     origin of the request.)
   An observer is also ideally placed to race as responder — see consideration 5. Services
   for which the leaking metadata is itself sensitive MUST NOT use bare anchored MEX; if
   the responder's identity is known in advance, the leakless PSS variant applies (see
   *Variant: known responder*).
3. **Mining cost asymmetry** — the requester performs two `PO_MIN`-depth minings per
   session (owner key, response ID). At `PO_MIN = 16` this is fast on commodity hardware;
   services MAY raise `PO_MIN` to price sessions higher.
4. **Timing window** — Phase 2 (mine `id_B` + upload) must complete within `T_RESPONSE`.
   At depth 16 mining is sub-second; services with slower requesters SHOULD size
   `T_RESPONSE` accordingly.
5. **Responder authenticity** — the storage receipt signature binds `pk_B` to the node
   that actually stored the request in the anchor neighbourhood. MEX authenticates *a*
   closest service node, not a particular operator; services needing operator identity
   must layer it into `R` (e.g. via DSN registry attestations, SWIP-39).

## Backwards Compatibility

MEX introduces no new wire protocol and no new chunk type: it composes MIC/MOC
subscriptions (SWIP-42), single-owner chunks, push-sync receipts, and retrieval. Nodes not
participating see ordinary SOC traffic. Prerequisite behaviours (SID subscription filter,
targeted delivery to closest node) are opt-in per service.

## Test Cases

- End-to-end exchange succeeds between a light, NAT'd requester and a responder in the
  anchor neighbourhood, with correct `Q`/`R` recovery on both sides.
- A second requester running concurrently against the same anchor and SID completes
  without interference (distinct sessions, distinct response addresses).
- A forged Phase-2 SOC at the watched address is rejected (AEAD failure) and the genuine
  one still completes within `T_RESPONSE`.
- Watch entries expire after `T_RESPONSE`; the pending-session cap is enforced.
- Responder's locally stored response chunk is served on retrieval without a postage stamp.

## Implementation

The pattern is specified as PubSub Milestone 3 in
[ethersphere/SWIPs PR #93](https://github.com/ethersphere/SWIPs/pull/93); implementation
groundwork in [bee PR #5435](https://github.com/ethersphere/bee/pull/5435) (pubsub) and
[bee PR #5486](https://github.com/ethersphere/bee/pull/5486) (MIC/MOC). A standalone MEX
library API is TBD.

## Copyright

Copyright and related rights waived via
[CC0](https://creativecommons.org/publicdomain/zero/1.0/).
