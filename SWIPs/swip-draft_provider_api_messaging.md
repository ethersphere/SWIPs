---
SWIP: <to be assigned>
title: Swarm Provider API — Messaging Extension (PSS & GSOC)
author: Florian Glatz (@heckerhut)
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
status: Draft
type: Standards Track
category: Interface
created: 2026-07-13
requires: <Swarm Provider API SWIP>
---

## Simple Summary

An extension to the [Swarm Provider API (`window.swarm`)](./swip-draft_provider_api.md)
that adds **real-time messaging**: encrypted point-to-point delivery (PSS) and
topic broadcast (GSOC), including a **subscription primitive** for receiving
pushed messages — the first streaming surface in the provider API, which is
otherwise entirely request/response.

## Abstract

The core Swarm Provider API specifies fifteen request/response RPC methods and
two lifecycle events (`connect`, `disconnect`). It has no way for a web
application to *receive* asynchronous data: every method resolves once, and the
only push signals concern the connection itself. Real-time applications —
collaborative editors, chat, presence, live dashboards — need a channel over
which the node delivers incoming messages as they arrive.

This extension adds that channel. It specifies:

- **`swarm_subscribe` / `swarm_unsubscribe`** — open and close a long-lived
  subscription to a GSOC address (topic broadcast) or a PSS topic
  (point-to-point inbox). Delivery is via a new **`message`** event, following
  the subscription-id + event pattern established by
  [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193)'s `eth_subscribe`.
- **`swarm_sendPss`** — send an encrypted point-to-point message to a recipient
  identified by their PSS public key.
- **`swarm_sendGsoc`** — broadcast a message on a topic that any subscriber to
  the derived GSOC address receives.
- **`swarm_getMessagingIdentity`** — disclose this origin's PSS public key and
  routing target, so peers can address messages to it.

PSS and GSOC are existing Swarm/Bee primitives; this extension does not define
them, only their exposure at the provider boundary with consent and
origin-scoping consistent with the core specification. Messages are best-effort,
unordered, and may be duplicated; applications requiring ordering or exactly-once
semantics MUST layer that themselves (a CRDT such as Yjs satisfies this
naturally).

## Motivation

The core API's request/response shape is a deliberate, minimal foundation, but
it structurally cannot express "tell me when something arrives." Applications
work around this by polling — repeatedly reading a feed or SOC on a timer —
which trades latency for request volume and never reaches interactive speed. A
collaborative document synced by polling feeds every few seconds is usable for
asynchronous editing but cannot show live cursors or keystroke-level updates.

Swarm already has the transport primitives for real-time messaging:

- **PSS** (Postal Service over Swarm): trojan chunks encrypted to a recipient's
  public key and routed toward a neighborhood — encrypted, sender-anonymous,
  point-to-point.
- **GSOC** (Graffiti Single Owner Chunk): a Single Owner Chunk at a
  deterministically-derivable address that many parties can write to and
  subscribe to — a broadcast "mailbox at a well-known address."

Historically these required a full node to *receive* (Bee has no push delivery
to light nodes). Light-node implementations can now receive by pulling from the
target neighborhood and decrypting locally, making send **and** receive viable
on the kind of light/ultra-light node a browser embeds. This extension exposes
that capability to dApps so the decentralized web gains real-time collaboration
without a coordination server.

### Design Goals

Identical to the core specification, plus:

- **One new interaction pattern, minimally.** Add exactly one streaming shape
  (subscription-id + `message` event), reusing EIP-1193 precedent, rather than
  several bespoke callback styles.
- **Hide protocol mechanics.** DApps address a *topic* or a *recipient key*; the
  provider handles trojan construction, neighborhood targeting, GSOC owner
  mining, nonce mining, encryption, and the receive pipeline.
- **Tolerate an unreliable substrate honestly.** The API surfaces best-effort,
  unordered, at-least-once delivery as such and does not pretend otherwise.

## Specification

This document is an **extension**. It adds methods, one event, error reasons,
capability fields, and one permission tier to the core Swarm Provider API. It
changes none of the existing method semantics. An implementation MAY conform to
the core specification without this extension; an implementation of this
extension MUST also conform to the core specification.

### Feature Detection

Because this extension is optional, dApps MUST NOT assume its presence from the
core `specVersion` alone. The core `swarm_getCapabilities` result is extended
with a `features` array; an implementation of this extension MUST include the
string `"messaging"` in it:

```javascript
const caps = await window.swarm.getCapabilities()
if (caps.features?.includes('messaging')) {
  // PSS/GSOC methods are available
}
```

