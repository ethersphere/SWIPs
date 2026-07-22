---
SWIP: <to be assigned>
title: Swarm Provider API (`window.swarm`)
author: Florian Glatz (@heckerhut)
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
status: Draft
type: Standards Track
category: Interface
created: 2026-04-03
---

## Simple Summary

A standard JavaScript API (`window.swarm`) that enables web pages to request access to a user's Swarm node for publishing data, uploading files, managing mutable feeds, reading/writing indexed feed entries, introspecting their own feed records, and working with low-level chunk primitives — with user consent and origin-scoped permissions.

## Abstract

This SWIP defines a browser-injected JavaScript provider object (`window.swarm`) that allows web applications to interact with a user's local Swarm (Bee) node. The API follows the request/response pattern established by [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) for Ethereum providers, adapted for Swarm's publishing, feed, and chunk primitives. It specifies fifteen RPC methods covering connection, capability discovery, data/file publishing, upload tracking, mutable feed management, indexed feed entry read/write, origin-scoped feed introspection, low-level chunk primitives (content-addressed and single-owner), and signing-identity disclosure. The provider includes a permission model with explicit user consent, origin isolation, and upload size limits. Read-only methods that operate on public Swarm data — including feed entry reads, chunk reads, and the calling origin's own feed introspection — do not require a connection grant but MUST be rate-limited per origin.

## Motivation

Today, publishing to Swarm from a web application requires either:

1. Direct HTTP calls to a locally running Bee node API (exposing the full API surface, including administrative endpoints, to any web page that can reach `localhost`), or
2. Server-side publishing infrastructure (defeating the purpose of decentralized hosting).

