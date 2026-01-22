---
swip: <to be assigned>
title: Fork Digest and BzzAddress Encoding
author: mfw78 (@mfw78)
status: Draft
type: Standards Track
category: Networking
created: 2026-01-21
---

## Simple Summary

Introduce a fork digest mechanism that enables nodes to identify compatible peers during network upgrades via the handshake and Hive peer gossip. Additionally, clean up the underlay encoding by using proper protobuf repeated fields instead of custom serialization.

## Abstract

A fork digest is a 4-byte identifier derived from the network configuration and current fork version. By including the fork digest in both the handshake protocol and Hive peer advertisements, nodes can efficiently filter incompatible peers before connection and avoid gossiping peers that recipients cannot use.

This proposal also replaces the custom underlay serialization format (magic `0x99` prefix with varint-length encoding) with idiomatic protobuf `repeated` fields, simplifying implementations and improving interoperability.

## Motivation

Swarm lacks a standardised mechanism for:

1. **Peer compatibility detection.** Nodes cannot determine protocol compatibility before establishing connections.
2. **Efficient peer gossip.** Hive broadcasts all known peers regardless of fork compatibility, wasting bandwidth.
3. **Graceful upgrades.** During network upgrades, incompatible nodes waste resources attempting failed connections.
4. **Clean underlay encoding.** The current protocol uses a custom serialization format for multiple underlay addresses: a magic `0x99` prefix byte followed by varint-length-prefixed multiaddr bytes. This deviates from idiomatic protobuf usage, complicates implementations, and conflates wire encoding with application logic.

## Specification

### Fork Digest Calculation

```
fork_digest = keccak256(genesis_hash || current_fork_version)[0:4]
```

Where:

- `genesis_hash`: 32-byte hash uniquely identifying the network
- `current_fork_version`: 4-byte version for the active fork

#### Genesis Hash

The genesis hash must uniquely identify a Swarm network. An illustrative example:

```
genesis_hash = keccak256(network_id || genesis_timestamp || ...)
```

The exact composition of the genesis hash requires further discussion. Candidates for inclusion:

- `network_id` (required)
- `genesis_timestamp`
- Contract addresses (postage stamp, staking, redistribution)
- Other network-specific parameters

Feedback is solicited on what should constitute the genesis hash for mainnet and testnet.

### Fork Versions

| Fork | Version | Activation |
|------|---------|------------|
| Homestead | `0x00000000` | Genesis |

### Fork Condition

Forks use timestamp-based activation:

```
fork_active = current_timestamp >= activation_timestamp
```

### Handshake Integration

The handshake protocol is updated with fork digest and proper underlay encoding:

```protobuf
syntax = "proto3";

package handshake;

message Syn {
    bytes observed_underlay = 1;
}

message Ack {
    BzzAddress address = 1;
    uint64 network_id = 2;
    bool full_node = 3;
    bytes nonce = 4;
    string welcome_message = 99;
}

message SynAck {
    Syn syn = 1;
    Ack ack = 2;
}

message BzzAddress {
    repeated bytes underlays = 1;  // Multiple multiaddr bytes (was: single bytes with custom encoding)
    bytes signature = 2;
    bytes overlay = 3;
    bytes fork_digest = 4;         // 4 bytes
}
```

Key changes:

1. **`underlays` becomes `repeated bytes`** - Each multiaddr is a separate element. No custom serialization (no `0x99` prefix, no varint length encoding). Protobuf handles the wire format.
2. **`fork_digest` is added** - 4-byte fork identifier.

Nodes MUST reject connections where `peer.fork_digest != local.fork_digest`.

### Hive Protocol Integration

The Hive protocol uses the same `BzzAddress` message defined above. Gossip filtering rules:

- When receiving peers, ignore those with an incompatible fork digest.
- When sending peers, only advertise those matching the recipient's fork digest.

This prevents nodes from filling their address books with unreachable peers and reduces unnecessary connection attempts across the network.

### BzzAddress Signature

The `BzzAddress.signature` field authenticates the address fields using EIP-191 personal sign.

**Legacy (v0):**

```
serialized_underlay = custom_serialize(underlays)  // 0x99 prefix + varint lengths, or raw for single
data = "bee-handshake-" || serialized_underlay || overlay || network_id
signature = eip191_sign(data)
```

**Fork-aware (v1):**

```
underlays_concat = underlays[0].bytes || underlays[1].bytes || ... || underlays[n].bytes
data = underlays_concat || overlay || network_id || fork_digest
signature = eip191_sign(data)
```

Key changes in v1:

1. **Simple concatenation for underlays.** The signature is computed over the concatenation of all underlay multiaddr bytes in order. No length prefixes, no magic bytes, no padding. The multiaddr self-describing format and the fixed-length `overlay` (32 bytes) provide implicit framing.

