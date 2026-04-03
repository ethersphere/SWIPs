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

A standard JavaScript API (`window.swarm`) that enables web pages to request access to a user's Swarm node for publishing data, uploading files, and managing mutable feeds — with user consent and origin-scoped permissions.

## Abstract

This SWIP defines a browser-injected JavaScript provider object (`window.swarm`) that allows web applications to interact with a user's local Swarm (Bee) node. The API follows the request/response pattern established by [EIP-1193](https://eips.ethereum.org/EIPS/eip-1193) for Ethereum providers, adapted for Swarm's publishing and feed primitives. It specifies seven RPC methods covering connection, capability discovery, data/file publishing, upload tracking, and mutable feed management. The provider includes a permission model with explicit user consent, origin isolation, and upload size limits.

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

| Property | Type | Description |
|---|---|---|
| `isFreedomBrowser` | `boolean` | **(OPTIONAL, implementation-specific)** Implementations MAY include a boolean property identifying themselves. This is NOT part of the standard interface and MUST NOT be relied upon for feature detection. Use `swarm_getCapabilities` instead. |

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

Implementations SHOULD expose convenience wrappers for each standard method:

```javascript
window.swarm.requestAccess()                     // swarm_requestAccess
window.swarm.getCapabilities()                    // swarm_getCapabilities
window.swarm.publishData({ data, contentType })   // swarm_publishData
window.swarm.publishFiles({ files })              // swarm_publishFiles
window.swarm.getUploadStatus({ tagUid })          // swarm_getUploadStatus
window.swarm.createFeed({ name })                 // swarm_createFeed
window.swarm.updateFeed({ feedId, reference })    // swarm_updateFeed
```

These MUST be equivalent to calling `window.swarm.request()` with the corresponding method name.

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
- Calling `swarm_requestAccess` when already connected SHOULD return the existing connection state without re-prompting.
- After a successful `swarm_requestAccess`, the provider MUST emit a `connect` event.

---

#### `swarm_getCapabilities`

Returns the current capabilities of the provider for this origin. Does NOT require prior access — can be called before `swarm_requestAccess` for feature detection.

**Params:** None.

**Result:**

```javascript
{
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

---

#### `swarm_publishData`

Upload a single blob of data to Swarm.

**Params:**

| Field | Type | Required | Description |
|---|---|---|---|
| `data` | `string \| Uint8Array \| ArrayBuffer` | Yes | The content to upload. |
| `contentType` | `string` | Yes | MIME type (e.g. `"text/html"`, `"application/json"`). |
| `name` | `string` | No | Display name for the upload. |

**Result:**

```javascript
{
  reference: string,   // 64-character hex Swarm reference
  bzzUrl: string       // "bzz://<reference>"
}
```

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
  bzzUrl: string     // "bzz://<manifestReference>" (stable feed URL)
}
```

**Errors:** `4100` if not connected or feed access not granted, `4900` if node unavailable, `-32602` if params invalid or feed doesn't exist.

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
3. **Feeds:** Feed operations (`swarm_createFeed`, `swarm_updateFeed`) require an additional feed-specific permission grant, separate from the connection permission.
4. **Disconnection:** The user can revoke access at any time. The provider MUST emit a `disconnect` event and reject subsequent requests with error code `4100`.

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

## Backwards Compatibility

This SWIP introduces a new API surface. There are no backwards compatibility concerns as no prior standard for `window.swarm` exists. Implementations that predate this specification SHOULD migrate to conform to these interfaces.

Web pages that do not use `window.swarm` are unaffected. The provider MUST NOT modify any existing browser APIs or globals.

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

## Implementation

A reference implementation exists in [Freedom Browser](https://github.com/solardev-xyz/freedom-browser) (PR [#19](https://github.com/solardev-xyz/freedom-browser/pull/19)):

- **Provider injection:** [`src/main/webview-preload.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/main/webview-preload.js) — `window.swarm` object injected into webview page context
- **Main-process enforcement:** [`src/main/swarm/swarm-provider-ipc.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/main/swarm/swarm-provider-ipc.js) — method dispatch, validation, origin enforcement
- **Publishing:** [`src/main/swarm/publish-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/main/swarm/publish-service.js) — data and file uploads via `bee-js`
- **Feeds:** [`src/main/swarm/feed-service.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/main/swarm/feed-service.js) — feed creation and updates
- **Permissions:** [`src/main/swarm/swarm-permissions.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/main/swarm/swarm-permissions.js) — origin-scoped permission store
- **Origin normalization:** [`src/shared/origin-utils.js`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/src/shared/origin-utils.js) — dweb-aware origin extraction
- **Test page:** [`docs/swarm-provider-test/index.html`](https://github.com/solardev-xyz/freedom-browser/blob/feature/swarm-publishing/docs/swarm-provider-test/index.html) — interactive test harness

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
