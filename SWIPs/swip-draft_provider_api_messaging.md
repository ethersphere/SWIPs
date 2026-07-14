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
  overlay, so peers can address messages to it.

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
[Limits](#limits)). Both `features` and the new limit fields MAY be returned
before `swarm_requestAccess` (they are static capability facts).

### Convenience Methods

Implementations of this extension MUST expose these convenience wrappers, in
addition to the core set:

```javascript
window.swarm.getMessagingIdentity()                        // swarm_getMessagingIdentity
window.swarm.subscribe({ kind, topic })                    // swarm_subscribe
window.swarm.unsubscribe({ subscriptionId })               // swarm_unsubscribe
window.swarm.sendPss({ topic, recipient, data })           // swarm_sendPss
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
| `invalid_kind` | `swarm_subscribe` | `kind` is not `"gsoc"` or `"pss"`. |
| `payload_too_large` | `swarm_sendPss`, `swarm_sendGsoc` | Payload exceeds `maxMessageBytes`. |
| `subscription_not_found` | `swarm_unsubscribe` | No active subscription with the given id for this origin. |
| `too_many_subscriptions` | `swarm_subscribe` | The origin has reached `maxSubscriptions`. |
| `unsupported_option` | messaging methods accepting `options` | An unrecognized option field was supplied. |

A subscription whose underlying receive pipeline fails after being established
(e.g. the node loses connectivity) MUST NOT silently stop. The provider SHOULD
emit a `message` with a transport-level error indicator OR emit `disconnect`
semantics per the core spec; at minimum, implementations MUST document their
failure signalling. (Normative signalling of mid-stream subscription errors is
deferred to a future revision; see [Future Work](#future-work).)

---

### Methods

#### `swarm_getMessagingIdentity`

Return this origin's messaging identity — the PSS public key peers encrypt to,
and the node overlay used for neighborhood targeting.

Operates under the **messaging permission tier** (see [Permission Model](#permission-model)):
the returned public key is a stable per-origin identifier, so disclosure
requires consent, mirroring `swarm_getSigningIdentity` in the core spec.

**Params:** None.

**Result:**

```javascript
{
  pssPublicKey: string,   // 66-char hex, 33-byte compressed secp256k1 public key
  overlay: string,        // 64-char hex node overlay address (neighborhood targeting)
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
surfaced. `4900` if the node is unavailable. `-32602` for
`invalid_kind`, `invalid_topic`, `invalid_address`, `too_many_subscriptions`,
`unsupported_option`.

**Behavior:**
- Subscribing establishes a receive pipeline for the target neighborhood. The
  implementation is responsible for pulling and decrypting matching chunks and
  delivering decoded payloads via the `message` event.
- **GSOC topic → address derivation MUST be deterministic** so that independent
  parties passing the same `topic` subscribe to and send at the same address.
  The derivation MUST be documented by the implementation and SHOULD match
  bee-js `gsocMine` semantics for cross-implementation interop.
- For PSS, only messages the node can decrypt (encrypted to this origin's PSS
  key) are delivered. Undecryptable traffic in the neighborhood MUST NOT be
  delivered.
- The provider MUST deduplicate deliveries; the same message MUST NOT be
  delivered twice for one subscription. (Across a resubscribe, redelivery is
  permitted — see delivery semantics.)
- Subscriptions are **origin-scoped** and **session-scoped**. They MUST be torn
  down automatically when the page unloads (`pagehide`) and when access is
  revoked (`disconnect`). Implementations are NOT REQUIRED to persist
  subscriptions across page reloads.
- Multiple subscriptions to the same key by one origin MAY be coalesced
  internally but MUST each receive messages and MUST each be independently
  addressable by `swarm_unsubscribe`.

**Delivery semantics (normative):** Messages are **best-effort, unordered, and
at-least-once**. A subscriber MAY miss messages published while it was not
subscribed, MAY receive messages out of send order, and MAY (across
resubscription) receive a message more than once. Applications MUST tolerate
this. Ordering/causality and gap recovery are application concerns; the durable
Swarm feed layer (core spec) is the appropriate substrate for authoritative
state and catch-up, with messaging used for live propagation.

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
| `targets` | `string` | No | Neighborhood prefix as hex (1–`maxTargetDepth` bytes). If omitted, the provider derives targeting from the recipient/overlay. Deeper targets = more precise routing, higher cost. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Payload. Strings encoded UTF-8. MUST be ≤ `maxMessageBytes`. |
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

#### `swarm_sendGsoc`

Broadcast a message on a topic. Any origin subscribed (via `swarm_subscribe`
with `kind: "gsoc"`) to the address the topic derives to receives it.

Operates under the **messaging send tier**.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `topic` | `string` | Conditional | Topic the provider deterministically maps to a GSOC address (same derivation as `swarm_subscribe`). Required unless `address` is given. |
| `address` | `string` | Conditional | Raw 64-char hex GSOC address. Mutually exclusive with `topic`. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Payload. Strings encoded UTF-8. MUST be ≤ `maxMessageBytes`. |
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
`invalid_topic`, `invalid_address`, `payload_too_large`, `unsupported_option`.

**Behavior:**
- GSOC send writes a Single Owner Chunk at the derived address. The provider
  performs any required owner mining so the chunk lands in the correct
  neighborhood, signs it, and uploads it with an automatically-selected batch.
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
| `maxTargetDepth` | 3 | Max neighborhood-prefix length in bytes for PSS `targets`. |
| `maxSubscriptions` | 32 | Max concurrent active subscriptions per origin. |

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
  limits and stamp checks under auto-approve.
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
const id = await window.swarm.getMessagingIdentity()
assert(/^[0-9a-f]{66}$/.test(id.pssPublicKey))   // 33-byte compressed key
assert(/^[0-9a-f]{64}$/.test(id.overlay))
```

### GSOC Broadcast Round-Trip (two peers, same topic)

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
assert(sent.address === sub.key)   // deterministic topic→address derivation

assert(await received === 'hello room')
```

### PSS Point-to-Point

```javascript
// Recipient publishes its messaging identity out of band
const me = await window.swarm.getMessagingIdentity()
const sub = await window.swarm.subscribe({ kind: 'pss', topic: 'dm:alice' })

// Sender (knowing recipient.pssPublicKey and topic)
await window.swarm.sendPss({
  topic: 'dm:alice',
  recipient: recipientPssPublicKey,   // 66-char hex
  data: 'private hello',
})
// recipient's 'message' event fires with kind:'pss', decrypted payload
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

The provider is responsible for translating the ergonomic, consent-gated,
origin-scoped method surface above onto whatever node interface it drives; these
endpoints are named only to ground the mapping.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
