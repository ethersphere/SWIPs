---
SWIP: 88
title: PQACT
author: Sig
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280 (Swarm Discord '#swips')
status: Draft
type: Standards Track
category: Core
created: 2026-10-16
replaces: ACT
---

*IMPORTANT NOTE: This SWIP is proactive to future threats. Current ACT security levels are unaffected.*

# PQACT

*Lattice based protection from the rebel alliance.*

## Simple Summary

ACT derives each grantee's session secret from secp256k1 Diffie-Hellman. A quantum computer breaks that, and ACT tries sit on a public network. PQACT hashes an ML-KEM-1024 shared secret into the session secret at the one place it is computed. Nothing else changes. This is the hybrid shape of Signal's PQXDH. ACT v2 supersedes v1; re-encryption of pre-existing data will be required.

## Motivation

Harvest now, decrypt later. Anyone can archive ACT tries today. With a quantum computer they recover a grantee's private key from its public key, recompute the session secret, and unwrap the access key. Rotation after the fact does not help. The key exchange must be post-quantum secure before publication.

## Specification

Every grantee has an ML-KEM-1024 keypair as well as its secp256k1 key. It publishes the encapsulation key $ek$ in a Single Owner Chunk owned by its secp256k1 key, identifier $\mathrm{keccak256}(\text{"swarm/act/kem"})$.

ACT v1 sets $s = \mathrm{ECDH}(\text{grantee}, \text{publisher}).x$, then $lookupKey = \mathrm{keccak256}(s \Vert \mathtt{0x00})$ and $akdk = \mathrm{keccak256}(s \Vert \mathtt{0x01})$.

PQACT changes only $s$:

$$
(ct, ss) = \mathrm{ML\text{-}KEM.Encaps}(ek), \qquad
s = \mathrm{keccak256}\big(\mathrm{ECDH}(\text{grantee}, \text{publisher}).x \,\Vert\, ss\big).
$$

The grantee decapsulates $ct$ to get $ss$ and computes the same $s$.

The trie value, previously the 32-byte wrapped access key, becomes a reference to a chunk holding $ct \Vert \mathrm{Enc}_{akdk}(accessKey)$, 1600 bytes. The grantee list stores $ek$ after each secp256k1 key. Lookup, trie, history, revocation, headers and endpoints are as in v1.

## Rationale

Like PQXDH, the DH output and the KEM shared secret go into one hash, so the secret holds if either primitive holds. The SOC signature plays the part of Signal's identity-key signature on the KEM prekey. ML-KEM already binds $ek$ into $ss$, so no further associated data is needed. Forward secrecy is out of scope: this is data at rest.

## Backwards Compatibility

None. Greenfield redeployment; v1 content must be re-encrypted and re-granted.

## Test Cases

1. Grant, then the grantee decrypts the reference.
2. Flip one byte of $ct$; decryption fails.
3. Known-answer vector for fixed keys and ML-KEM seed.

## Implementation

Bee `pkg/accesscontrol/session.go`: hash $ss$ into the secret. `access.go`: write and read the ciphertext chunk. `grantee.go`: longer entries.

ML-KEM-1024 libraries:

- Go: `crypto/mlkem`, standard library since 1.24.
- JavaScript: `node:crypto` in Node.js 24+ (`ml-kem-1024` keys, `encapsulate`, `decapsulate`). Browsers have no Web Crypto ML-KEM yet; use `@noble/post-quantum` (audited, pure JS).
- Rust: no standard library; use `libcrux-ml-kem` (formally verified, used by Signal's libsignal).

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
