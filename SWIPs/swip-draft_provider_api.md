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

A standard JavaScript API (`window.swarm`) that enables web pages to request access to a user's Swarm node for publishing data, uploading files, managing mutable feeds, and reading/writing indexed feed entries — with user consent and origin-scoped permissions.

## Abstract

This SWIP defines a browser-injected JavaScript provider object (`window.swarm`) that allows web applications to interact with a user's local Swarm (Bee) node. The API follows the request/response pattern established by [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) for Ethereum providers, adapted for Swarm's publishing and feed primitives. It specifies nine RPC methods covering connection, capability discovery, data/file publishing, upload tracking, mutable feed management, and indexed feed entry read/write. The provider includes a permission model with explicit user consent, origin isolation, and upload size limits.

## Motivation

Today, publishing to Swarm from a web application requires either:

1. Direct HTTP calls to a locally running Bee node API (exposing the full API surface, including administrative endpoints, to any web page that can reach `localhost`), or
2. Server-side publishing infrastructure (defeating the purpose of decentralized hosting).

Neither approach is suitable for a user-sovereign web. Users need a way to grant web applications controlled, permissioned access to Swarm publishing capabilities — similar to how `window.ethereum` ([EIP-1193](https://eips.ethereum.org/EIPS/eip-1193)) lets web applications interact with a user's Ethereum wallet without exposing private keys.

Without a standard, each Swarm-enabled browser or extension will invent its own API. This fragments the ecosystem: dApp developers must write implementation-specific code, and users can't switch clients without breaking functionality. A standard `window.swarm` provider ensures interoperability across implementations.

### Design Goals

- **User consent first.** No operation executes without explicit permission.
- **Minimal surface.** Only publishing and feeds are exposed — not administrative, debug, or staking endpoints.
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
window.swarm.requestAccess()                     // swarm_requestAccess
window.swarm.getCapabilities()                    // swarm_getCapabilities
window.swarm.publishData({ data, contentType })   // swarm_publishData
window.swarm.publishFiles({ files })              // swarm_publishFiles
window.swarm.getUploadStatus({ tagUid })          // swarm_getUploadStatus
window.swarm.createFeed({ name })                 // swarm_createFeed
window.swarm.updateFeed({ feedId, reference })    // swarm_updateFeed
window.swarm.writeFeedEntry({ name, data })       // swarm_writeFeedEntry
window.swarm.readFeedEntry({ name, owner })       // swarm_readFeedEntry
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
| 4100 | Unauthorized | The origin has not been granted access. Call `swarm_requestAccess` first. |
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
| `payload_too_large` | `swarm_publishData`, `swarm_writeFeedEntry` | Payload exceeds the maximum allowed size. |
| `invalid_topic` | `swarm_readFeedEntry` | Topic is not a valid 64-character hex string. |
| `invalid_owner` | `swarm_readFeedEntry` | Owner is missing (when required) or not a valid address. |

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
    maxDataBytes: number,  // Maximum payload size for swarm_publishData
    maxFilesBytes: number, // Maximum total size for swarm_publishFiles
    maxFileCount: number   // Maximum number of files per swarm_publishFiles call
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

**Errors:** `4100` if not connected, `4900` if node unavailable, `-32602` if params invalid or payload exceeds `maxDataBytes`.

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
- Must be a non-empty string, maximum 256 characters.
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

**Errors:** `4100` if not connected, `4900` if node unavailable, `-32602` if params invalid, files exceed `maxFileCount`, or total size exceeds `maxFilesBytes`.

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

**Errors:** `4100` if not connected or feed access not granted, `4900` if node unavailable, `-32602` if name invalid.

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

**Errors:** `4100` if not connected or feed access not granted, `4900` if node unavailable, `-32602` if params invalid or feed doesn't exist.

**Behavior:**
- Writes are serialized per-topic (same mutex as `swarm_writeFeedEntry`). The returned `index` reflects the actual sequence index written.

---

#### `swarm_writeFeedEntry`

Write an arbitrary payload directly to a feed index as a Single Owner Chunk (SOC).

This enables the **journal pattern** — an append-only log where each entry is an independently-addressed chunk at an incrementing index. Unlike `swarm_updateFeed` (which stores a 32-byte content reference), `swarm_writeFeedEntry` stores the payload directly in the SOC. For payloads larger than the 4 KB SOC limit, the underlying implementation uploads the data separately and wraps the root chunk into the SOC transparently.

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

**Errors:** `4100` if not connected or feed access not granted, `4900` if node unavailable, `-32602` if params invalid, feed doesn't exist, index is occupied (`index_already_exists`), or payload exceeds SOC size limit (`payload_too_large`).

**Behavior:**

- The feed MUST already exist (created via `swarm_createFeed`).
- If `index` is omitted, the provider MUST resolve the next available index and write at that index. The resolved index is returned.
- If `index` is provided, the provider MUST check whether an entry already exists at that index. If it does, the write MUST be rejected with error data `{ reason: "index_already_exists" }`. This overwrite protection is the core safety guarantee of the journal pattern.
- The overwrite check and the write MUST be atomic — implementations MUST NOT allow concurrent writes to race between the check and the write to the same index. A per-topic serialization mechanism (e.g., a mutex) is RECOMMENDED.
- Sparse indices are valid. Writing to index 1000 without indices 0–999 existing is allowed. Applications that want sequential journal semantics SHOULD omit `index` and rely on auto-increment.

**Write serialization:** Implementations MUST serialize writes to the same feed topic. Two concurrent `swarm_writeFeedEntry` calls to the same feed MUST NOT produce index collisions. Writes to different feeds MAY execute in parallel.

---

#### `swarm_readFeedEntry`

Read a feed entry at a specific index, or read the latest entry. This is a read-only operation that does NOT require feed-level permission — only a basic connection (`swarm_requestAccess`).

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

**Errors:** `4100` if not connected, `4900` if node unreachable, `-32602` if params invalid.

Structured error reasons in `data.reason`:

| Reason | Meaning |
|---|---|
| `feed_empty` | The feed exists but has no entries written yet (returned for latest-entry reads). |
| `entry_not_found` | No entry exists at the requested index. |
| `feed_not_found` | Used `name` without `owner`, but the feed has not been created yet under this origin. |

**Behavior:**

- This method does NOT require feed-level permission — only connection permission (`swarm_requestAccess`). Feeds are public data on Swarm; the connection gate ensures the origin has been approved to use the user's Bee node.
- Pre-flight checks MUST be limited to verifying the Bee node's HTTP API is reachable. Mode checks (ultra-light), readiness checks, and stamp checks MUST NOT be applied — reads work regardless of node mode and do not consume stamps.
- Implementations MUST distinguish "not found" errors (HTTP 404/500 from the Bee API) from transient errors (network timeouts, internal failures). Transient errors MUST propagate as `-32603` (Internal Error), NOT be misclassified as `feed_empty` or `entry_not_found`.
- When reading the latest entry (`index` omitted), `nextIndex` indicates the next index available for writing. When reading a specific index, `nextIndex` is `null`.

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
2. **Publish:** Each `swarm_publishData`/`swarm_publishFiles` call MAY require per-operation user approval, unless the user has opted into auto-approve for this origin.
3. **Feed writes:** Feed write operations (`swarm_createFeed`, `swarm_updateFeed`, `swarm_writeFeedEntry`) require an additional feed-specific permission grant, separate from the connection permission.
4. **Feed reads:** `swarm_readFeedEntry` requires only connection permission — no feed grant is needed. Swarm feeds are public data; any connected origin can read any feed if it knows the owner address and topic.
5. **Disconnection:** The user can revoke access at any time. The provider MUST emit a `disconnect` event and reject subsequent requests with error code `4100`.

#### Auto-Approve (OPTIONAL)

Implementations MAY offer users the option to auto-approve publish and/or feed operations for trusted origins. When auto-approve is active:
- The implementation MUST still enforce all validation, size limits, and pre-flight checks.
- The implementation SHOULD provide a visual indicator that auto-approve is active.
- The user MUST be able to revoke auto-approve at any time.

---

### Limits

Implementations MUST enforce upload size and file count limits. The limits MUST be discoverable via `swarm_getCapabilities`. Recommended defaults:

| Limit | Recommended Default |
|---|---|
| `maxDataBytes` | 10 MB (10,485,760 bytes) |
| `maxFilesBytes` | 50 MB (52,428,800 bytes) |
| `maxFileCount` | 100 files |

Implementations MAY use different limits but MUST report them accurately in `swarm_getCapabilities`.

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

### Why do feed reads not require feed permission?

Swarm feeds are public data — anyone who knows the owner address and topic can read any feed entry on the network. The connection permission gate (`swarm_requestAccess`) ensures the origin has been approved to route requests through the user's Bee node. Adding a per-feed read ACL would be security theater: the same data is accessible via any other Bee node or gateway. Keeping reads lightweight (connection-only, no vault unlock, no stamps check) enables use cases like profile pages and cross-user activity views without unnecessary permission prompts.

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

This specification does not mandate a specific rate-limiting scheme, as appropriate limits depend on the node's capacity and the user's preferences.

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

- **`swarm_listFeeds`** — Enumerate existing feeds for the calling origin. This would allow dApps to discover feeds without maintaining their own registry of feed names.
- **`capabilitiesChanged` event** — Proactive notification when the provider's capabilities change (e.g., node goes offline, stamps exhausted). Currently dApps must poll `swarm_getCapabilities` to detect state changes.
- **`preferredIdentityMode` parameter for `swarm_createFeed`** — Allow dApps to express a preference for `app-scoped` or `bee-wallet` identity mode, rather than relying solely on user/implementation choice.
- **`encoding` parameter for `swarm_readFeedEntry`** — Allow callers to request a specific response encoding (e.g., `"utf8"`) to avoid manual base64 decoding for text payloads.

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
// After user revokes access, all methods reject with 4100
// (simulate disconnect via browser UI, then:)
try {
  await window.swarm.publishData({ data: 'test', contentType: 'text/plain' });
  assert.fail('Should have thrown');
} catch (err) {
  assert(err.code === 4100); // Unauthorized
}
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

### Feed Read Without Feed Grant

```javascript
// readFeedEntry requires only connection, not feed grant
// (assuming connected but no feed permission granted)
const entry = await window.swarm.readFeedEntry({
  topic: 'a1b2c3...64-char-hex-topic...',
  owner: '0xSomeAddress',
  index: 0,
});
// Should succeed — feed grant not required for reads
assert(typeof entry.data === 'string');
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
// specVersion is optional (SHOULD) in 1.0
if (caps.specVersion) assert(typeof caps.specVersion === 'string');
```

## Implementation

A reference implementation exists in [Freedom Browser](https://github.com/solardev-xyz/freedom-browser) (PR [#19](https://github.com/solardev-xyz/freedom-browser/pull/19)):

- **Provider injection:** [`src/main/webview-preload.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/webview-preload.js) — `window.swarm` object injected into webview page context
- **Main-process enforcement:** [`src/main/swarm/swarm-provider-ipc.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/swarm-provider-ipc.js) — method dispatch, validation, origin enforcement
- **Publishing:** [`src/main/swarm/publish-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/publish-service.js) — data and file uploads via `bee-js`
- **Feeds:** [`src/main/swarm/feed-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/feed-service.js) — feed creation and updates
- **Permissions:** [`src/main/swarm/swarm-permissions.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/main/swarm/swarm-permissions.js) — origin-scoped permission store
- **Origin normalization:** [`src/shared/origin-utils.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/src/shared/origin-utils.js) — dweb-aware origin extraction
- **Test page:** [`docs/swarm-provider-test/index.html`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing-updated/docs/swarm-provider-test/index.html) — interactive test harness

A reference dApp consuming this API exists in [Swarmit](https://github.com/flotob/swarmit), a decentralized message board that uses `swarm_requestAccess`, `swarm_publishData`, `swarm_createFeed`, and `swarm_updateFeed` for its full publishing pipeline.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