Neither approach is suitable for a user-sovereign web. Users need a way to grant web applications controlled, permissioned access to Swarm publishing capabilities — similar to how `window.ethereum` ([EIP-1193](https://eips.ethereum.org/EIPS/eip-1193)) lets web applications interact with a user's Ethereum wallet without exposing private keys.

Without a standard, each Swarm-enabled browser or extension will invent its own API. This fragments the ecosystem: dApp developers must write implementation-specific code, and users can't switch clients without breaking functionality. A standard `window.swarm` provider ensures interoperability across implementations.

### Design Goals

- **User consent first.** No write, signing, or other operation that consumes user resources executes without consent or explicit resource controls. Read-only operations on public Swarm data are ungated but rate-limited per origin.
- **Minimal surface.** Only the data plane — not administrative, debug, or staking endpoints.
- **Origin isolation.** Each web origin gets isolated permissions and feed identities.
- **Implementation freedom.** The spec defines the interface, not how the host manages nodes, keys, or storage internally.

## Specification

### Provider Object

Conforming implementations MUST inject a `window.swarm` object into the JavaScript context of web pages. The object MUST be available before the page's `DOMContentLoaded` event fires.

#### Detection

```javascript
if (typeof window.swarm !== 'undefined') {
  // Swarm provider is available
}
```

#### Properties

Implementations MAY include additional boolean properties identifying themselves (e.g., `isFreedomBrowser`). These are NOT part of the standard interface and MUST NOT be relied upon for feature detection. Use `swarm_getCapabilities` for capability discovery.

> **Note:** Future versions of this specification may define a standard `isSwarmProvider` property or a capability-based detection mechanism.

### Request Interface

The provider MUST expose a `request` method:

```javascript
window.swarm.request({ method: string, params?: object }): Promise<any>
```

- `method` — (Required) A string identifying the RPC method to invoke.
- `params` — (Optional) A plain object containing method-specific parameters.

The method MUST return a `Promise` that resolves with the method's result, or rejects with an error object.

### Convenience Methods

Implementations MUST expose convenience wrappers for each standard method:

```javascript
window.swarm.requestAccess()                              // swarm_requestAccess
window.swarm.getCapabilities()                             // swarm_getCapabilities
window.swarm.publishData({ data, contentType })            // swarm_publishData
window.swarm.publishFiles({ files })                       // swarm_publishFiles
window.swarm.getUploadStatus({ tagUid })                   // swarm_getUploadStatus
window.swarm.createFeed({ name })                          // swarm_createFeed
window.swarm.updateFeed({ feedId, reference })             // swarm_updateFeed
window.swarm.writeFeedEntry({ name, data })                // swarm_writeFeedEntry
window.swarm.readFeedEntry({ name, owner })                // swarm_readFeedEntry
window.swarm.listFeeds()                                   // swarm_listFeeds
window.swarm.publishChunk({ data })                        // swarm_publishChunk
window.swarm.readChunk({ reference })                      // swarm_readChunk
window.swarm.writeSingleOwnerChunk({ identifier, data })   // swarm_writeSingleOwnerChunk
window.swarm.readSingleOwnerChunk({ owner, identifier })   // swarm_readSingleOwnerChunk
window.swarm.getSigningIdentity()                          // swarm_getSigningIdentity
```

Each convenience method MUST be equivalent to calling `window.swarm.request()` with the corresponding method name and parameters.

### Events

The provider MUST support event subscription:

```javascript
window.swarm.on(event: string, handler: Function): this
window.swarm.removeListener(event: string, handler: Function): this
window.swarm.removeAllListeners(event?: string): this
```

#### Standard Events

| Event | Data | Description |
|---|---|---|
| `connect` | `{ origin: string }` | Emitted when the user grants access. |
| `disconnect` | `{ origin: string }` | Emitted when the user revokes access or the provider disconnects. |

### Error Format

Errors MUST follow the [JSON-RPC 2.0 error format](https://www.jsonrpc.org/specification#error_object):

```javascript
{
  code: number,
  message: string,
  data?: any
}
```

#### Standard Error Codes

| Code | Name | Description |
|---|---|---|
| 4001 | User Rejected | The user denied the request. |
| 4100 | Unauthorized | The origin is not authorized for the requested operation, or required consent cannot be obtained in this context. Covers: origin has not called `swarm_requestAccess`; feed-permission prompt cannot be surfaced; tag ownership mismatch in `swarm_getUploadStatus`; access was previously revoked. |
| 4200 | Unsupported Method | The requested method is not recognized. |
| 4900 | Node Unavailable | The Swarm node is not running, not ready, or lacks usable postage stamps. |
| -32602 | Invalid Params | Missing or invalid method parameters. |
| -32603 | Internal Error | An unexpected error occurred in the provider. |

Error codes 4001, 4100, 4200, and 4900 are aligned with the [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) and [EIP-1474](https://eips.ethereum.org/EIPS/eip-1474) error code ranges.

#### Structured Error Reasons

For `-32602` (Invalid Params) errors, implementations SHOULD include a `data.reason` field to enable programmatic error handling:

| Reason | Applicable Methods | Meaning |
|---|---|---|
| `feed_empty` | `swarm_readFeedEntry` | Feed exists but has no entries (latest-entry read). |
| `entry_not_found` | `swarm_readFeedEntry` | No entry at the requested index. |
| `feed_not_found` | `swarm_readFeedEntry`, `swarm_writeFeedEntry` | Feed not found in local store or does not exist. |
| `index_already_exists` | `swarm_writeFeedEntry` | An entry already exists at the explicit index (overwrite protection). |
| `payload_too_large` | `swarm_publishData`, `swarm_writeFeedEntry`, `swarm_publishChunk`, `swarm_writeSingleOwnerChunk` | Payload exceeds the maximum allowed size. |
| `invalid_topic` | `swarm_readFeedEntry` | Topic is not a valid 64-character hex string. |
| `invalid_owner` | `swarm_readFeedEntry`, `swarm_readSingleOwnerChunk` | Owner is missing (when required) or not a valid address. |
| `invalid_reference` | `swarm_readChunk`, `swarm_readSingleOwnerChunk` | Chunk reference is not a valid 64-character hex address. |
| `invalid_identifier` | `swarm_writeSingleOwnerChunk`, `swarm_readSingleOwnerChunk` | SOC identifier is not a valid 64-character hex string. |
| `invalid_span` | `swarm_publishChunk`, `swarm_writeSingleOwnerChunk` | Explicit `span` is negative, non-integer, exceeds the 8-byte unsigned range, or is a `number` outside `Number.MAX_SAFE_INTEGER` (use `bigint` for values above 2⁵³ − 1). |
| `chunk_not_found` | `swarm_readChunk`, `swarm_readSingleOwnerChunk` | No chunk exists at the requested address. |
| `chunk_type_mismatch` | `swarm_readChunk`, `swarm_readSingleOwnerChunk` | Returned bytes do not validate as the requested chunk type. |
| `unsupported_option` | All methods accepting `options` | An option field was supplied that the implementation does not recognize. |
| `rate_limited` | `swarm_readFeedEntry`, `swarm_readChunk`, `swarm_readSingleOwnerChunk`, `swarm_listFeeds` | The calling origin has exceeded the implementation's per-origin rate or bandwidth budget for permission-free reads. |

---

### Methods

#### `swarm_requestAccess`

Requests the user's permission to interact with their Swarm node from this origin. Implementations MUST present a user-visible consent prompt. The user MUST be able to deny access.

**Params:** None.

**Result:**

```javascript
{
  connected: true,
  origin: string,          // The normalized origin that was granted access
  capabilities: string[]   // e.g. ["publish"]
}
```

**Errors:** `4001` if the user rejects.

**Behavior:**
- Calling `swarm_requestAccess` when already connected MUST return the existing connection state without re-prompting.
- After a successful `swarm_requestAccess`, the provider MUST emit a `connect` event.

---

#### `swarm_getCapabilities`

Returns the current capabilities of the provider for this origin. Does NOT require prior access — can be called before `swarm_requestAccess` for feature detection.

**Params:** None.

**Result:**

```javascript
{
  specVersion: string,     // Specification version (e.g. "1.0")
  canPublish: boolean,     // true if connected AND node is ready
  reason: string | null,   // null if canPublish is true, otherwise a reason code
  limits: {
    maxDataBytes: number,         // Maximum payload size for swarm_publishData and swarm_writeFeedEntry
    maxFilesBytes: number,        // Maximum total size for swarm_publishFiles
    maxFileCount: number,         // Maximum number of files per swarm_publishFiles call
    maxPathBytes: number,         // Maximum length of a file path in swarm_publishFiles, measured in UTF-8 bytes
    maxChunkPayloadBytes: number  // Maximum payload size for swarm_publishChunk and swarm_writeSingleOwnerChunk (4096 by protocol)
  }
}
```

**Reason codes:**

| Code | Meaning |
|---|---|
| `"not-connected"` | Origin has not called `swarm_requestAccess`. |
| `"node-stopped"` | Bee node is not running. |
| `"ultra-light-mode"` | Node is in ultra-light mode (browse only, cannot publish). |
| `"node-not-ready"` | Node is running but not yet synced/ready. |
| `"no-usable-stamps"` | No postage stamps with remaining capacity. |

**`specVersion`:** The version of this specification that the provider implements. This SWIP defines version `"1.0"`. Implementations SHOULD return this field regardless of whether the origin has called `swarm_requestAccess`. DApps can use this field to detect available features and adapt to different provider versions.

---

#### `swarm_publishData`

Upload a single blob of data to Swarm.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | The content to upload. Strings are encoded as UTF-8. |
| `contentType` | `string` | Yes | MIME type (e.g. `"text/html"`, `"application/json"`). |
| `name` | `string` | No | Display name for the upload. |

**Result:**

```javascript
{
  reference: string,   // 64-character hex Swarm reference
  bzzUrl: string       // "bzz://<reference>"
}
```

> **Note on `bzz://` URLs:** The `bzz://` URI scheme is a Swarm convention for content-addressed references. It is not an IANA-registered scheme. Implementations resolve `bzz://` URLs through a local Bee gateway or native protocol handler.

**Errors:** `4001` if the user rejects a per-publish prompt. `4100` if not connected. `4900` if node unavailable. `-32602` if params invalid or payload exceeds `maxDataBytes`.

**Behavior:**
- Implementations SHOULD prompt the user for per-publish consent unless the user has opted into auto-approve for this origin.
- The implementation selects an appropriate postage batch automatically — dApps do not manage batches.
- Uploads MUST be pinned on the local node.

---

#### `swarm_publishFiles`

Upload a collection of files as a Swarm manifest (directory).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `files` | `Array<FileEntry>` | Yes | Array of file objects. |
| `indexDocument` | `string` | No | Path of the default document (e.g. `"index.html"`). Must match an entry in `files`. |

**FileEntry:**

| Field | Type | Required | Description |
|---|---|---|---|
| `path` | `string` | Yes | Virtual path in the manifest (e.g. `"index.html"`, `"assets/style.css"`). |
| `bytes` | `Uint8Array \| ArrayBuffer` | Yes | File content. |
| `contentType` | `string` | No | MIME type. Implementation MAY infer from path if omitted. |

**Path validation rules:**
- Must be a non-empty string. Maximum length is `maxPathBytes` UTF-8 bytes, advertised via `swarm_getCapabilities`. Length MUST be measured in UTF-8 bytes, not Unicode characters or UTF-16 code units — a single emoji is 4 bytes, not 1.
- No backslashes, no leading slash, no empty segments, no `.` or `..` segments.
- No control characters (code points < 32).
- Paths must be unique within the `files` array.

**Result:**

```javascript
{
  reference: string,     // 64-character hex Swarm reference
  bzzUrl: string,        // "bzz://<reference>"
  tagUid: number | null  // Upload tag for progress tracking (if supported)
}
```

**Errors:** `4001` if the user rejects a per-publish prompt. `4100` if not connected. `4900` if node unavailable. `-32602` if params invalid, files exceed `maxFileCount`, or total size exceeds `maxFilesBytes`.

---

#### `swarm_getUploadStatus`

Query the upload progress of a previously initiated file upload.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `tagUid` | `number` | Yes | The tag ID returned by `swarm_publishFiles`. |

**Result:**

```javascript
{
  tagUid: number,
  split: number,     // Total chunks
  seen: number,      // Chunks seen by the node
  stored: number,    // Chunks stored locally
  sent: number,      // Chunks dispatched to the network
  synced: number,    // Chunks fully replicated
  progress: number,  // 0-100 percentage (based on sent/split)
  done: boolean      // true when all chunks have been sent
}
```

**Errors:** `4100` if not connected or tag not owned by this origin, `-32602` if `tagUid` invalid.

**Security:** Implementations MUST enforce origin-scoped tag ownership. A page MUST NOT be able to query upload status for tags created by a different origin. This prevents cross-origin upload snooping.

**Persistence:** Tag ownership is session-scoped. Upload status for tags created in a previous browser session MAY be unavailable. Implementations are NOT REQUIRED to persist tag ownership across restarts.

---

#### `swarm_createFeed`

Create a mutable Swarm feed with a stable `bzz://` URL.

Feeds allow web applications to maintain updatable content at a fixed address. The feed manifest provides a permanent `bzz://` URL that always resolves to the latest update.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | Yes | Feed identifier, unique per origin. Max 64 chars, no `/`, no control chars. |

**Result:**

```javascript
{
  feedId: string,              // The feed name (same as input)
  owner: string,               // Ethereum address of the signing key
  topic: string,               // Hex-encoded topic hash
  manifestReference: string,   // 64-character hex reference to the feed manifest
  bzzUrl: string,              // "bzz://<manifestReference>"
  identityMode: string         // "app-scoped" or "bee-wallet"
}
```

**Errors:** `4001` if the user rejects the feed-permission prompt. `4100` if the origin lacks basic connection or the implementation cannot surface a permission prompt. `4900` if node unavailable. `-32602` if name invalid.

**Behavior:**
- Creating a feed that already exists MUST be idempotent — return the existing feed's metadata.
- Implementations MUST support at least one feed identity mode:
  - **`app-scoped`** (RECOMMENDED default): A dedicated signing key derived per-origin. The key is never funded and cannot sign transactions. This provides origin isolation — one dApp cannot impersonate another's feeds.
  - **`bee-wallet`**: The node's main Bee wallet key. Useful when the dApp needs feeds signed by a known, funded identity.
- The identity mode choice MAY be presented to the user during the feed permission prompt.
- Feed creation requires a separate permission grant beyond basic connection access. Implementations SHOULD prompt users specifically for feed access.

**Feed Topic Derivation:**

The topic for a feed MUST be derived from the normalized origin and the feed name:

```
topic = keccak256(normalizedOrigin + "/" + feedName)
```

This ensures feeds are origin-scoped at the protocol level — two different origins using the same feed name produce different topics.

---

#### `swarm_updateFeed`

Update a feed to point at a new content reference.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `feedId` | `string` | Yes | Feed name (as returned by `swarm_createFeed`). |
| `reference` | `string` | Yes | 64-character hex Swarm reference to point the feed at. |

**Result:**

```javascript
{
  feedId: string,    // The feed name
  reference: string, // The new content reference
  bzzUrl: string,    // "bzz://<manifestReference>" (stable feed URL)
  index: number      // The sequence index that was written
}
```

**Errors:** `4001` if the user rejects a feed-permission prompt this call triggered. `4100` if the origin lacks basic connection or the implementation cannot surface a permission prompt. `4900` if node unavailable. `-32602` if params invalid or feed doesn't exist.

**Behavior:**
- Writes are serialized per-topic (same mutex as `swarm_writeFeedEntry`). The returned `index` reflects the actual sequence index written.

---

#### `swarm_writeFeedEntry`

Write an arbitrary payload directly to a feed index as a Single Owner Chunk (SOC).

This enables the **journal pattern** — an append-only log where each entry is an independently-addressed chunk at an incrementing index. Unlike `swarm_updateFeed` (which stores a 32-byte content reference), `swarm_writeFeedEntry` stores the payload in the feed itself.

The 4 KB SOC body limit is internal to the storage envelope and is NOT a dApp-visible payload cap. Payloads up to the SOC limit are stored directly in the chunk; larger payloads MUST be wrapped transparently — the implementation uploads the bytes (e.g., as a BMT tree via `POST /bytes`) and writes only the root chunk reference into the SOC body. DApps see one consistent payload cap, `maxDataBytes`, across `swarm_publishData` and `swarm_writeFeedEntry`.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `name` | `string` | Yes | Feed name (same namespace as `swarm_createFeed`). The feed must already exist. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | The payload to write. Strings are encoded as UTF-8. |
| `index` | `number` | No | Explicit index to write at. If omitted, auto-increments to the next available index. |

**Result:**

```javascript
{
  index: number   // The feed index that was written
}
```

**Errors:** `4001` if the user rejects a feed-permission prompt this call triggered. `4100` if the origin lacks basic connection or the implementation cannot surface a permission prompt. `4900` if node unavailable. `-32602` if params invalid, feed doesn't exist, index is occupied (`index_already_exists`), or payload exceeds `maxDataBytes` (`payload_too_large`).

**Behavior:**

- The feed MUST already exist (created via `swarm_createFeed`).
- If `index` is omitted, the provider MUST resolve the next available index and write at that index. The resolved index is returned.
- If `index` is provided, the provider MUST check whether an entry already exists at that exact index. If it does, the write MUST be rejected with error data `{ reason: "index_already_exists" }`. This overwrite protection is the core safety guarantee of the journal pattern.
- The existence check MUST use **exact-match** semantics — see [Implementation Note: Exact-Match Feed Reads](#implementation-note-exact-match-feed-reads). Implementations MUST NOT use Bee's `GET /feeds/{owner}/{topic}?index=N` endpoint for this probe: that endpoint has at-or-before semantics and would falsely reject any sparse-index write whenever any earlier index exists.
- The overwrite check and the write MUST be atomic — implementations MUST NOT allow concurrent writes to race between the check and the write to the same index. A per-topic serialization mechanism (e.g., a mutex) is RECOMMENDED.
- Sparse indices are valid. Writing to index 1000 without indices 0–999 existing is allowed. Applications that want sequential journal semantics SHOULD omit `index` and rely on auto-increment.

**Write serialization:** Implementations MUST serialize writes to the same feed topic. Two concurrent `swarm_writeFeedEntry` calls to the same feed MUST NOT produce index collisions. Writes to different feeds MAY execute in parallel.

---

#### `swarm_readFeedEntry`

Read a feed entry at a specific index, or read the latest entry. This is a read-only operation on public Swarm data and does NOT require any permission grant — neither connection (`swarm_requestAccess`) nor feed-level. Any web page MAY call it.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `topic` | `string` | Conditional | 64-character hex topic. Required if `name` is not provided. |
| `name` | `string` | Conditional | Feed name (same namespace as `swarm_createFeed`). Required if `topic` is not provided. |
| `owner` | `string` | Conditional | Ethereum address of the feed owner (signer). See owner resolution rules below. |
| `index` | `number` | No | Specific index to read. If omitted, reads the latest entry. |

Exactly one of `topic` or `name` MUST be provided:
- **`topic`**: Raw 64-character hex topic. The provider constructs the topic directly from these bytes (no hashing). Use this to read feeds created by other origins or other users. `owner` is required.
- **`name`**: Feed name string. The provider derives the topic by hashing: `keccak256(normalizedOrigin + "/" + name)`. Use this to read your own feeds.

**Owner resolution:**
- When using `topic`: `owner` is required.
- When using `name` without `owner`: The provider looks up the owner from its local feed store (populated when `swarm_createFeed` was called). No vault unlock or signing is needed — this is a metadata lookup.
- When using `name` with `owner`: The provided owner is used. This allows reading another user's feed that shares the same app-scoped topic derivation.

**Result:**

```javascript
{
  data: string,           // Base64-encoded payload
  encoding: "base64",     // Explicit encoding identifier
  index: number,          // The index that was read
  nextIndex: number|null  // Next writable index (only present when reading the latest entry)
}
```

**Why base64:** The payload traverses process boundaries (main process → renderer → page context) via IPC and `postMessage`. Binary payloads do not survive this chain intact. Base64 is the safe universal encoding. The caller decodes:

```javascript
const bytes = Uint8Array.from(atob(result.data), c => c.charCodeAt(0))
const text = new TextDecoder().decode(bytes)
```

**Errors:** `4900` if node unreachable, `-32602` if params invalid or the calling origin has exceeded its per-origin read budget (`rate_limited`). Notably does NOT return `4100` — no permission is required to call this method.

Structured error reasons in `data.reason`:

| Reason | Meaning |
|---|---|
| `feed_empty` | The feed exists but has no entries written yet (returned for latest-entry reads). |
| `entry_not_found` | No entry exists at the requested index. |
| `feed_not_found` | Used `name` without `owner`, but the feed has not been created yet under this origin. |
| `rate_limited` | The calling origin has exceeded the implementation's per-origin rate or bandwidth budget for permission-free reads. See [Resource Exhaustion](#resource-exhaustion). |

**Behavior:**

- This method does NOT require any permission grant. Feeds are public data on Swarm and the same lookup is available from any Bee gateway without auth; gating it would be friction without security benefit. This is symmetric with `swarm_listFeeds`.
- Pre-flight checks MUST be limited to verifying the Bee node's HTTP API is reachable. Mode checks (ultra-light), readiness checks, and stamp checks MUST NOT be applied — reads work regardless of node mode and do not consume stamps.
- Implementations MUST distinguish "not found" errors (HTTP 404/500 from the Bee API) from transient errors (network timeouts, internal failures). Transient errors MUST propagate as `-32603` (Internal Error), NOT be misclassified as `feed_empty` or `entry_not_found`.
- When reading the latest entry (`index` omitted), `nextIndex` indicates the next index available for writing. When reading a specific index, `nextIndex` is `null`.
- When `index` is provided, implementations MUST use **exact-match** semantics — see [Implementation Note: Exact-Match Feed Reads](#implementation-note-exact-match-feed-reads). The returned `result.index` MUST equal the requested `index`. Implementations MUST NOT return data from a different index that happens to be the highest at-or-before the requested index.

---

#### `swarm_listFeeds`

Return the calling origin's feed records — every feed previously created via `swarm_createFeed` under the caller's normalized origin.

This is an introspection method scoped to the calling origin. It does NOT require any permission grant — neither connection (`swarm_requestAccess`) nor feed-level. Any web page MAY call it.

**Params:** None. The result is determined entirely by the caller's normalized origin. Implementations SHOULD silently ignore any params supplied; strict rejection buys nothing for an introspection-only method.

**Result:**

```javascript
[
  {
    name: string,                  // Feed name (as passed to swarm_createFeed)
    topic: string,                 // 64-character hex topic (no 0x prefix)
    owner: string,                 // Checksummed Ethereum address of the signing key
    manifestReference: string,     // 64-character hex reference to the feed manifest
    bzzUrl: string,                // "bzz://<manifestReference>"
    createdAt: number,             // ms unix timestamp when createFeed was called
    lastUpdated: number | null,    // ms unix timestamp of last swarm_updateFeed (null otherwise)
    lastReference: string | null   // last reference written via swarm_updateFeed (null otherwise)
  },
  ...
]
```

Returns an empty array `[]` for origins with no feeds — including origins that have never granted permission, origins that have granted but not created feeds, and origins whose permission has been revoked.

**Errors:** None expected on the happy path. `-32602` with `data.reason = "rate_limited"` if the calling origin has exceeded its per-origin read budget (see [Resource Exhaustion](#resource-exhaustion)). `-32603` (Internal Error) only on unexpected internal failures (e.g., feed-store read errors).

**Behavior:**

- **Origin scoping is mandatory.** The result MUST contain only feeds created under the calling page's normalized origin. Implementations MUST NOT return feeds created under any other origin.
- **No permission required**, by design:
  - Feed coordinates are deterministic given `(origin, name)` — the calling origin can compute the same set itself given the names of feeds it created. Listing them does not reveal anything beyond what the caller already knows.
  - Feed metadata persists across permission revocation by design (so an origin re-granted access after revocation resumes its prior identity and can continue using its existing feeds). Requiring permission for introspection would create UX friction without security benefit.
  - Symmetric with `swarm_readFeedEntry`: both are read-only operations on data the caller could obtain elsewhere.
- **`lastUpdated` and `lastReference`** are populated only by `swarm_updateFeed`-style usage. For feeds maintained as journals via `swarm_writeFeedEntry`, both fields stay `null` (those operations do not update the manifest reference).
- **`bzzUrl`** is a stable convenience built from `manifestReference`. For `swarm_updateFeed`-style feeds it resolves to the latest pointed-at content; for journal-style feeds (where the SOC payload is raw bytes rather than a content reference) the manifest URL has limited utility — applications should use `swarm_readFeedEntry` to read journal contents.

---

### Low-Level Chunk Methods

The methods specified above are *high-level*: they express publishing and feed intent, and the provider translates that intent into Swarm's underlying chunk operations. This section defines the *low-level* tier — direct read and write access to individual Swarm chunks.

Every Swarm data structure is ultimately a graph of chunks: **content-addressed chunks (CACs)** for immutable data, and **Single Owner Chunks (SOCs)** — signed chunks at a caller-chosen address — used as the building block for mutable structures such as feeds. Exposing the chunk layer lets dApps and libraries implement higher-level constructs this specification does not define directly — custom manifests, epoch feeds, access-controlled data, and structures not yet supported natively by Bee — without a revision of this specification for each one.

The chunk tier is **additive**. It does not replace the high-level methods, which carry consent semantics, safety guarantees (e.g. the journal overwrite protection of `swarm_writeFeedEntry`), and an efficient bulk-data path. Applications SHOULD prefer the high-level methods where they fit, and reach for the chunk tier only for primitives the high-level methods do not provide.

**Chunk type is explicit.** Swarm carries no in-band chunk-type tag, and a chunk's 32-byte address does not reveal whether it is a CAC or a SOC; Bee currently distinguishes them heuristically (see [SWIP-67](https://github.com/ethersphere/SWIPs/pull/67) and [bee#5445](https://github.com/ethersphere/bee/pull/5445)). This specification sidesteps that ambiguity by making the chunk type explicit in the **method name** — `swarm_publishChunk`/`swarm_readChunk` operate on CACs, `swarm_writeSingleOwnerChunk`/`swarm_readSingleOwnerChunk` operate on SOCs. The provider never has to guess, and the API does not depend on the resolution of the upstream heuristic.

**Chunk size.** A Swarm chunk payload is at most 4096 bytes. This is a protocol constant, advertised as `maxChunkPayloadBytes` in `swarm_getCapabilities` for completeness, but it is not implementation-configurable.

**Not for bulk data.** Each chunk method call crosses a process boundary and incurs IPC overhead. Uploading large content as thousands of individual `swarm_publishChunk` calls is far slower than `swarm_publishData`, which splits content into a BMT tree in a single node operation. Applications SHOULD use `swarm_publishData`/`swarm_publishFiles` for bulk content and reserve the chunk methods for single chunks and custom structures that cannot be expressed at the high-level tier.

All chunk uploads MUST be pinned on the local node, as with `swarm_publishData`. The implementation selects an appropriate postage batch automatically.

**Type validation on read.** Implementations MUST validate the returned bytes against the requested chunk type using Swarm's standard chunk verification rules — BMT hash recomputation for CACs, SOC signature recovery and `keccak256(identifier_32 || owner_20)` address derivation for SOCs. A mismatch MUST be reported as `chunk_type_mismatch`. See [Implementation Note: Exact-Match Feed Reads](#implementation-note-exact-match-feed-reads) for SOC address derivation and the span-endianness rules; refer to Swarm's chunk-format specification for the canonical byte layout (with [bee-js](https://github.com/ethersphere/bee-js) as a reference implementation).

**Options object.** Several chunk methods accept an optional `options` object. The v1 surface is deliberately narrow — see [Future Extensions](#future-extensions) for the deferred fields and the rationale. Implementations MUST reject any option key they do not recognize with `-32602` and `data.reason = "unsupported_option"`, so that future option additions degrade safely.

---

#### `swarm_publishChunk`

Upload a single content-addressed chunk (CAC).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Chunk payload. Strings are encoded as UTF-8. MUST be ≤ `maxChunkPayloadBytes` (4096). |
| `span` | `number \| bigint` | No | The value committed in the chunk's 8-byte span field. Defaults to the byte length of `data` (always representable as a `number`). Set explicitly only when constructing intermediate nodes of a custom BMT tree. MUST be a non-negative integer fitting in 8 unsigned bytes (`0 ≤ span ≤ 2⁶⁴ − 1`). Pass a `bigint` when the value exceeds `Number.MAX_SAFE_INTEGER` (2⁵³ − 1); a `number` outside the safe-integer range MUST be rejected with `invalid_span`. |
| `options` | `object` | No | Reserved for future use. No fields are standardized in v1; unknown fields MUST be rejected with `unsupported_option`. |

**Result:**

```javascript
{
  reference: string   // 64-character hex chunk address
}
```

**Errors:** `4001` if the user rejects a per-publish prompt. `4100` if not connected. `4900` if node unavailable. `-32602` if params invalid (`payload_too_large`, `invalid_span`, `unsupported_option`).

**Behavior:**
- The chunk address is the BMT hash of `span_8LE || data`. See [Implementation Note: Exact-Match Feed Reads](#implementation-note-exact-match-feed-reads) for the **little-endian** span convention.
- Subject to the **publish permission tier** — the same per-operation consent / auto-approve as `swarm_publishData`.
- CACs are immutable; uploading a chunk that already exists is idempotent and returns an identical reference.
- Chunk payloads are opaque bytes. Per-chunk encryption is the caller's responsibility — the provider stores the bytes as given. (Swarm's encryption primitive lives at the BMT-tree layer, not at single `/chunks` endpoints; see [Future Extensions](#future-extensions).)

---

#### `swarm_readChunk`

Retrieve a single content-addressed chunk by its address. This is a read-only operation on public Swarm data and does NOT require any permission grant — symmetric with `swarm_readFeedEntry`. Any web page MAY call it. Subject to the per-origin rate limits described in [Security Considerations](#resource-exhaustion).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `reference` | `string` | Yes | 64-character hex chunk address. |
| `options` | `object` | No | Reserved for future use. Unknown fields MUST be rejected with `unsupported_option`. |

**Result:**

```javascript
{
  data: string,        // Base64-encoded chunk payload (span field stripped)
  encoding: "base64",
  span: number | bigint   // Decoded span value; `number` when ≤ Number.MAX_SAFE_INTEGER, `bigint` otherwise
}
```

**Errors:** `4900` if node unreachable, `-32602` for invalid params (`invalid_reference`, `unsupported_option`). `data.reason` is `chunk_not_found` if no chunk exists at the address, `chunk_type_mismatch` if the returned bytes do not validate as a CAC at the requested address, or `rate_limited` if the per-origin budget is exceeded.

**Behavior:**
- Works regardless of node mode; reads consume no stamps. Pre-flight checks MUST be limited to verifying the Bee HTTP API is reachable (same rule as `swarm_readFeedEntry`).
- Implementations MUST recompute the BMT hash of the returned bytes (over `span_8LE || data`) and reject any chunk whose hash does not equal the requested `reference` (`chunk_type_mismatch`). A returned SOC at the same address — which is structurally possible — MUST be rejected here; the caller intended a CAC and should use `swarm_readSingleOwnerChunk` for SOCs.
- Implementations MUST distinguish "not found" (HTTP 404) from transient errors (5xx, timeouts). Transient errors MUST propagate as `-32603`, NOT be misclassified as `chunk_not_found`.

---

#### `swarm_writeSingleOwnerChunk`

Write a Single Owner Chunk at a caller-chosen `identifier`, signed by the origin's signing identity. SOCs are the primitive behind every mutable Swarm structure (feeds, epoch feeds, custom mutable references).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `identifier` | `string` | Yes | 64-character hex (32-byte) SOC identifier, chosen by the caller. |
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | Payload. Strings encoded as UTF-8. MUST be ≤ `maxChunkPayloadBytes` (4096). |
| `span` | `number \| bigint` | No | As in `swarm_publishChunk` (same range, same `bigint`-for-out-of-safe-integer-range rule). |
| `options` | `object` | No | Reserved for future use. Unknown fields MUST be rejected with `unsupported_option`. |

**Result:**

```javascript
{
  reference: string,    // 64-character hex SOC address
  owner: string,        // Checksummed Ethereum address of the signing key
  identifier: string    // The identifier (echoed)
}
```

**Errors:** `4001` if the user rejects a feed-permission prompt this call triggered. `4100` if the origin lacks basic connection or the implementation cannot surface a permission prompt. `4900` if node unavailable. `-32602` if params invalid (`invalid_identifier`, `invalid_span`, `payload_too_large`, `unsupported_option`).

**Behavior:**
- The provider signs the SOC using the **origin's signing identity** — the same identity established at feed-permission grant time and exposed via `swarm_getSigningIdentity`. There is no caller-supplied `identityMode` parameter in v1 (see [Future Extensions](#future-extensions)). Key material MUST NOT be exposed to the page context (consistent with the feed key-material rules in [Security Considerations](#feed-key-material)).
- The SOC address is `keccak256(identifier_32 || owner_20)` — see [Implementation Note: Exact-Match Feed Reads](#implementation-note-exact-match-feed-reads).
- Subject to the **feed permission tier** — SOC writes involve signing and require the feed-access grant, the same grant as `swarm_createFeed`.
- Because the owner is an origin-scoped key, a dApp can only create SOCs under its own identity. It cannot forge SOCs owned by another origin or by an arbitrary address.
- **No overwrite guarantee.** The same `(owner, identifier)` pair SHOULD be treated as immutable; the behavior of re-writing a SOC at an existing `(owner, identifier)` is undefined and discouraged. Applications that need mutability MUST use distinct identifiers (e.g. the feed pattern `keccak256(topic || index)`), and applications that need overwrite-rejection MUST use `swarm_writeFeedEntry`.

---

#### `swarm_readSingleOwnerChunk`

Retrieve a Single Owner Chunk. Read-only operation on public Swarm data; requires NO permission grant. Subject to the per-origin rate limits described in [Security Considerations](#resource-exhaustion).

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `address` | `string` | Conditional | 64-character hex SOC address. |
| `owner` | `string` | Conditional | Ethereum address of the SOC owner. Required if `address` is not provided. |
| `identifier` | `string` | Conditional | 64-character hex identifier. Required if `address` is not provided. |
| `options` | `object` | No | Reserved for future use. Unknown fields MUST be rejected with `unsupported_option`. |

Exactly one of `address`, or the pair (`owner` + `identifier`), MUST be provided. When the pair is given, the provider derives the address as `keccak256(identifier_32 || owner_20)`.

**Result:**

```javascript
{
  data: string,            // Base64-encoded payload (span field stripped)
  encoding: "base64",
  span: number | bigint,   // Decoded span value; `number` when ≤ Number.MAX_SAFE_INTEGER, `bigint` otherwise
  reference: string,       // 64-character hex SOC address (echoed/derived)
  owner: string,       // Recovered owner address
  identifier: string,
  signature: string    // 130-character hex (65-byte) SOC signature, for caller-side verification
}
```

**Errors:** `4900` if node unreachable, `-32602` if params invalid (`invalid_owner`, `invalid_identifier`, `invalid_reference`, `unsupported_option`). `data.reason` is `chunk_not_found` if no SOC exists at the address, `chunk_type_mismatch` if the returned bytes do not validate as a SOC for the requested address, or `rate_limited` if the per-origin budget is exceeded.

**Behavior:**
- Exact-match by address — no heuristics, no at-or-before search.
- Implementations MUST parse the returned SOC, recover the signer from the signature, derive `keccak256(identifier_32 || owner_20)`, and reject any chunk whose derived address does not equal the requested address (`chunk_type_mismatch`). A returned CAC at the same address MUST be rejected here.
- Node-mode independent; consumes no stamps; pre-flight limited to HTTP reachability. Transient vs. not-found distinction as in `swarm_readChunk`.

---

#### `swarm_getSigningIdentity`

Return the origin's signing identity — the key the provider uses to sign feed updates and SOCs on this origin's behalf. Useful for pre-computing SOC addresses (e.g. for epoch-feed construction) before any write, and as the canonical entry point for acquiring the feed-permission grant without committing to a specific write.

This method operates under the **feed permission tier**: the returned address *is* the dApp's persistent on-chain identity, and exposing it without consent would let arbitrary pages enumerate per-origin identities.

**Params:** None.

**Result:**

```javascript
{
  owner: string,        // Checksummed Ethereum address of the signing key
  identityMode: string  // "app-scoped" or "bee-wallet" (whichever was established at feed-permission grant)
}
```

**Errors:** `4001` if the user rejects the feed-permission prompt. `4100` if the origin has not been granted basic connection (`swarm_requestAccess`) or the implementation cannot surface a permission prompt in the current context (e.g. a nested browsing context where consent UI is unavailable).

**Behavior:**
- If the calling origin has not yet been granted the feed-permission tier, the implementation MUST prompt the user for feed/signing access (the same prompt as `swarm_createFeed`'s first call) and return the identity on approval. This makes `swarm_getSigningIdentity` a viable bootstrap path for dApps that need to pre-compute SOC addresses before any write.
- If feed-permission has already been granted, the method MUST return immediately without prompting.
- The returned `owner` MUST be identical to the `owner` returned by `swarm_createFeed`, `swarm_writeSingleOwnerChunk`, and the entries of `swarm_listFeeds` for this origin.
- The identity is stable for the lifetime of the origin's feed-permission grant. Identity mode selection happens once, at feed-permission grant time; there is no caller-driven mode selection in v1 (see [Future Extensions](#future-extensions)).

---

### Implementation Note: Exact-Match Feed Reads

This section is **informative**. It documents a Bee API behavior that affects the correctness of `swarm_writeFeedEntry`'s overwrite protection and `swarm_readFeedEntry`'s explicit-index path.

#### The problem

Bee's `GET /feeds/{owner}/{topic}?index=N` endpoint does NOT return the entry at exact index N. Its semantics are **at-or-before**: the endpoint performs an epoch search and returns the latest Single Owner Chunk (SOC) at index ≤ N. So:

- A read of index 6 on a feed where only index 3 has been written returns index 3's chunk (with no out-of-band signal that index 6 itself is empty).
- A pre-write existence probe at index 6 returns whatever's at index 5 / 4 / ... / 0 if any of them exist, falsely flagging index 6 as occupied.

For the journal pattern, this breaks both halves of the contract: explicit-index reads can return the wrong entry, and overwrite protection falsely rejects sparse writes.

#### The fix

Implementations SHOULD derive the SOC address directly and fetch via `GET /chunks/{socAddress}`, which is exact-match.

```
identifier  = keccak256( topic_32 || index_8BE )
socAddress  = keccak256( identifier_32 || ownerAddress_20 )
```

Where:
- `topic_32` — the feed's 32-byte topic (the same topic used elsewhere in the feed API).
- `index_8BE` — the feed index encoded as **8 bytes big-endian**.
- `ownerAddress_20` — the 20-byte Ethereum address of the feed signer.

A 404 from `GET /chunks/{socAddress}` means no entry exists at the exact requested index — translated to `entry_not_found` for reads and "index available" for pre-write probes. 5xx and connection errors MUST propagate as transient (`-32603` Internal Error), NOT be misclassified as not-found.

#### When to use which endpoint

The latest-entry read path is unaffected — at-or-before is exactly the desired behavior, and `GET /feeds/{owner}/{topic}` returns the latest entry plus the `swarm-feed-index` and `swarm-feed-index-next` response headers (`%016x`) that drive auto-increment.

| Operation | Endpoint | Semantics |
|---|---|---|
| `swarm_readFeedEntry` (no `index`) — latest entry + `nextIndex` | `GET /feeds/{owner}/{topic}` | At-or-before |
| `swarm_writeFeedEntry` auto-increment — find next writable index | `GET /feeds/{owner}/{topic}` | At-or-before |
| `swarm_readFeedEntry` with explicit `index` | `GET /chunks/{socAddress}` | Exact-match |
| `swarm_writeFeedEntry` overwrite probe | `GET /chunks/{socAddress}` | Exact-match |

#### Endianness trap

Bee uses **big-endian** for the 8-byte feed index in identifier derivation, but **little-endian** for the 8-byte `span` (payload length) prefix in the SOC body. These are different fields with different conventions in the same operation. Implementations going through `bee-js` get both right via its built-in helpers; implementations writing directly against this spec MUST handle the two conventions separately.

---

### Permission Model

#### Origin Normalization

Implementations MUST normalize the requesting page's origin to a stable, content-addressed root identity. For decentralized web contexts where pages are served via local gateways, the HTTP origin (e.g., `http://127.0.0.1:1633`) does NOT represent the content's identity.

The normalization rules are:

| Display URL | Normalized Origin |
|---|---|
| `ens://myapp.eth/#/path` | `myapp.eth` |
| `myapp.eth/blog` | `myapp.eth` |
| `bzz://abc123def.../page` | `bzz://abc123def...` |
| `ipfs://QmABC.../docs` | `ipfs://QmABC...` |
| `ipns://host/guide` | `ipns://host` |
| `rad://z123.../tree` | `rad://z123...` |
| `https://app.example.com/page` | `https://app.example.com` |

The key insight: the origin is derived from the **user-visible URL** (the address bar), not from `window.location` which reflects the internal gateway routing.

#### Permission Lifecycle

1. **Connection:** Granted via `swarm_requestAccess`. Persisted per-origin.
2. **Publish:** Each `swarm_publishData`/`swarm_publishFiles`/`swarm_publishChunk` call MAY require per-operation user approval, unless the user has opted into auto-approve for this origin. CAC chunk uploads fall under the same publish tier as `swarm_publishData`. If a per-publish prompt is shown and the user rejects it, the method MUST reject with `4001` (User Rejected); `4100` (Unauthorized) remains reserved for the cases where the origin lacks basic connection or the implementation cannot surface a permission prompt in the current context.
3. **Feed writes and signing:** Operations that involve signing with the origin's identity — `swarm_createFeed`, `swarm_updateFeed`, `swarm_writeFeedEntry`, `swarm_writeSingleOwnerChunk`, and the identity-disclosure method `swarm_getSigningIdentity` — require an additional feed-specific permission grant, separate from the connection permission. Raw SOC writes are gated here (not under the publish tier) because they involve signing and share key material with feeds. Any feed-tier method MAY trigger a user prompt to acquire this grant on first call. If the user rejects, the method MUST reject with `4001` (User Rejected); `4100` (Unauthorized) is reserved for the cases where the origin lacks basic connection or the implementation cannot surface a permission prompt in the current context.
4. **Reads and introspection:** `swarm_readFeedEntry`, `swarm_readChunk`, `swarm_readSingleOwnerChunk`, and `swarm_listFeeds` require NO permission grant. The data is either public on Swarm or deterministic given the caller's origin — none of it reveals anything the caller couldn't obtain elsewhere or compute itself. All four methods MUST work without a prior `swarm_requestAccess`, and MUST be rate-limited per origin (see [Security Considerations](#resource-exhaustion)).
5. **Disconnection:** The user can revoke access at any time. The provider MUST emit a `disconnect` event and reject subsequent permission-gated requests with error code `4100`. Permission-free methods (`swarm_getCapabilities`, `swarm_readFeedEntry`, `swarm_readChunk`, `swarm_readSingleOwnerChunk`, `swarm_listFeeds`) MUST continue to function after disconnection — `swarm_listFeeds` in particular continues returning the previously-created feed records, which by design persist across revocation so a subsequent re-grant restores identity continuity.

#### Auto-Approve (OPTIONAL)

Implementations MAY offer users the option to auto-approve publish (including CAC chunk uploads) and/or feed operations (including SOC writes) for trusted origins. When auto-approve is active:
- The implementation MUST still enforce all validation, size limits, and pre-flight checks.
- The implementation SHOULD provide a visual indicator that auto-approve is active.
- The user MUST be able to revoke auto-approve at any time.

---

### Limits

Implementations MUST enforce upload size, file count, and path length limits. The limits MUST be discoverable via `swarm_getCapabilities`. Recommended defaults:

| Limit | Recommended Default | Notes |
|---|---|---|
| `maxDataBytes` | 10 MB (10,485,760 bytes) | Applies to both `swarm_publishData` and `swarm_writeFeedEntry` payloads. |
| `maxFilesBytes` | 50 MB (52,428,800 bytes) | Total size across all entries in `swarm_publishFiles`. |
| `maxFileCount` | 100 files | Per `swarm_publishFiles` call. |
| `maxPathBytes` | 100 (UTF-8 bytes) | Per `files[].path` in `swarm_publishFiles`. Implementations MUST advertise at least 100. |
| `maxChunkPayloadBytes` | 4096 (bytes) | Per `swarm_publishChunk` and `swarm_writeSingleOwnerChunk` payload. Fixed by the Swarm chunk protocol; implementations MUST advertise exactly 4096. |

Implementations MAY use different limits but MUST report them accurately in `swarm_getCapabilities`.

The `maxPathBytes` floor of 100 reflects current implementation reality: reference implementations build uploads as USTAR tar archives (`Content-Type: application/x-tar` with `Swarm-Collection: true`), and USTAR's `name` header field is exactly 100 bytes. Without PAX extensions — which are out of scope for v1 — paths longer than 100 UTF-8 bytes cannot be encoded. Future implementations supporting PAX or alternative upload formats MAY advertise a larger `maxPathBytes`.

---

## Rationale

### Why EIP-1193 style?

The `window.ethereum` pattern ([EIP-1193](https://eips.ethereum.org/EIPS/eip-1193)) is well-understood by web3 developers. By following the same request/response pattern and reusing compatible error codes, we minimize the learning curve and allow existing tooling patterns (event listeners, promise-based flows, error handling) to transfer directly.

### Why not expose the full Bee API?

Exposing the full Bee HTTP API to web pages would be a security risk — it includes administrative endpoints (staking, chequebook management, debug APIs) that should never be accessible to arbitrary web content. The provider API exposes only publishing and feed primitives, with user consent gating every operation.

### Why origin normalization?

In decentralized web browsers, all content from IPFS, Swarm, ENS, etc. is typically served through a local gateway at `127.0.0.1`. Using `window.location.origin` would collapse all dApps into a single permission scope. Origin normalization uses the user-visible URL to derive the content's true identity, providing meaningful per-dApp isolation.

### Why app-scoped feed identities?

Without app-scoped identities, any dApp with feed permission could create feeds signed by the user's main wallet key — making feeds from different dApps indistinguishable and creating impersonation risks. App-scoped keys (derived per-origin from the user's master key) provide cryptographic isolation: each dApp's feeds are signed by a unique key that the dApp cannot extract.

### Why separate feed permissions?

Feeds involve key material (signing) and have long-term implications (the feed URL is permanent, updates are irrevocable). This warrants a separate, more deliberate permission grant beyond "allow this site to upload data."

### Why indexed feed entries alongside `updateFeed`?

`swarm_updateFeed` treats a feed as a mutable pointer — it stores a 32-byte Swarm reference at the next sequence index. This is ideal for "latest version" use cases (e.g., a website, a profile).

Many applications also need an **append-only log**: user activity feeds, message history, notification streams. Without indexed entry access, applications must implement a fragile "read current blob → append → re-upload entire blob → update feed" pattern. If the read fails (404, network blip), the entire history is silently overwritten.

`swarm_writeFeedEntry` and `swarm_readFeedEntry` expose the native Swarm feed index, enabling O(1) appends (write one SOC, no reads) and O(N) parallel reconstruction (fetch individual entries by index). The overwrite protection on explicit indices ensures the core safety guarantee: no silent history corruption.

### Why do feed and chunk reads require no permission grant?

Swarm feeds, CACs, and SOCs are public data — anyone who knows the address (or owner + identifier, or owner + topic + index) can read any chunk on the network from any Bee gateway. Adding a per-origin ACL on top would be security theater: gating doesn't restrict access to the data, only routes around the user's node, which any page can do on its own.

What gating *would* restrict is the user's bandwidth, local cache, and connection. Those are the real resources at risk, and they are protected by the **mandatory per-origin rate and bandwidth limits** specified in [Resource Exhaustion](#resource-exhaustion) — including tighter budgets for origins that have never called `swarm_requestAccess`. This puts the control where the actual risk lives, instead of behind a permission prompt that would block legitimate use cases (profile pages, cross-user activity views, link previews) for no security gain.

The same logic extends to `swarm_listFeeds`: feed coordinates are deterministic given `(origin, name)`, so listing them reveals nothing the calling origin could not compute itself.

### Why expose chunk operations?

Every Swarm data structure — feeds, manifests, ACT, GSOC, future constructions not yet supported by Bee such as epoch feeds — is built from chunks. Without a chunk tier, every new high-level primitive Swarm gains would require a new method in this specification and a new revision to ship it.

Exposing CAC and SOC read/write at the provider boundary moves that experimentation into the library layer: a library author can build a new manifest format, a new feed scheme, or a new access-control overlay on top of `swarm_publishChunk`/`swarm_readChunk`/`swarm_writeSingleOwnerChunk`/`swarm_readSingleOwnerChunk`, without touching this specification. This mirrors EIP-1193's role on Ethereum, where `eth_sendRawTransaction` and friends are the low-level transport and ergonomic abstractions (ethers, viem) live as libraries.

The chunk tier is constrained the same way the high-level methods are: origin-scoped permissions, host-managed postage, fixed payload size limit, per-origin rate budgets on permission-free reads, and signing-key custody inside the trusted context. It adds expressiveness without weakening the security posture — a 4 KB opaque blob upload is strictly less powerful than a 10 MB `swarm_publishData` call the same origin can already make.

### Why type-explicit method names?

Swarm chunks carry no in-band type tag, and a chunk's address does not encode whether the chunk is a CAC or a SOC. Bee disambiguates heuristically, which has produced real edge cases (see [SWIP-67](https://github.com/ethersphere/SWIPs/pull/67), [bee#5445](https://github.com/ethersphere/bee/pull/5445)).

Rather than wait on a Bee-level resolution or introduce our own heuristics, the API encodes the type in the method name: `swarm_publishChunk`/`swarm_readChunk` for CACs, `swarm_writeSingleOwnerChunk`/`swarm_readSingleOwnerChunk` for SOCs. The caller declares intent, the provider applies the correct upload endpoint and verification rules, and the spec does not depend on the upstream ambiguity ever being resolved.

This also unblocks a clean validation contract: on every read, the provider recomputes the type-specific address from the returned bytes and rejects mismatches as `chunk_type_mismatch`. The caller can rely on "if `swarm_readChunk(addr)` returned bytes, those bytes are the CAC at `addr`" — a guarantee the underlying Bee endpoint does not give.

### Why base64 for read responses?

Feed entry payloads are arbitrary bytes. The response travels from the Bee node through the main process, across IPC to the renderer, and via `postMessage` to the page context. Binary data (`Uint8Array`) does not survive this serialization chain intact across all environments. Base64 is the safe universal encoding. The `encoding: "base64"` field makes the contract explicit so callers know exactly how to decode.

## Backwards Compatibility

This SWIP introduces a new API surface. There are no backwards compatibility concerns as no prior standard for `window.swarm` exists. Implementations that predate this specification SHOULD migrate to conform to these interfaces.

Web pages that do not use `window.swarm` are unaffected. The provider MUST NOT modify any existing browser APIs or globals.

## Security Considerations

### Origin Trust Model

The provider relies on the host application (browser) to supply the correct origin for each request. If the host misidentifies a page's origin, the entire permission model breaks. Implementations MUST derive the origin from the user-visible URL (address bar), not from `window.location` or any value the page can control. The page context MUST NOT be able to influence its own origin identification.

### Resource Exhaustion

A connected origin could repeatedly publish data up to the size limit, consuming postage stamp capacity and local storage. Implementations SHOULD consider:

- **Rate limiting:** Throttling publish requests per origin per time window.
- **Stamp monitoring:** Warning the user when stamp capacity is running low due to dApp activity.
- **Per-origin accounting:** Tracking cumulative usage per origin so users can identify heavy consumers.

This specification does not mandate a specific rate-limiting scheme for permissioned operations, as appropriate limits depend on the node's capacity and the user's preferences.

#### Permission-Free Reads

The read methods that require no permission grant — `swarm_readFeedEntry`, `swarm_readChunk`, `swarm_readSingleOwnerChunk`, and `swarm_listFeeds` — can be invoked by any page that loads the provider, including pages the user has never granted access to. `swarm_readChunk` in particular widens this to arbitrary chunk addresses, effectively turning the user's node into a public retrieval path on behalf of any page.

The capability itself is benign — the same data is available from any public Swarm gateway — but the user's bandwidth, local cache, and network connection are not. Without throttling, a hostile page could drain the user's bandwidth by issuing high-volume chunk reads, or probe the local cache via timing.

Implementations MUST enforce **per-origin rate and bandwidth limits** on permission-free read methods. Origins exceeding the configured budget MUST receive `-32602` with `data.reason = "rate_limited"` (an analytics-friendly reason code, not an error condition the dApp should retry without backoff). Implementations MAY apply tighter limits to origins that have never called `swarm_requestAccess` than to previously-connected origins.

This specification does not mandate specific numeric thresholds, as appropriate limits depend on the node's bandwidth and the user's preferences. Implementations SHOULD make the limits user-visible and adjustable.

### Iframe and Nested Context Behavior

This specification does not define behavior for `window.swarm` inside iframes or nested browsing contexts. Implementations SHOULD restrict provider availability to the top-level browsing context. If an implementation chooses to expose the provider to iframes, the iframe's origin MUST be evaluated independently — it MUST NOT inherit the parent frame's permissions.

### Feed Key Material

App-scoped feed identities involve derived signing keys. Implementations MUST ensure that:

- Private key material is never exposed to the page context.
- Key derivation is deterministic (same origin always produces the same key) but not reversible (the page cannot derive the master key from its app-scoped key).
- Feed signing occurs in a trusted context (main process or secure enclave), never in the renderer or page context.

### Temporary Artifacts

Implementations that create temporary files or directories during upload processing (e.g., for `swarm_publishFiles` manifest construction) MUST clean up these artifacts regardless of whether the upload succeeds or fails.

## Future Extensions

The following capabilities are anticipated for future versions of this specification and are explicitly out of scope for version 1.0:

- **`capabilitiesChanged` event** — Proactive notification when the provider's capabilities change (e.g., node goes offline, stamps exhausted). Currently dApps must poll `swarm_getCapabilities` to detect state changes.
- **`preferredIdentityMode` parameter** — Allow dApps to express a preference for `app-scoped` or `bee-wallet` identity mode, rather than relying solely on user/implementation choice. When added, this parameter SHOULD land on `swarm_createFeed`, `swarm_writeSingleOwnerChunk`, and `swarm_getSigningIdentity` consistently.
- **`encoding` parameter for `swarm_readFeedEntry`, `swarm_readChunk`, `swarm_readSingleOwnerChunk`** — Allow callers to request a specific response encoding (e.g., `"utf8"`) to avoid manual base64 decoding for text payloads.
- **Expanded chunk `options`** — The chunk methods' `options` object is intentionally empty in v1, with `unsupported_option` providing forward-compat enforcement. Candidate fields for future revisions, each requiring a precise mapping to Bee's endpoint contract before standardization:
  - `trackProgress: true` on writes — provider issues a fresh origin-scoped `tagUid` (returned in the result) usable with `swarm_getUploadStatus`. The page MUST NOT supply a `tag` value directly, to preserve the origin ownership invariant `swarm_getUploadStatus` enforces.
  - `cache: boolean` on reads — pass-through to Bee's cache header.
  - **ACT (Access Control Trie)** on reads — Bee's `/chunks` endpoint accepts ACT headers; once ACT semantics are specified at this layer (key custody, grantee management, history references), it is a natural fit for the chunk tier.
  - **Per-chunk encryption** — Bee's encryption primitive currently lives at the `/bytes` BMT-tree layer, not at single `/chunks`. Adding it at the chunk tier requires either a Bee-level addition or a client-side convention; both are out of scope for v1.
  - **Redundancy (erasure coding)** — Same situation as encryption: a BMT-tree-layer feature in Bee, not a single-chunk one.
  - **`deferred` upload** — Bee's `swarm-deferred-upload` header is endpoint-general but not guaranteed at `/chunks`; pending verification.

Additionally, the `specVersion` field in `swarm_getCapabilities` is currently a SHOULD. A future revision may promote it to MUST once multiple implementations exist and version negotiation becomes necessary.

Implementations MAY experiment with these features, but they are not part of the 1.0 standard interface and MUST NOT be required for conformance.

## Test Cases

### Detection

```javascript
// Provider available
assert(typeof window.swarm !== 'undefined');
assert(typeof window.swarm.request === 'function');
```

### Connection Flow

```javascript
// Request access (user approves)
const result = await window.swarm.requestAccess();
assert(result.connected === true);
assert(typeof result.origin === 'string');
assert(Array.isArray(result.capabilities));

// Capabilities reflect connection
const caps = await window.swarm.getCapabilities();
assert(caps.canPublish === true || typeof caps.reason === 'string');
```

### Publish Data

```javascript
const result = await window.swarm.publishData({
  data: '<h1>Hello Swarm</h1>',
  contentType: 'text/html',
  name: 'greeting',
});
assert(/^[0-9a-f]{64}$/.test(result.reference));
assert(result.bzzUrl === `bzz://${result.reference}`);
```

### Publish Files

```javascript
const encoder = new TextEncoder();
const result = await window.swarm.publishFiles({
  files: [
    { path: 'index.html', bytes: encoder.encode('<h1>Hello</h1>'), contentType: 'text/html' },
    { path: 'style.css', bytes: encoder.encode('body { color: red; }'), contentType: 'text/css' },
  ],
  indexDocument: 'index.html',
});
assert(/^[0-9a-f]{64}$/.test(result.reference));
```

### Feed Lifecycle

```javascript
// Create feed
const feed = await window.swarm.createFeed({ name: 'my-blog' });
assert(feed.feedId === 'my-blog');
assert(/^[0-9a-f]{64}$/.test(feed.manifestReference));

// Publish content, then update feed
const content = await window.swarm.publishData({
  data: '<h1>Post #1</h1>',
  contentType: 'text/html',
});
const updated = await window.swarm.updateFeed({
  feedId: 'my-blog',
  reference: content.reference,
});
assert(updated.bzzUrl === feed.bzzUrl); // Same stable URL
assert(typeof updated.index === 'number'); // Sequence index returned
```

### Error Handling

```javascript
// Calling without access
try {
  await window.swarm.publishData({ data: 'test', contentType: 'text/plain' });
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === 4100); // Unauthorized
}

// Invalid params
try {
  await window.swarm.publishData({}); // missing data and contentType
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === -32602); // Invalid params
}
```

### Post-Disconnect Behavior

```javascript
// After user revokes access, permission-gated methods reject with 4100.
// Permission-free methods (getCapabilities, readFeedEntry, readChunk,
// readSingleOwnerChunk, listFeeds) MUST continue to function.
// (simulate disconnect via browser UI, then:)
try {
  await window.swarm.publishData({ data: 'test', contentType: 'text/plain' });
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === 4100); // Unauthorized
}

// Permission-free introspection still works:
const feeds = await window.swarm.listFeeds();
assert(Array.isArray(feeds)); // Returns previously-created feed records

const caps = await window.swarm.getCapabilities();
assert(caps.canPublish === false);
assert(caps.reason === 'not-connected');
```

### Feed Idempotency

```javascript
// Creating the same feed twice returns identical metadata
const feed1 = await window.swarm.createFeed({ name: 'my-blog' });
const feed2 = await window.swarm.createFeed({ name: 'my-blog' });
assert(feed1.manifestReference === feed2.manifestReference);
assert(feed1.owner === feed2.owner);
assert(feed1.topic === feed2.topic);
```

### Feed Journal (Write and Read Entries)

```javascript
// Create feed first
const feed = await window.swarm.createFeed({ name: 'activity' });

// Write entries (auto-increment)
const w0 = await window.swarm.writeFeedEntry({
  name: 'activity',
  data: JSON.stringify({ action: 'post', id: 1 }),
});
assert(w0.index === 0);

const w1 = await window.swarm.writeFeedEntry({
  name: 'activity',
  data: JSON.stringify({ action: 'post', id: 2 }),
});
assert(w1.index === 1);

// Read latest entry
const latest = await window.swarm.readFeedEntry({ name: 'activity' });
assert(latest.encoding === 'base64');
assert(latest.index === 1);
assert(latest.nextIndex === 2);

// Decode the payload
const bytes = Uint8Array.from(atob(latest.data), c => c.charCodeAt(0));
const entry = JSON.parse(new TextDecoder().decode(bytes));
assert(entry.action === 'post');
assert(entry.id === 2);

// Read specific index
const first = await window.swarm.readFeedEntry({ name: 'activity', index: 0 });
assert(first.index === 0);

// Read all entries in parallel
const all = await Promise.all(
  Array.from({ length: latest.nextIndex }, (_, i) =>
    window.swarm.readFeedEntry({ name: 'activity', index: i })
  )
);
assert(all.length === 2);
```

### Feed Journal — Overwrite Protection

```javascript
// Writing at an occupied index is rejected
await window.swarm.writeFeedEntry({ name: 'activity', data: 'first', index: 0 });
try {
  await window.swarm.writeFeedEntry({ name: 'activity', data: 'duplicate', index: 0 });
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === -32602);
  assert(err.data.reason === 'index_already_exists');
}
```

### Feed Journal — Sparse-Index Writes (Exact-Match Requirement)

```javascript
// Sparse writes are valid: writing index 5 with no entries 1-4 must succeed.
// Implementations using at-or-before semantics for the overwrite probe would
// falsely reject this write because index 0 exists.
await window.swarm.createFeed({ name: 'sparse' });
await window.swarm.writeFeedEntry({ name: 'sparse', data: 'first', index: 0 });
const w5 = await window.swarm.writeFeedEntry({ name: 'sparse', data: 'fifth', index: 5 });
assert(w5.index === 5);

// Reading explicit index 5 must return index 5's data, not index 0's.
// Implementations using at-or-before semantics for explicit-index reads would
// silently return index 0's payload.
const r5 = await window.swarm.readFeedEntry({ name: 'sparse', index: 5 });
assert(r5.index === 5);
const bytes = Uint8Array.from(atob(r5.data), c => c.charCodeAt(0));
assert(new TextDecoder().decode(bytes) === 'fifth');
```

### Feed Journal — Cross-User Read

```javascript
// Read another user's feed using raw topic + owner from their published objects
const otherUserEntry = await window.swarm.readFeedEntry({
  topic: 'a1b2c3...64-char-hex-topic...',
  owner: '0xOtherUserSignerAddress',
  index: 0,
});
assert(otherUserEntry.encoding === 'base64');
assert(typeof otherUserEntry.index === 'number');
```

### Feed Journal — Empty Feed

```javascript
// Reading latest from empty feed returns structured error
await window.swarm.createFeed({ name: 'empty-feed' });
try {
  await window.swarm.readFeedEntry({ name: 'empty-feed' });
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === -32602);
  assert(err.data.reason === 'feed_empty');
}
```

### Feed Read Without Any Permission

```javascript
// readFeedEntry requires NO permission — no requestAccess, no feed grant.
// An origin that has never called requestAccess can still read public feeds.
const entry = await window.swarm.readFeedEntry({
  topic: 'a1b2c3...64-char-hex-topic...',
  owner: '0xSomeAddress',
  index: 0,
});
assert(typeof entry.data === 'string');
assert(entry.encoding === 'base64');
```

### List Feeds — Origin-Scoped Introspection

```javascript
// Returns feeds previously created under the calling origin
await window.swarm.createFeed({ name: 'user-feed' });
await window.swarm.createFeed({ name: 'comments' });

const feeds = await window.swarm.listFeeds();
assert(Array.isArray(feeds));
assert(feeds.length >= 2);

const userFeed = feeds.find(f => f.name === 'user-feed');
assert(userFeed.bzzUrl.startsWith('bzz://'));
assert(/^[0-9a-f]{64}$/.test(userFeed.topic));
assert(/^0x[0-9a-fA-F]{40}$/.test(userFeed.owner));
assert(typeof userFeed.createdAt === 'number');
```

### List Feeds — Empty for Un-Granted Origin

```javascript
// listFeeds requires NO permission. An origin with no granted access
// and no created feeds simply gets an empty array — never an error.
const feeds = await window.swarm.listFeeds();
assert(Array.isArray(feeds));
assert(feeds.length === 0);
```

### Re-Connection Without Re-Prompt

```javascript
// Second requestAccess call returns existing state without prompting
const first = await window.swarm.requestAccess();
const second = await window.swarm.requestAccess();
assert(second.connected === true);
assert(second.origin === first.origin);
```

### Capabilities Before Connection

```javascript
// getCapabilities works without prior requestAccess
const caps = await window.swarm.getCapabilities();
assert(caps.canPublish === false);
assert(caps.reason === 'not-connected');
assert(typeof caps.limits.maxDataBytes === 'number');
assert(typeof caps.limits.maxPathBytes === 'number');
assert(caps.limits.maxPathBytes >= 100);
// specVersion is optional (SHOULD) in 1.0
if (caps.specVersion) assert(typeof caps.specVersion === 'string');
```

## Implementation

[Freedom Browser](https://github.com/solardev-xyz/freedom-browser) (PR [#19](https://github.com/solardev-xyz/freedom-browser/pull/19)) implements the original high-level surface — `swarm_requestAccess`, `swarm_getCapabilities`, `swarm_publishData`, `swarm_publishFiles`, `swarm_getUploadStatus`, `swarm_createFeed`, `swarm_updateFeed`, `swarm_writeFeedEntry`, `swarm_readFeedEntry`, `swarm_listFeeds`:

- **Provider injection:** [`src/main/webview-preload.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/webview-preload.js) — `window.swarm` object injected into webview page context
- **Main-process enforcement:** [`src/main/swarm/swarm-provider-ipc.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/swarm-provider-ipc.js) — method dispatch, validation, origin enforcement
- **Publishing:** [`src/main/swarm/publish-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/publish-service.js) — data and file uploads via `bee-js`
- **Feeds:** [`src/main/swarm/feed-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/feed-service.js) — feed creation and updates
- **Permissions:** [`src/main/swarm/swarm-permissions.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/swarm-permissions.js) — origin-scoped permission store
- **Origin normalization:** [`src/shared/origin-utils.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/shared/origin-utils.js) — dweb-aware origin extraction

[Swarmit](https://github.com/flotob/swarmit) — a decentralized message board — exercises the core publish/feed flows from a consuming dApp, using `swarm_requestAccess`, `swarm_publishData`, `swarm_createFeed`, `swarm_writeFeedEntry`, `swarm_readFeedEntry`, and `swarm_listFeeds`.

The low-level chunk tier (`swarm_publishChunk`, `swarm_readChunk`, `swarm_writeSingleOwnerChunk`, `swarm_readSingleOwnerChunk`), `swarm_getSigningIdentity`, the chunk-type validation contract, and the MUST-level per-origin rate limiting on permission-free reads are newly proposed in this draft from review feedback and are not yet implemented on either side. Reference implementations will follow in a subsequent Freedom Browser PR.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
