---
SWIP: 8
title: Postage Stamps for Swarm Messages
author: Daniel A. Nagy <daniel@ethswarm.org> (@nagydani)
discussions-to: https://swarmresear.ch/t/postage-ex-proof-of-burn/
status: Draft
type: Standards Track
category: Core
created: 2019-07-12
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

# Postage Stamps for Swarm Messages

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Short witnesses of on-chain payment (akin to postage stamps affixed to snail mail) to be attached to uploaded Swarm chunks and 
SSP messages as a spam protection measure and to prioritize delivery and storage when network capacity becomes scarce.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->

A small piece of data cryptographically tied to a Swarm chunk or PSS message carrying the following information can act as 
postage payment for spam protection, message delivery and syncing incentivization:

 * The swarm hash of the payload
 * Amount paid on-chain to an appropriate smart contract.
 * Timestamp of beginning of validity period
 * Timestamp of the end of validity period (expiration time)
 * Cryptographic proof of the above.

The same payload can have multiple (valid) postage stamps attached to it. The “value density” of a postage stamp is measured in 
wei/second/chunk. By definition, it is zero, if the chunk has no currently valid stamps attached to it. The value densities 
conferred to the chunk by valid postage stamps simply add up. The value density of a stamp is calculated as the value of the 
payment divided by the number of chunks stamped from the same payment and further divided by the length of the validity period of 
the stamp. If the same payload is encountered with a different set of stamps, these sets are merged (union).

Even though a Swarm node cannot directly evaluate the value density, as it does not have access to postage stamps corresponding to
payloads that do not pass through it, it can still compare the relative value densities of different payloads that it does encounter in order to prioritize them in case of resource shortage.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

Without postage, the incentivization of message routing (be it syncing or PSS delivery) is very problematic, because if the 
sender is required to pay for it, they might choose not to forward it, unless it is their own message, whereas if the recipient is 
required to pay for it, then useless messages (spam) can be generated without much effort for which recipients will also pay.

Taking inspiration from international mail delivery, the entire delivery path (as well as storage) can be pre-paid by the 
originator of the payload, attaching a proof of payment. If the storer or final recipient of a message has a chance of obtaining 
part of the pre-payment and an ability to accurately estimate their expected payout, which is smaller than what the originator 
paid for postage then they are willing to pay the node that delivers the message, without exposing themselves to attack by 
cheaply generated spam. This, in turn, incentivizes all nodes along the delivery route to pay the previous one, as they can count on payment from the next one.

Even before the reward for storing nodes is implemented and message forwarding is done on an altruistic best-effort basis, postage stamps provide an adequate spam protection mechanism and a way for network nodes to select messages to forward and store, if the available resources do not allow for forwarding and/or storing all messages.

The necessity of stamping multiple payloads from the same payment transaction comes from the high cost of on-chain transactions. 
Doing an on-chain payment for each chunk or message is prohibitively expensive.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations. -->

Nodes participating in the same postage system are configured to reference the same contract on the same blockchain. This contract
*must* have an accessor call with the following ABI signature:
```json
{
  "name": "postage",
  "type": "function",
  "inputs": [
    {
      "name": "payloadHash",
      "type": "uint256"
    },
    {
      "name": "postagePaid",
      "type": "uint256"
    },
    {
      "name": "beginValidity",
      "type": "uint256"
    },
    {
      "name": "endValidity",
      "type": "uint256"
    },
    {
      "name": "witness",
      "type": "bytes"
    }
  ],
  "outputs": [
    {
      "name": "",
      "type": "bool"
    }
  ]
}
```

This accessor method returns `true` iff the proof embodied by `witness` checks out for all other arguments within the claimed 
validity period, i.e. when `block.timestamp` (the output of `TIMESTAMP` EVM opcode) is between `beginValidity` (inclusive) and 
`endValidity`, (exclusive). Outside of the validity period, the return value is undefined.

The binary serialization of the postage stamp consists of a single 5-element array containing the arguments in the same order, all [RLP-encoded](https://github.com/ethereum/wiki/wiki/RLP). 

### Witness Types

There can be different implementations of postage stamps that differ in the structure and semantics of the `witness` field. To allow for new cryptographic mechanism to be used as they are developed, the first byte of `witness` indicates the `type` of the witness used. These numbers are assigned sequentially in the SWIP process. Witness types `0` and `1` are specified in this SWIP, further types are specified in later SWIPs referencing and extending this one.

Witness type `0` refers to **ECDSA** witness, which is an ECDSA signature on the 128 bytes resulting from the concatenation of `payloadHash`, `postagePaid`, `beginValidity` and `endValidity`. The binary encoding of the ECDSA signature is 65 bytes resulting from the concatenation of the `r` (32 bytes), `s` (32 bytes) and `v` (1 byte) parameters of the signature, in this order. The signature is calculated on the SECP256K1 elliptic curve, just like the signatures of Ethereum transactions. This is the bare minimum that postage stamp contracts and clients must implement.

Witness type `1` refers to **RSA** witness, which is an RSA signature on the same 128 bytes as above. The binary encoding of the RSA signature is of variable length, and is an RLP encoded array of the RSA signature `s` (as defined in [PKCS #1](https://tools.ietf.org/html/rfc8017)) and the RSA public key parameters `n` (RSA modulus) and `e` (public exponent).

### Contract Uprgades

In order to facilitate the uprage of the contract either in case of a discovered vulnerability or some feature extension (such as adding new witness types), it is recommended that the part holding the funds with the database of payments and the part that verifies witnesses are in separate contracts so that a backwards-compatible upgrade can be performed with minimal disruption.

In order to avoid centralized control, it is also recommended that it is the witness-verifying contract that is referenced in client configuration so that client operators can independently decide for themselves when and whether to switch to a new contract, as they become available.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->
The ECDSA witness is the simplest and cheapest solution both in terms of gas consumed by the stamp verification contract and in terms of computational resources used off chain. Also, it does not rely on cryptographic assumptions in addition to those on which Ethereum critically relies, therefore as long as Ethereum is considered cryptographically secure, no advance in cryptorgraphy can render this witness type insecure. This is the justification for this witness type to be the only mandatory witness type to be implemented.

The RSA witness is specified so that blind stamping services can be implemented in a simple fashion, in order to mitigate the privacy issues arising from the ability to link chunks signed with the same private key. Even though blind ECDSA signatures also exist, their protocol requires more rounds of communication, making the implementation of such a service more complex, more error-prone and less performant. The specification of such blind stamping services is outside of the scope of this SWIP, requiring a separate one.

The inclusion of the entire public key in each RSA witness rather than storing the public key in contract state and just referencing it from the witness is justified by reducing the gas costs of interactions with the contract as well as future-proofing the design in case contract state rent is introduced in Ethereum. These considerations are more important than the brevity of postage stamps, marginally reducing the bandwith costs of uploading and forwarding stamped content.

Note that cryptographic advances can render RSA witnesses insecure without rendering Ethereum insecure, therefore RSA witnesses can be phased out in future versions of the protocol, if the security of RSA signatures gets compromised. Note, furthermore, that such blind signing services are not entirely trustless, through the damage they can incur is bounded. Trustless blind stamping services based on ZK proofs are not feasible at this stage, as the current algorithms are not sufficiently performant for the purpose, but given the rapid advances in the field, the development of suitable algorithms can be expected in the future, in which case a corresponding witness type will have to be specified in a separate SWIP.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
