---
swip: <to be assigned>
title: Fork Digest for Network Upgrade Coordination
author: mfw78 (@mfw78)
status: Draft
type: Standards Track
category: Networking
created: 2026-01-21
---

## Simple Summary

Introduce a fork digest mechanism that enables nodes to identify compatible peers during network upgrades via the handshake and Hive peer gossip.

## Abstract

A fork digest is a 4-byte identifier derived from the network configuration and current fork version. By including the fork digest in both the handshake protocol and Hive peer advertisements, nodes can efficiently filter incompatible peers before connection and avoid gossiping peers that recipients cannot use.

## Motivation

Swarm lacks a standardised mechanism for:

1. **Peer compatibility detection.** Nodes cannot determine protocol compatibility before establishing connections.
2. **Efficient peer gossip.** Hive broadcasts all known peers regardless of fork compatibility, wasting bandwidth.
3. **Graceful upgrades.** During network upgrades, incompatible nodes waste resources attempting failed connections.

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

Add `fork_digest` to the handshake message:

```protobuf
message Handshake {
    bytes overlay_address = 1;
    bytes underlay_address = 2;
    bytes signature = 3;
    bytes nonce = 4;
    uint64 network_id = 5;
    bool full_node = 6;
    bytes fork_digest = 7;  // 4 bytes
}
```

Nodes MUST reject connections where `peer.fork_digest != local.fork_digest`.

### Hive Protocol Integration

Include the fork digest in peer advertisements:

```protobuf
message BzzAddress {
    bytes underlay = 1;
    bytes signature = 2;
    bytes overlay = 3;
    bytes fork_digest = 4;  // 4 bytes
}
```

Gossip filtering rules:

- When receiving peers, ignore those with an incompatible fork digest.
- When sending peers, only advertise those matching the recipient's fork digest.

This prevents nodes from filling their address books with unreachable peers and reduces unnecessary connection attempts across the network.

### BzzAddress Signature

The `BzzAddress.signature` field authenticates the address fields using EIP-191 personal sign.

**Legacy (v0):**

```
data = "bee-handshake-" || underlay || overlay || network_id
signature = eip191_sign(data)
```

**Fork-aware (v1):**

```
data = underlay || overlay || network_id || fork_digest
signature = eip191_sign(data)
```

The `"bee-handshake-"` prefix is removed in v1 as EIP-191 personal sign already provides domain separation via `"\x19Ethereum Signed Message:\n<length>"`.

During migration, nodes MUST support verifying both signature formats:

1. If `fork_digest` is present, verify using the v1 scheme.
2. If `fork_digest` is absent, verify using the legacy v0 scheme.

Nodes SHOULD generate v1 signatures when creating new BzzAddress entries once fork digest support is enabled.

### Grace Period

During fork transitions (a one-hour window around activation), nodes MAY accept both pre-fork and post-fork digests to accommodate clock skew.

## Rationale

**4-byte digest.** A 4-byte value is compact yet sufficient (2^32 possible values) for network and fork disambiguation. This matches Ethereum's approach.

**Timestamp activation.** Swarm has no block consensus, making timestamps the natural coordination mechanism.

**Hive integration.** Without fork-aware gossip, nodes accumulate stale peer lists during upgrades, degrading connectivity.

**Signature versioning.** Including the fork digest in the signature binds the address to a specific fork, preventing replay of old addresses on new forks.

**Removing the "bee-handshake-" prefix.** The legacy prefix was redundant. EIP-191 personal sign already prefixes messages with `"\x19Ethereum Signed Message:\n<length>"`, providing sufficient domain separation. Removing it simplifies the protocol without reducing security.

## Backwards Compatibility

This proposal introduces a breaking change to the handshake and Hive protocols.

Migration:

1. **Release N.** Fork digest is optional. BzzAddress accepts both v0 and v1 signatures. Nodes generate v1 signatures.
2. **Release N+1.** Fork digest is required. v0 signatures are rejected.

Once Release N is deployed, fork digests will propagate through Hive gossip as nodes exchange peer information. By the time Release N+1 is deployed, the network should be predominantly fork-aware, easing the transition to mandatory fork digest.

Nodes that have not upgraded by Release N+1 will be unable to connect.

## Test Cases

| Scenario | Expected |
|----------|----------|
| Same network, same fork | Connection accepted |
| Different networks | Connection rejected |
| Pre/post fork during grace period | Connection accepted |
| Pre/post fork outside grace period | Connection rejected |
| Hive gossip with matching fork | Peer accepted |
| Hive gossip with mismatched fork | Peer ignored |
| BzzAddress with v0 signature, no fork_digest | Accepted (Release N) |
| BzzAddress with v1 signature, with fork_digest | Accepted |
| BzzAddress with v0 signature after Release N+1 | Rejected |

## Implementation

Reference: [vertex-swarm-forks](https://github.com/nxm-rs/vertex)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
