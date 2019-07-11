---
SWIP: <to be assigned>
title: Act (Access Control Module)
author: <a list of the author's or authors' name(s) and/or username(s), or name(s) and email(s), e.g. (use with the parentheses or triangular brackets): Viktor Trón,  @zelig viktor@ethswarm.org, Tim Bansemer (editorial) tim@inblock.io
discussions-to: https://swarmresear.ch/
status: Draft
type: Core Track,
category (*only required for Standard Track): Core
created: 2019
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
ACT
Access Control and Authentication

Access to encrypted content using a shared passphrase, a public-private key pair or an innovative scalable access control system (ACT) offering users sovereign control over private (encrypted) data as well as scalable user authentication for dapps.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->

*reference* to content in swarm is composed of a *content address* and an
optional *decryption key*.

*root access* is a type of access provided by a disclosed reference to
meta-information (oranized is a Swarm manifest), describing the process
of obtaining the reference to encrypted content. In the simplest case,
the content reference is explicitly included in meta-data in plaintext.

*granted access* is a type of selective access requiring root access and
*access credentials*; authorized private key or passphrase. Granted access
gives differentiated privileges accessing the content to multiple parties
sharing the same root access. This allows for updating the content without
changing access credentials. Granted access is implemented by an additional
layer of encryption on references.