2. **No "bee-handshake-" prefix.** EIP-191 personal sign already provides domain separation via `"\x19Ethereum Signed Message:\n<length>"`. The legacy prefix was redundant.

3. **Fork digest included.** Binds the signature to a specific fork, preventing replay on incompatible networks.

During migration, nodes MUST support verifying both signature formats:

1. If `fork_digest` is present, verify using the v1 scheme.
2. If `fork_digest` is absent, verify using the legacy v0 scheme (with custom underlay deserialization).

Nodes SHOULD generate v1 signatures when creating new BzzAddress entries once fork digest support is enabled.

### Grace Period

During fork transitions (a one-hour window around activation), nodes MAY accept both pre-fork and post-fork digests to accommodate clock skew.

## Rationale

**4-byte digest.** A 4-byte value is compact yet sufficient (2^32 possible values) for network and fork disambiguation. This matches Ethereum's approach.

**Timestamp activation.** Swarm has no block consensus, making timestamps the natural coordination mechanism.

**Hive integration.** Without fork-aware gossip, nodes accumulate stale peer lists during upgrades, degrading connectivity.

**Signature versioning.** Including the fork digest in the signature binds the address to a specific fork, preventing replay of old addresses on new forks.

**Removing the "bee-handshake-" prefix.** The legacy prefix was redundant. EIP-191 personal sign already prefixes messages with `"\x19Ethereum Signed Message:\n<length>"`, providing sufficient domain separation. Removing it simplifies the protocol without reducing security.

**Repeated bytes for underlays.** The legacy custom encoding (magic `0x99` prefix + varint length prefixes) was a workaround for backward compatibility with single-underlay nodes. This conflates wire encoding with application logic and complicates implementations. Using protobuf's native `repeated bytes` field:

- Leverages protobuf's built-in length-prefixed encoding for wire format
- Simplifies parsing - no custom deserialization logic needed
- Improves interoperability - standard protobuf tooling works correctly
- Separates concerns - wire encoding is handled by protobuf, signature construction is application logic

**Concatenation for signature.** The signature is over the simple concatenation of multiaddr bytes. No additional framing is required because:

- Multiaddrs are self-describing (each component includes its protocol code and length)
- The overlay address is fixed-length (32 bytes)
- EIP-191 includes the total message length, providing overall framing
- The fork digest is fixed-length (4 bytes)

This provides sufficient domain separation without introducing complexity.

## Backwards Compatibility

This proposal introduces breaking changes to the handshake and Hive protocols:

1. **Fork digest field** - New required field in BzzAddress
2. **Underlay encoding** - Changes from `bytes underlay` (custom encoding) to `repeated bytes underlays` (native protobuf)
3. **Signature scheme** - Changes from v0 (with prefix and custom underlay) to v1 (no prefix, concatenated underlays, fork digest)

Migration:

1. **Release N.** Fork digest is optional. BzzAddress accepts both:
   - Legacy format: `bytes underlay` with custom encoding, v0 signature
   - New format: `repeated bytes underlays`, v1 signature with fork digest
   Nodes generate the new format but verify both.

2. **Release N+1.** Only the new format is accepted. Legacy format is rejected.

Once Release N is deployed, the new format will propagate through Hive gossip as nodes exchange peer information. By the time Release N+1 is deployed, the network should be predominantly using the new format.

Nodes that have not upgraded by Release N+1 will be unable to connect.

## Test Cases

### Fork Digest

| Scenario | Expected |
|----------|----------|
| Same network, same fork | Connection accepted |
| Different networks | Connection rejected |
| Pre/post fork during grace period | Connection accepted |
| Pre/post fork outside grace period | Connection rejected |
| Hive gossip with matching fork | Peer accepted |
| Hive gossip with mismatched fork | Peer ignored |

### Signature Verification

| Scenario | Expected |
|----------|----------|
| v0 signature (legacy underlay encoding, no fork_digest) | Accepted (Release N only) |
| v1 signature (repeated underlays, with fork_digest) | Accepted |
| v0 signature after Release N+1 | Rejected |
| v1 signature with wrong fork_digest | Rejected |
| v1 signature with underlays in different order | Rejected (signature mismatch) |

### Underlay Encoding

| Scenario | Expected |
|----------|----------|
| Single underlay in repeated field | Valid |
| Multiple underlays in repeated field | Valid |
| Empty underlays (zero elements) | Rejected |
| Legacy 0x99-prefixed encoding in bytes field | Accepted (Release N only) |
| Raw multiaddr in bytes field (single underlay) | Accepted (Release N only) |

## Implementation

Reference: [vertex-swarm-forks](https://github.com/nxm-rs/vertex)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