`swarm_getCapabilities` is additionally extended with messaging limits (see
[Limits](#limits)). Both `features` and the new limit fields MUST be available
before `swarm_requestAccess` — the core spec makes `swarm_getCapabilities`
permission-free, and these are static capability facts, not user data.

### Convenience Methods

Implementations of this extension MUST expose these convenience wrappers, in
addition to the core set:

```javascript
window.swarm.getMessagingIdentity()                        // swarm_getMessagingIdentity
window.swarm.subscribe({ kind, topic, history })           // swarm_subscribe
window.swarm.unsubscribe({ subscriptionId })               // swarm_unsubscribe
window.swarm.sendPss({ topic, recipient, targets, data })  // swarm_sendPss
window.swarm.sendGsoc({ topic, data })                     // swarm_sendGsoc
```

Each MUST be equivalent to calling `window.swarm.request()` with the
corresponding method name and params.

### Events

This extension adds one standard event:

| Event | Data | Description |
|---|---|---|
| `message` | `SubscriptionMessage` (below) | Emitted for each message delivered on any active subscription owned by the calling origin. |

**`SubscriptionMessage`:**

```javascript
{
  type: "swarm_subscription",   // constant; disambiguates from other future event payloads
  subscription: string,          // the subscriptionId this message belongs to
  result: {
    kind: "gsoc" | "pss",       // matches the subscription kind
    key: string,                 // GSOC: the 64-hex SOC address; PSS: the 64-hex topic
    data: string,                // base64-encoded decrypted payload
    encoding: "base64",
    receivedAt: number           // ms unix timestamp the provider received it
  }
}
```

The `message` event MUST fire only for subscriptions created by the calling
origin (origin-scoped, same isolation as feeds and tags). An implementation MUST
NOT deliver a message to an origin that did not open the corresponding
subscription.

Consistent with EIP-1193, `swarm.on('message', handler)`,
`swarm.removeListener('message', handler)`, and `swarm.removeAllListeners('message')`
MUST be supported.

### Error Format

Unchanged from the core specification. This extension reuses the standard error
codes (`4001`, `4100`, `4200`, `4900`, `-32602`, `-32603`) and adds the
following `data.reason` values for `-32602` (Invalid Params):

| Reason | Applicable Methods | Meaning |
|---|---|---|
| `invalid_topic` | `swarm_subscribe`, `swarm_sendPss`, `swarm_sendGsoc` | Topic is missing or not a valid non-empty string / 64-char hex where hex is required. |
| `invalid_address` | `swarm_subscribe` | An explicit GSOC `address` is not a valid 64-char hex. |
| `invalid_recipient` | `swarm_sendPss` | Recipient public key is missing or not a valid 33-byte compressed secp256k1 key (66-char hex). |
| `invalid_target` | `swarm_sendPss` | `targets` is missing, not valid hex, or outside 2–`maxTargetDepth` whole bytes (a 1-byte target is too shallow to be stored — see [PSS mining depth](#pss-mining-depth-prefix-length)). |
| `invalid_kind` | `swarm_subscribe` | `kind` is not `"gsoc"` or `"pss"`. |
| `payload_too_large` | `swarm_sendPss`, `swarm_sendGsoc` | Payload exceeds `maxMessageBytes`. |
| `invalid_payload` | `swarm_sendGsoc` | Payload is empty. A GSOC update is a single-owner chunk and bee's chunk layer rejects an empty SOC payload, so an empty broadcast cannot be expressed. (`swarm_sendPss` **does** accept an empty payload — the PSS trojan framing carries an explicit length.) |
| `subscription_not_found` | `swarm_unsubscribe` | No active subscription with the given id for this origin. |
| `too_many_subscriptions` | `swarm_subscribe` | The origin has reached `maxSubscriptions`. |
| `unsupported_option` | messaging methods accepting `options` | An unrecognized option field was supplied. |

A subscription whose underlying receive pipeline fails after being established
(e.g. the node loses connectivity) has no per-subscription error signal in this
revision — the `SubscriptionMessage` schema deliberately has no error variant,
and normative mid-stream error signalling is deferred to a future revision (see
[Future Work](#future-work)). Where the failure is node-wide, the core spec's
`disconnect` event already applies. Implementations MUST document how a
degraded or failed pipeline behaves (silent gap until recovery, automatic
teardown, etc.) so applications can reason about liveness.

---

### Methods

#### `swarm_getMessagingIdentity`

Return this origin's messaging identity — the PSS public key peers encrypt to,
and the neighborhood-prefix target peers route toward when sending to it.

Operates under the **messaging permission tier** (see [Permission Model](#permission-model)):
the returned public key is a stable per-origin identifier, so disclosure
requires consent, mirroring `swarm_getSigningIdentity` in the core spec.

**Params:** None.

**Result:**

```javascript
{
  pssPublicKey: string,   // 66-char hex, 33-byte compressed secp256k1 public key
  pssTarget: string,      // hex neighborhood prefix (2..maxTargetDepth bytes); peers pass it as `targets` in swarm_sendPss
  identityMode: string    // "app-scoped" or "bee-wallet" (as in the core spec)
}
```

**Errors:** `4001` if the user rejects the messaging-permission prompt. `4100`
if the origin lacks basic connection or a prompt cannot be surfaced. `4900` if
the node is unavailable.

**Behavior:**
- If messaging permission has not been granted, the implementation MUST prompt
  (same tier as the first `swarm_subscribe`/`swarm_send*` call) and return on
  approval.
- The `pssPublicKey` MUST be stable for the lifetime of the origin's messaging
  grant. An `app-scoped` implementation SHOULD derive it per-origin so one dApp
  cannot present another's messaging identity.
- Whether the PSS key is bound to the same key as `swarm_getSigningIdentity`'s
  `owner` is implementation-defined; dApps MUST NOT assume equality.
- `pssTarget` MUST be a truncated neighborhood prefix, **at least 2 and at most
  `maxTargetDepth` bytes**, NOT the node's full overlay address. Two bounds, two
  reasons:
  - *Upper* (privacy): the full 64-hex overlay is a node-global value, identical
    for every origin, that would function as a cross-origin correlation handle
    and disclose the node's exact network position (see
    [Security Considerations](#security-considerations)).
  - *Lower* (deliverability): the prefix length is the number of leading bits a
    sender's trojan chunk is mined to match, and it must be **deep enough that
    storers in the neighborhood actually keep the chunk** — a prefix shallower
    than the network's storage depth produces chunks no reserve retains, so the
    message is undeliverable. It also governs the receiver's pull cost. See
    [PSS mining depth](#pss-mining-depth-prefix-length).

---

#### `swarm_subscribe`

Open a long-lived subscription. Incoming messages are delivered via the
[`message` event](#events), tagged with the returned `subscriptionId`.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `kind` | `"gsoc" \| "pss"` | Yes | Subscription type. |
| `topic` | `string` | Conditional | GSOC: a topic string the provider deterministically maps to a GSOC address. PSS: the topic to receive on. Required unless a raw `address` is given for GSOC. |
| `address` | `string` | Conditional | GSOC only. A raw 64-char hex GSOC/SOC address, for interoperating with GSOCs whose address was derived elsewhere. Mutually exclusive with `topic`. |
| `history` | `boolean` | No | PSS only. When `true`, on subscribe the provider attempts to deliver messages that arrived *before* the subscription — a **mailbox** — recovering offline messages, subject to storer retention and an implementation-defined bound (see [Delivery semantics](#delivery-semantics-normative)). Default `false` (live traffic only). Ignored for GSOC (a SOC has a single latest value, not a message backlog). |
| `options` | `object` | No | Reserved. Unknown fields rejected with `unsupported_option`. |

**Result:**

```javascript
{
  subscriptionId: string,   // opaque id, unique within this origin's session
  kind: "gsoc" | "pss",
  key: string               // resolved GSOC address (gsoc) or topic (pss), 64-char hex
}
```

**Errors:** `4001` if the user rejects the messaging-permission prompt this call
triggered. `4100` if the origin lacks basic connection or a prompt cannot be
surfaced. `4900` if the node is unavailable, **or if the node's aggregate
subscription capacity is exhausted** (see below). `-32602` for
`invalid_kind`, `invalid_topic`, `invalid_address`, `too_many_subscriptions`,
`unsupported_option`.

**Per-origin cap vs. node capacity — two distinct failures.**
`too_many_subscriptions` (`-32602`) means *this origin* has reached
`maxSubscriptions`: the dApp caused it and can fix it by unsubscribing. But a
receive pipeline is a **node-wide** resource — an implementation typically
bounds the number of *distinct neighborhoods* it will pull concurrently across
**all** origins (the reference light-node implementation allows 8), and that
pool can be exhausted by *other* origins' subscriptions. That case MUST be
reported as `4900` with a message naming subscription capacity, NOT as
`too_many_subscriptions`: it is not a parameter error, the calling dApp did
nothing wrong, and it is **retryable** — capacity frees when other
subscriptions close. DApps SHOULD treat it like any other transient node
condition (back off and retry, or degrade to feed polling) rather than as a
permanent refusal.

**Behavior:**
- Subscribing establishes a receive pipeline for the target neighborhood. The
  implementation is responsible for pulling and decrypting matching chunks and
  delivering decoded payloads via the `message` event.
- **GSOC topic → address derivation MUST be deterministic within an
  implementation**: any two origins passing the same `topic` to the same
  provider MUST resolve to the same address, whether subscribing or sending.
  The derivation MUST be documented by the implementation.
- **Cross-implementation convergence is NOT guaranteed in this revision.**
  Determinism alone does not pin the address: implementations must additionally
  agree on the identifier derivation (topic → 32-byte SOC identifier), the
  target-neighborhood derivation (topic → overlay prefix), the mining algorithm
  and its search order (e.g. bee-js `gsocMine`), and the required proximity —
  a difference in any one yields a different address for the same topic. Until
  a normative derivation profile exists (see [Future Work](#future-work)),
  applications interoperating across different providers MUST exchange the
  resolved GSOC `address` (returned by both `swarm_subscribe` and
  `swarm_sendGsoc`) out of band and use the raw `address` parameter — for
  **receiving only**. Sending requires the mined owner key, which only the
  topic derivation yields, so cross-provider *senders* must share the topic
  itself (see `swarm_sendGsoc` Behavior).
- For PSS, only messages the node can decrypt (encrypted to this origin's PSS
  key) are delivered. Undecryptable traffic in the neighborhood MUST NOT be
  delivered.
- The provider MUST deduplicate deliveries; the same message MUST NOT be
  delivered twice for one subscription. (Across a resubscribe, redelivery is
  permitted — see delivery semantics.) Note that two *sends* with
  byte-identical payloads on the same key are indistinguishable at the
  transport layer and MAY therefore be coalesced into a single delivery;
  applications that need repeated identical messages observed individually
  MUST make payloads distinct (e.g. include a sequence number or nonce).
- Subscriptions are **origin-scoped** and **session-scoped**. They MUST be torn
  down automatically when the page unloads (`pagehide`) and when access is
  revoked (`disconnect`). Implementations are NOT REQUIRED to persist
  subscriptions across page reloads.
- Multiple subscriptions to the same key by one origin MAY be coalesced
  internally but MUST each receive messages and MUST each be independently
  addressable by `swarm_unsubscribe`.

**Delivery semantics (normative):** Messages are **best-effort, unordered, and
at-least-once**. Without `history`, a subscriber MAY miss messages published
while it was not subscribed, MAY receive messages out of send order, and MAY
(across resubscription) receive a message more than once. Applications MUST
tolerate this. Ordering/causality and gap recovery are application concerns; the
durable Swarm feed layer (core spec) is the appropriate substrate for
authoritative state and catch-up, with messaging used for live propagation.

**With `history: true` (mailbox):** on subscribe the provider SHOULD additionally
deliver messages that arrived before the subscription — offline delivery. This
is **bounded and best-effort**, not a durable queue: recovery is limited by (a)
storer **retention** — a message whose postage stamp has expired, or that has
been evicted from neighborhood reserves, is unrecoverable; and (b) an
**implementation-defined lookback bound** the provider MAY impose to keep the
recovery sweep cheap. Recovered messages carry the same `message`-event shape as
live ones and are subject to the same at-least-once/may-duplicate guarantees;
`receivedAt` reflects when the *provider* recovered the message, not when it was
originally sent (a sender-supplied timestamp, if wanted, is application payload).
Whether historical messages are ordered relative to each other is
implementation-defined; applications needing send-order MUST carry their own
sequence. The recoverable depth scales with the mining prefix length (see
[PSS mining depth](#pss-mining-depth-prefix-length)): a deeper prefix makes the
whole neighborhood backlog small enough to sweep completely.

---

#### `swarm_unsubscribe`

Close a subscription.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `subscriptionId` | `string` | Yes | An id returned by `swarm_subscribe` for this origin. |

**Result:**

```javascript
{ unsubscribed: true }
```

**Errors:** `-32602` with `subscription_not_found` if no such active
subscription exists for this origin. Unsubscribing an already-closed
subscription MAY be treated as idempotent success or `subscription_not_found`;
implementations SHOULD prefer idempotent success.

**Behavior:**
- After a successful unsubscribe, the `message` event MUST NOT fire for that
  `subscriptionId`.
- The provider SHOULD release the underlying receive pipeline when its last
  subscriber for a neighborhood unsubscribes.

---

#### `swarm_sendPss`

Send an encrypted point-to-point message to a recipient identified by their PSS
public key. The message is a trojan chunk encrypted to the recipient and routed
toward the neighborhood implied by `targets`.

Operates under the **messaging send tier** (per-operation consent like publish;
consumes a postage stamp).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `topic` | `string` | Yes | Topic the recipient subscribes on. Hashed/normalized by the provider as in Bee PSS. |
| `recipient` | `string` | Yes | Recipient PSS public key: 66-char hex, 33-byte compressed secp256k1 (as returned by `swarm_getMessagingIdentity`). |
| `targets` | `string` | Yes | Neighborhood prefix as hex (**2**–`maxTargetDepth` bytes) locating the recipient — the value the recipient's `swarm_getMessagingIdentity` returned as `pssTarget`, shared out of band alongside their public key. The sender's provider cannot derive this from the public key alone. The prefix length sets the trojan's mining depth (see [PSS mining depth](#pss-mining-depth-prefix-length)): it MUST be deep enough that neighborhood storers keep the chunk, and deeper targets cost more to mine but less to receive. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Payload. Strings encoded UTF-8. MUST be ≤ `maxMessageBytes`. MAY be empty — the PSS trojan framing carries an explicit length, so a zero-byte message is well-formed (useful for pings/signals). |
| `options` | `object` | No | Reserved. Unknown fields rejected with `unsupported_option`. |

**Result:**

```javascript
{ sent: true }
```

**Errors:** `4001` if the user rejects a per-send prompt. `4100` if not
connected. `4900` if node unavailable or no usable postage stamp. `-32602` for
`invalid_topic`, `invalid_recipient`, `invalid_target`, `payload_too_large`,
`unsupported_option`.

**Behavior:**
- The provider constructs the trojan chunk (encryption to `recipient`, nonce
  mining, targeting) and uploads it with an automatically-selected postage
  batch. DApps do not manage batches or mining.
- PSS is **fire-and-forget**: a successful result means the chunk was accepted
  for upload, NOT that the recipient received it. There is no delivery receipt.
- Payload confidentiality is provided by PSS encryption to the recipient key.
  Sender anonymity properties are those of the underlying PSS primitive and are
  not strengthened or weakened here.

---

### PSS mining depth (prefix length)

A PSS message is a *trojan chunk* whose content-address is **mined** to share a
number of leading bits — the **prefix length**, `L` bits = `targets`/`pssTarget`
byte-count × 8 — with the recipient's overlay, so the network routes it into the
recipient's neighborhood. `L` is not a free knob; it is bounded on both sides,
which is why this spec constrains `targets`/`pssTarget` to **2–`maxTargetDepth`
bytes** rather than the underlying primitive's 1-byte floor.

**Lower bound — storability.** Neighborhood storers keep a chunk only if it falls
within their storage depth `d` (the proximity order at which the reserve is
maintained). A trojan mined to `L < d` lands *outside* every neighborhood
storer's reserve and is simply not stored — the send returns success (the chunk
was accepted for upload) but no one retains it, so it is undeliverable. On the
public network `d` is on the order of a dozen bits and rises with network growth;
a 1-byte (`L=8`) target is below it, which is why 1-byte targets are rejected. A
2-byte (`L=16`) target is the current de-facto floor; a 3-byte (`L=24`) target is
comfortably above `d` with headroom for growth.

**Upper bound — mining cost.** Mining is ~`2^L` hashes, so `maxTargetDepth`
(typically 3 bytes) caps sender work.

**Why the receiver cares — reception cost, and the mailbox.** A light-node
receiver pulls candidate chunks from the neighborhood and tries to decrypt them.
The volume it must sift is governed by `L`: on a depth-`d` storer the chunks at
proximity `≥ L` number roughly `2^(reserve_bits − (L − d))` of the reserve, so
each extra bit of `L` **halves** the receiver's candidate traffic. At `L=16,
d≈12` that is a sizeable fraction of ingest; at `L=24` it is only ~1–2K chunks —
small enough that a receiver can sweep the neighborhood's **entire** trojan
backlog on subscribe, which is exactly what makes the `history` mailbox
(above) recover *all* offline messages rather than only recent ones. Deeper
targets thus cost the sender more to mine but make the receiver dramatically
cheaper and unlock complete offline delivery.

**Convention.** Implementations MUST reject `targets`/`pssTarget` shorter than 2
bytes (`invalid_target`) and SHOULD document the mining prefix they use.
Interoperating sender and receiver implementations MUST agree on `L`: a receiver
pulls the bins a message at prefix `L` can occupy, so a sender mining to a
different `L` may land where the receiver is not looking. This SWIP does not yet
pin a single normative `L` — 2 bytes maximizes compatibility with today's
senders, 3 bytes is materially better for receiver cost and offline delivery —
and flags it as an open question for the Swarm community (it is arguably a
network-wide parameter that belongs alongside the storage-depth conventions in
the core protocol docs, not only in this provider spec).

Broadcast a message on a topic. Any origin subscribed (via `swarm_subscribe`
with `kind: "gsoc"`) to the address the topic derives to receives it.

Operates under the **messaging send tier**.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `topic` | `string` | Yes | Topic the provider deterministically maps to a GSOC address (same derivation as `swarm_subscribe`). Unlike `swarm_subscribe`, there is no raw `address` alternative — see Behavior. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Payload. Strings encoded UTF-8. MUST be **1**..`maxMessageBytes` bytes: an empty payload is rejected with `invalid_payload` (a GSOC update is a single-owner chunk, and bee's chunk layer refuses an empty SOC payload — the provider must not sign a chunk the network will not accept). |
| `options` | `object` | No | Reserved. Unknown fields rejected with `unsupported_option`. |

**Result:**

```javascript
{
  sent: true,
  address: string   // 64-char hex GSOC address written to
}
```

**Errors:** `4001` if the user rejects a per-send prompt. `4100` if not
connected. `4900` if node unavailable or no usable postage stamp. `-32602` for
`invalid_topic`, `invalid_payload`, `payload_too_large`, `unsupported_option`.

**Behavior:**
- GSOC send writes a Single Owner Chunk at the derived address. The provider
  performs any required owner mining so the chunk lands in the correct
  neighborhood, signs it, and uploads it with an automatically-selected batch.
- **There is deliberately no raw `address` variant** (asymmetric with
  `swarm_subscribe`, which accepts one). Writing a GSOC requires signing with
  the mined owner key, and that key is recovered by re-running the derivation
  from the topic; a GSOC address is a hash output
  (`keccak256(identifier ‖ owner)`) from which neither the identifier nor the
  owner key can be recovered. An address alone therefore carries nothing to
  sign with — watching an address is passive, authoring at one is not. Senders
  interoperating across providers MUST share the topic (and, until a normative
  derivation profile exists, use the same provider implementation or agree on
  the derivation out of band).
- Re-sending on the same topic overwrites the SOC at that address with a newer
  timestamp (this is how a broadcast channel advances). Because delivery is
  at-least-once and unordered, subscribers MUST NOT assume they observe every
  intermediate value — only that they converge on recent ones. For a stream of
  independent updates (e.g. CRDT deltas) where every value matters, senders
  SHOULD vary the effective address per message (e.g. include a sequence or
  random component in the topic) so updates do not clobber one another, or use
  PSS. Implementations SHOULD document their GSOC addressing so applications can
  reason about this.
- Unlike the core `swarm_writeSingleOwnerChunk` (signed by the fixed origin
  identity), GSOC uses a mined owner key derived for neighborhood placement;
  this is why GSOC send is a distinct method rather than a use of the core SOC
  write.

---

### Limits

`swarm_getCapabilities().limits` is extended with:

| Limit | Recommended Default | Notes |
|---|---|---|
| `maxMessageBytes` | 3584 | Max PSS/GSOC payload. A Swarm chunk is 4096 bytes; PSS/GSOC framing and encryption overhead reduce the usable payload. Implementations MUST advertise the true usable maximum. |
| `maxTargetDepth` | 3 | Max neighborhood-prefix length in bytes for PSS `targets`/`pssTarget`. The minimum is fixed at **2 bytes** (below the network storage depth chunks are not retained — see [PSS mining depth](#pss-mining-depth-prefix-length)); this limit caps the deep end (sender mining cost). |
| `maxSubscriptions` | 32 | Max concurrent active subscriptions **per origin**. The node additionally bounds its *aggregate* receive pipelines across all origins (implementation-defined; not advertised here because it is shared state, not a per-origin promise) — exhaustion of that pool surfaces as a retryable `4900`, see `swarm_subscribe`. |

Applications needing to move more than `maxMessageBytes` in one logical message
MUST chunk at the application layer, or publish the bulk via `swarm_publishData`
and send only the resulting reference over messaging.

### Permission Model

This extension adds one tier to the core permission lifecycle:

- **Messaging tier.** Acquired on first call to `swarm_getMessagingIdentity`,
  `swarm_subscribe`, `swarm_sendPss`, or `swarm_sendGsoc`. Separate from the
  publish and feed tiers. Rationale: messaging discloses a stable per-origin
  public identity, opens a resource-consuming receive pipeline (the node pulls
  from a neighborhood on the origin's behalf), and sends consume postage. Any
  messaging method MAY trigger the grant prompt on first call; on rejection the
  method MUST reject with `4001`.
- **Send consent.** `swarm_sendPss`/`swarm_sendGsoc` MAY additionally require
  per-operation approval (like `swarm_publishData`), or fall under an origin
  auto-approve the user has enabled. Implementations MUST still enforce size
  limits and stamp checks under auto-approve, and SHOULD additionally apply a
  per-origin send rate cap there — messaging sends are cheap to issue in a
  loop and each consumes postage.
- **Subscription resource control.** Subscriptions consume bandwidth for as long
  as they are open. Implementations MUST cap concurrent subscriptions per origin
  (`maxSubscriptions`) and SHOULD apply per-origin bandwidth accounting to the
  receive pipeline, tighter for origins that have not been explicitly granted
  messaging.
- **Revocation.** On disconnect/revocation the provider MUST tear down the
  origin's subscriptions and stop emitting `message` events for it, consistent
  with the core spec's `disconnect` behavior.

### Encoding

Payloads cross the process/IPC/`postMessage` boundary as in the core spec, so
inbound payloads in the `message` event are **base64** (`encoding: "base64"`),
decoded exactly as `swarm_readFeedEntry` results are. Outbound `data` accepts
`string | Uint8Array | ArrayBuffer` as elsewhere.

## Rationale

### Why a subscription primitive instead of polling helpers?

The core API can already be polled (`swarm_readFeedEntry`, `swarm_readSingleOwnerChunk`).
Polling is sufficient for asynchronous state and is the right tool for
authoritative catch-up. It cannot reach interactive latency without pathological
request rates, and it cannot express PSS's push-only, encrypted, point-to-point
delivery at all. A subscription is the minimal addition that unlocks the class
of applications the core API cannot serve.

### Why the EIP-1193 `message`-event shape?

Web3 developers already know `eth_subscribe` → subscription id → `message`
events. Reusing that shape (with `type: "swarm_subscription"`) means existing
mental models and tooling transfer, and keeps the provider to a single streaming
idiom rather than inventing per-method callbacks.

### Why is GSOC send a new method rather than `swarm_writeSingleOwnerChunk`?

The core SOC write signs with the origin's fixed app-scoped identity at a
caller-chosen identifier. GSOC requires an owner key *mined* so the resulting
SOC address falls in a chosen neighborhood — a different owner, chosen by the
provider, not the origin identity. Overloading the core method with a mining
mode would complicate its clean "sign with your identity" contract; a dedicated
method keeps both honest.

### Why does `swarm_sendGsoc` accept a topic but not an address?

An earlier draft mirrored `swarm_subscribe` and allowed a raw `address` on
send. That was unimplementable: authoring a GSOC means producing a signature
from the mined owner key, and the address — `keccak256(identifier ‖ owner)` —
is a one-way hash of the very material a sender needs. Every conforming
provider would have had to reject the parameter at runtime; better for the
interface to make the impossible state unrepresentable. The asymmetry is
principled: subscribing to an address is passive observation, sending to one
is authorship, and authorship needs the key that only the topic derivation
(or out-of-band agreement on it) can reproduce.

### Why expose a PSS public key separately from the signing identity?

Receiving PSS requires peers to encrypt to a key the node holds the private half
of. That key's role (encryption) and possibly its derivation differ from the
feed/SOC signing key. Exposing it explicitly via `swarm_getMessagingIdentity`
avoids conflating the two and lets implementations choose their key management.

### Why surface best-effort/unordered/at-least-once so prominently?

Because building on a false reliability assumption is the most likely way to
misuse this API. Stating the true semantics steers applications toward
CRDT/idempotent designs (which compose perfectly with these guarantees) and
toward using the durable feed layer for authoritative state — the intended
architecture: **feeds for the source of truth, messaging for live propagation.**

## Backwards Compatibility

Purely additive. Implementations without this extension omit the messaging
methods and the `"messaging"` feature flag; dApps detect absence via
`swarm_getCapabilities().features` and fall back to the feed/polling approach.
No core method changes.

## Security Considerations

Inherits the core specification's origin trust model, key-custody rules
(messaging private keys MUST NOT reach the page context; encryption/signing
occur in the trusted context), and resource-exhaustion posture. Additional
considerations:

- **Receive pipeline as an amplification/DoS surface.** A subscription makes the
  user's node pull from a neighborhood on the origin's behalf. Unbounded
  subscriptions or very shallow targets could be abused to consume bandwidth.
  Implementations MUST cap concurrent subscriptions (`maxSubscriptions`) and
  SHOULD bound per-origin receive bandwidth, with tighter limits for
  un-granted origins.
- **Cross-origin identity correlation.** `pssPublicKey` is per-origin under
  `app-scoped` derivation, but any node-global value returned to multiple
  origins is a correlation handle. This is why `swarm_getMessagingIdentity`
  returns a truncated `pssTarget` prefix rather than the node's full overlay
  address: the full overlay is identical for every origin, uniquely identifies
  the user's node, and discloses its exact network position. Even the
  truncated prefix leaks up to `maxTargetDepth` bytes of neighborhood
  information and is the same across origins; implementations SHOULD keep
  `maxTargetDepth` small. Under `bee-wallet` mode the public key itself is
  node-global; users selecting it accept cross-origin linkability, as in the
  core spec.
- **Metadata exposure.** PSS hides payloads but the existence and neighborhood
  of traffic is observable to the network. Subscribing to a topic reveals
  interest in that neighborhood to peers the node pulls from. Applications
  handling sensitive relationships SHOULD treat topics as potentially
  observable and derive them so as not to leak identifiers.
- **Send is unauthenticated at the transport layer.** GSOC broadcasts can be
  written by anyone who derives the address; PSS messages can be sent by anyone
  who knows the recipient key and topic. Applications MUST authenticate message
  *content* themselves (e.g. signed payloads) and MUST NOT trust a message's
  origin from the transport alone. This mirrors the core spec's stance that the
  provider secures access to the node, not the semantics of arbitrary data.
- **Payload confidentiality.** GSOC payloads are plaintext on Swarm unless the
  application encrypts them; only PSS provides transport encryption. For a
  private collaborative session over GSOC, the application MUST encrypt payloads
  (e.g. with a per-session key shared out of band, as the Freedom Docs
  capability-link model already does).
- **Duplicate/stale delivery.** At-least-once, unordered delivery means a
  malicious or lagging peer could replay old messages. Application-layer
  sequence/version handling (again, native to CRDTs) is required; state MUST NOT
  advance irreversibly on receipt of a single unverified message.

## Test Cases

### Feature Detection

```javascript
const caps = await window.swarm.getCapabilities()
assert(Array.isArray(caps.features))
const hasMessaging = caps.features.includes('messaging')
if (hasMessaging) {
  assert(typeof caps.limits.maxMessageBytes === 'number')
  assert(typeof caps.limits.maxSubscriptions === 'number')
}
```

### Messaging Identity

```javascript
const { maxTargetDepth } = (await window.swarm.getCapabilities()).limits
const id = await window.swarm.getMessagingIdentity()
assert(/^[0-9a-f]{66}$/.test(id.pssPublicKey))   // 33-byte compressed key
assert(/^([0-9a-f]{2})+$/.test(id.pssTarget))    // whole bytes, hex
assert(id.pssTarget.length / 2 <= maxTargetDepth) // truncated prefix, never the full overlay
assert(['app-scoped', 'bee-wallet'].includes(id.identityMode))
```

### GSOC Broadcast Round-Trip (two peers, same topic, same provider implementation)

```javascript
// Peer B subscribes
const sub = await window.swarm.subscribe({ kind: 'gsoc', topic: 'room:doc-42' })
assert(typeof sub.subscriptionId === 'string')
assert(/^[0-9a-f]{64}$/.test(sub.key))   // resolved GSOC address

const received = new Promise((resolve) => {
  window.swarm.on('message', (m) => {
    if (m.subscription === sub.subscriptionId) {
      const bytes = Uint8Array.from(atob(m.result.data), c => c.charCodeAt(0))
      resolve(new TextDecoder().decode(bytes))
    }
  })
})

// Peer A sends on the same topic (address derives identically)
const sent = await window.swarm.sendGsoc({ topic: 'room:doc-42', data: 'hello room' })
assert(sent.sent === true)
assert(sent.address === sub.key)   // same-provider topic→address determinism
                                   // (across different providers, exchange `address` instead)

assert(await received === 'hello room')
```

### PSS Point-to-Point

```javascript
// Recipient publishes its messaging identity out of band
const me = await window.swarm.getMessagingIdentity()
const sub = await window.swarm.subscribe({ kind: 'pss', topic: 'dm:alice' })

// Sender (knowing the recipient's pssPublicKey, pssTarget, and topic,
// shared out of band)
await window.swarm.sendPss({
  topic: 'dm:alice',
  recipient: recipientPssPublicKey,   // 66-char hex
  targets: recipientPssTarget,        // recipient's getMessagingIdentity().pssTarget
  data: 'private hello',
})
// recipient's 'message' event fires with kind:'pss', decrypted payload
```

### Mailbox (offline delivery)

```javascript
// A sender posts to a room while nobody is subscribed.
await window.swarm.sendPss({ topic: 'room:42', recipient, targets, data: 'sent while you were away' })

// Later, a client subscribes WITH history — and receives the earlier message.
const seen = []
window.swarm.on('message', (m) => { if (m.subscription === sub.subscriptionId) seen.push(m.result.data) })
const sub = await window.swarm.subscribe({ kind: 'pss', topic: 'room:42', history: true })
// `seen` includes messages sent before this subscription existed
// (bounded by storer retention; see Delivery semantics).

// Without history, the same subscribe would only receive messages sent
// from now on:
const liveOnly = await window.swarm.subscribe({ kind: 'pss', topic: 'room:42' })
```

### Unsubscribe Stops Delivery

```javascript
const sub = await window.swarm.subscribe({ kind: 'gsoc', topic: 't' })
const res = await window.swarm.unsubscribe({ subscriptionId: sub.subscriptionId })
assert(res.unsubscribed === true)
// No further 'message' events fire for sub.subscriptionId

try {
  await window.swarm.unsubscribe({ subscriptionId: 'nonexistent' })
} catch (err) {
  assert(err.code === -32602)
  assert(err.data.reason === 'subscription_not_found')
}
```

### Payload Too Large

```javascript
const { maxMessageBytes } = (await window.swarm.getCapabilities()).limits
try {
  await window.swarm.sendGsoc({ topic: 't', data: 'x'.repeat(maxMessageBytes + 1) })
  assert.fail('should reject')
} catch (err) {
  assert(err.code === -32602)
  assert(err.data.reason === 'payload_too_large')
}
```

### Payload Bounds (empty)

```javascript
// GSOC cannot express an empty broadcast (bee rejects an empty SOC payload):
try {
  await window.swarm.sendGsoc({ topic: 't', data: '' })
  assert.fail('should reject')
} catch (err) {
  assert(err.code === -32602)
  assert(err.data.reason === 'invalid_payload')
}
// PSS carries an explicit length, so a zero-byte message is valid:
const res = await window.swarm.sendPss({
  topic: 't', recipient: peerKey, targets: peerTarget, data: '',
})
assert(res.sent === true)
```

### Permission Gating

```javascript
// Before the messaging grant, a messaging method prompts; on rejection:
try {
  await window.swarm.subscribe({ kind: 'gsoc', topic: 't' })
  assert.fail('should reject when user denies messaging permission')
} catch (err) {
  assert(err.code === 4001)   // User Rejected
}
```

## Future Work

- **Normative GSOC derivation profile.** A pinned topic → (identifier,
  target neighborhood, proximity) derivation plus mining algorithm and search
  order, so the same topic converges on the same address across *independent*
  provider implementations, not only within one. Until then, cross-provider
  interop goes through the raw `address` parameter.
- **Mid-stream error signalling.** A normative way to report that an established
  subscription's pipeline has degraded/failed (a dedicated event or a
  `message` error variant), rather than the current SHOULD-document approach.
- **Delivery/ack extensions for PSS.** Optional application-visible send
  acknowledgement where the underlying primitive can support it.
- **Presence/awareness helpers.** A higher-level convention for ephemeral
  presence (cursors, typing) layered on GSOC, if a common pattern emerges.
- **Backpressure signalling.** Surfacing to the dApp when the provider is
  shedding inbound messages under load, so applications can adapt send rates.

## Reference Endpoints (informative)

This extension is designed to sit atop light-node PSS/GSOC support exposing
gateway endpoints equivalent to:

- `POST /pss/send/{topic}/{targets}` (+ recipient key) — backs `swarm_sendPss`
- `POST /soc/{owner}/{id}` with mined owner/id — backs `swarm_sendGsoc`
- `GET /gsoc/subscribe/{address}` (streaming) — backs `swarm_subscribe` (gsoc)
- `GET /pss/subscribe/{topic}` (streaming) — backs `swarm_subscribe` (pss)
- `GET /addresses` reporting `pssPublicKey`/overlay — backs `swarm_getMessagingIdentity`
  (the provider truncates the overlay to the `pssTarget` prefix; the full
  overlay never crosses the page boundary)

The provider is responsible for translating the ergonomic, consent-gated,
origin-scoped method surface above onto whatever node interface it drives; these
endpoints are named only to ground the mapping.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