*encrypted references* are defined as the symmetric encryption of the reference
(using swarm's flavour, see below). The symmetric key used in this layer is called
*access key*.

In case of granted access, the root access meta-information contains both the
encrypted reference and additional information for obtaining the access key
using access credentials. Once the access key is obtained, the reference to
content is obtained by decrypting the encrypted reference with the access key.

The accesss key can be obtained from a variety of sources, of which currently
three are defined.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

To protect users sovereignity additional actions need to be taken to ensure that their private data is only accessed by them or by the user authorized parties.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

## Symmetric and Asymmetric Derivation of Access Key

First, a *session key* is derived from the provided credentials. In case
of granting access to a single party, the session key is used directly as the
access key. In case of multiple parties, an additional mechanism is used for
turning the session key into the access key.

### Symmetric Derivation

The simplest credential is a *passhrase*. The session key is derived from it using
`scrypt` with parameters (such as *salt*) specified among the root access
meta-information. The output of `scrypt` is a 32-byte key that can be directly
used for Swarm encryption and decryption algorithms.

In typical use cases, the passphrase is distributed by off-band means, with
adequate security measures. Any user knowing the passphrase from which the key
was derived can access the content.

### Asymmetric Derivation

A more sophisticated credential is an *EC private key*, identical to those used
throughout Ethereum for accessing accounts. In order to obtain the
session key, an ECDH key agreement needs to be performed between a provided
*EC public key* (that of the content publisher) and the authorized key.

The session key is obtained from a *ECDH session key* (a *shared secret*) by
hashing with a *salt* value provided among the root access meta-data. This
session key can only be computed by the publisher and the grantee and noone
else (by ECDH assumption).

### Selective Access to Multiple Parties

In order to grant access to the same content by multiple parties, each of which
is identified by either type of credentials, the session key derived as
described above is not used directly as access key to decrypt the reference.
Instead, two keys, a *lookup key* and a *access key decryption key* are derived
from it by hashing it with two different constants (1 and 0, respectively).

The publisher needs to generate an access key and encrypt it with the
access key decryption keys for each grantee. Thereafter, they need to create a
lookup table mapping grantees' lookup keys to the ciphertext encrypted with the
correspoinding access key decryption key.

This lookup table is implemented as the *access control trie* (a.k.a. *ACT*) in
Swarm manifest format with paths corresponding to lookup keys and manifest
entries containing the ciphertext in metadata. The grantee knows whether to
use the ACT from the root access metadata.

ACT itself is an independent resource referenced by a URL in the
root access metadata.

Checking and looking up one's own access is logarithmic in the size of the ACT.
The size of the ACT merely provides an upper bound on the number of grantees,
but does not disclose any information beyond this upper bound about the set of
grantees to third parties. Even those included in the ACT can only learn that
they are grantees, but obtain no information about other grantees beyond an
upper bound on their number.

Granting access to an additional key requires extending the ACT by a single
entry, which is logarithmic in the size of the ACT. Withdrawing access
requires a change in the access key and therefore the rebuilding of the ACT.
Note that this requires that the publisher has the public keys of grantees.

## Access hierarchy

In the simplest case, the access key is a symmetric encryption/decryption
key. However, this is just a special case of the more flexible solution, where
the access key consists of a symmetric key and a key derivation path by which
it is derived from a root key. In this case, in addition to the encrypted
reference, a derivation path may also be included. Any party with an
access key whose derivation is a prefix to the derivation path of the
reference can decrypt the reference by deriving its key using their own key
and the rest of the derivation path of the reference.

This allows for a tree-like hierarchy of roles, possibly reflecting an
organizational structure. As long as role changes are "promotions", i.e.
result in increase of privileges, it is sufficient to change a single
ACT entry for each role change.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
This SWIP is introduced as a new feature and does not need to accomodate backward compatibilitiy to legacy implementations.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.

#Test Case for Asymmetric Keys
For example, and as a test case, consider the following two public keys, both derived according to BIP-39 from the following
seed phrase:
```
sunny science wrist intact lens file arch security kitten antique segment link
```
derivation path | public key | Ethereum address | private key
--------------- | ---------- | ---------------- | ---
`m/44'/60'/0'/0/0` | `02e6f8d5e28faaa899744972bb847b6eb805a160494690c9ee7197ae9f619181db` | `0xE8505879090351e00dd44807095352106eC7E56e` | `ec5541555f3bc6376788425e9d1a62f55a82901683fd7062c5eddcc373a73459`
`m/44'/60'/0'/0/1` | `0226f213613e843a413ad35b40f193910d26eb35f00154afcde9ded57479a6224a` | `0x7DEFd3C34972C6B6d19E53395a04B4fCd23A8617` | `70c7a73011aa56584a0009ab874794ee7e5652fd0c6911cd02f8b6267dd82d2d`

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.

### Asymmetric Keys

Throughout Ethereum, instead of *elliptic curve points*, their canonical hashes called *addresses* are used as public keys for
ECC, which is perfectly justified, as ECC is only used for digital signatures. For public key encryption, we actually need the
elliptic curve points, but Ethereum API's typically do not even allow us to access them.

In order to maintain compatibility with existing popular libraries, the same 33-byte compressed representation is used as in
Bitcoin. When textual representation are required, hexadecimal representation (without the `0x` prefix) is used. Private keys
are similarly represented in hexadecimal, as 256 bit (32 byte, 64 hexadecimal digit) indices.



### Elliptic Curve Diffie-Hellman Shared Secret

While it might seem somewhat inconsistent, the ECDH session key, which is also an EC point, is represented differently from
public keys, because of restrictions of certain platforms (devices and libraries, `go-ethereum/crypto` being one of them).
Instead of using the compressed point format, only the *x* coordinate of the point is used, which is bytes 1..32 of both the
compressed and the uncompressed representation of EC points.

In particular, the *shared secret* (a.k.a. ECDH session key) for the above to keys is `a85586744a1ddd56a7ed9f33fa24f40dd745b3a941be296a0d60e329dbdb896d`.

### Symmetric Keys

Just like for symmetric content encryption in Swarm, 256-bit keys are used, represented as 64-digit hexadecimal numbers.

Symmetric keys can be derived from the following sources:

Source | Derivation
--- | ---
Passphrase *pw* | scrypt(*pw*, *salt*, *scrypt_params*)
ECDH session key *s* | SHA3(*s* \| *salt*)
root key *r* | k(*r*, *path*) = empty(*path*) ? *r* : k(SHA3(*r* \| *path*\[0\]), *path*\[1:\])

### Symmetrically Encrypted Data

Symmetric encryption is done using the same algorithm that encrypts chunks in Swarm: SHA3² used in CTR mode, except that there
is no padding to 4 kilobytes. Ciphertexts as well as keys are serialised using hexadecimal representation when included in manifests or URLs.
 Note that the ciphertext has the same length as the concatenation of 8 bytes and the plaintext, if the latter is represented in the same way. Thus, the length of the
plaintext can be inferred from the ciphertext. Therefore, the first 8 bytes can be used as a quick check whether or not the key used for
decryption is the correct one.

## Access Protocols

The above described algorithms using private key credentials have been designed
to be compatible with existing key management software and hardware solutions,
such as popular hardware wallets already used for accessing Ethereum assets.

Deriving both the access key decryption key and the lookup key from the same
session key allows us to request the credentials only once.

### HTTP

Whem a HTTP request is made that resolves into a selective access reference, it is first checked whether it comes with a public ECDH key and whether the client has an unlocked private key. If this is the case, access using the private key is attempted.
Otherwise, if the selective access reference has all the metadata for passphrase-based resolution, basic HTTP authentication as defined in [RFC7614](https://tools.ietf.org/html/rfc7617) is used to obtain the passphrase, consisting of both the username and
the password.


## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).





