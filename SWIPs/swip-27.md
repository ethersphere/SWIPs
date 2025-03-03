---
swip: 27
title: Wire-Level Protocol Standardisation with Strongly Typed Messages
status: Draft
type: Standards Track
category: Networking
author: mfw78 (@mfw78)
created: 2025-03-03
requires: 26
---

## Simple Summary
This SWIP proposes standardised, strongly typed message formats for Swarm network protocols to enhance security, interoperability, and maintainability.

## Abstract
This SWIP defines a comprehensive approach to standardising Swarm's wire-level protocols using strongly typed messages. It addresses current inconsistencies in protocol message formats, enhances type safety, and introduces a consistent pattern for stateful protocols. Building upon SWIP-26's chunk type framework, this proposal enforces the principle that each stream should write and read only one specific message type, creating clearer protocol boundaries and reducing implementation errors.

## Motivation
Swarm's current protocol implementations suffer from several wire-level issues:

1. **Weak Type Safety**: Generic byte arrays are used for complex data structures, increasing security risks.

2. **Message Type Confusion**: Streams often handle multiple message types, leading to parsing errors and state confusion.

3. **Inconsistent Conversation Patterns**: Stateful protocols lack clear message flow structures.

4. **Duplicated Logic**: Common types are represented differently across protocols.

This SWIP addresses these issues by standardising message formats and enforcing single-message-type streams.

## Specification

### Core Principles

1. **One Message Type Per Stream**: Each writing or reading stream should handle exactly one message type.

2. **Strongly Typed Messages**: All messages must use explicit types rather than generic byte arrays.

3. **Common Type Definitions**: Shared structures like addresses and chunks must use consistent definitions.

4. **Explicit Protocol State**: Stateful protocols must use wrapper messages with explicit type enums.

### Message Structure

#### 1. Stateful Protocols

Stateful protocols shall use wrapper messages with type enums and oneof fields:

```
message ProtocolMessage {
    MessageType type = 1;

    oneof message {
        MessageType1 message_type1 = 2;
        MessageType2 message_type2 = 3;
    }
}
```

#### 2. Stateless Protocols

Simple request/response protocols shall use direct message types:

```
// Stream 1: Client writes Request, Server reads Request
message Request {
    field1_type field1 = 1;
}

// Stream 2: Server writes Response, Client reads Response
message Response {
    field2_type field2 = 1;
}
```

### Protocol Classifications

1. **Stateful Protocols**:
   - Handshake protocol
   - PullSync protocol (including Cursors subprotocol)
   - Swap protocol
   - PseudoSettle protocol

2. **Stateless Protocols**:
   - Hive protocol
   - Headers protocol
   - PingPong protocol
   - Pricing protocol
   - PushSync protocol
   - Retrieval protocol
   - Status protocol

### Protocol Versioning

This SWIP introduces new major versions for all protocols:

1. All protocols will advertise new libp2p protocol versions (e.g., upgrading from "/swarm/hive/1.0.0/proto" to "/swarm/hive/2.0.0/proto")
2. The new protocol versions will use the standardized message formats outlined in this SWIP
3. Node implementations must support both old and new protocol versions during the transition period

### Reference Implementation

A complete set of Protocol Buffer definitions implementing this proposal is available in the [assets directory](./assets/swip-27/). This includes a comprehensive [overview of improvements](./assets/swip-27/README.md) compared to the previous protocol definitions, as well as detailed protocol definitions for all Swarm network protocols.

## Rationale

The proposed approach:

1. **Reduces Complexity**: By limiting each stream to one message type, we simplify parsing and state management.

2. **Improves Security**: Strong typing and clear message boundaries reduce the attack surface.

3. **Enhances Maintainability**: Standardised patterns make code more maintainable and easier to audit.

4. **Clarifies Protocols**: Explicit message types make protocol documentation and implementation clearer.

5. **Facilitates Testing**: Well-defined message boundaries make unit testing more effective.

The single-message-type principle is particularly important because it:
- Prevents type confusion attacks
- Makes protocol state transitions explicit
- Reduces parsing errors
- Creates cleaner API boundaries

## Backwards Compatibility

This proposal introduces significant changes to message formats but provides a structured migration path:

1. **Dual Protocol Support**: All nodes must support both old and new protocol versions during the transition period, with the underlying node logic remaining unchanged.

2. **Version Preference**: Nodes should prefer using the new protocol versions when communicating with peers that support them.

3. **Advertised Capabilities**: New protocol versions will be advertised through libp2p protocol version strings.

4. **Phased Adoption**: This approach allows for progressive network upgrades without immediate disruption.

5. **Hard Deadline**: At a predetermined block height or timestamp, support for old protocol versions will be discontinued through a mandatory handshake protocol version upgrade.

## Implementation

Implementation will proceed in phases:

1. **Protocol Definition**: Define the new protocol message formats using Protocol Buffers.

2. **Dual Support Implementation**: Update node software to support both old and new protocol versions simultaneously, with no changes to the underlying business logic.

3. **Version Negotiation**: Enhance connection handling to detect and prefer new protocol versions when available.

4. **Network Monitoring**: Track adoption rates of the new protocol versions across the network.

5. **Hard Cutoff**: At a predetermined network milestone (e.g., a specific block height), enforce the exclusive use of new protocol versions by upgrading the handshake protocol version, requiring all nodes to support the new message formats.

6. **Legacy Code Removal**: After the hard cutoff date, remove support for legacy protocol versions, simplifying the codebase.

This approach provides a balance between network stability and progressive improvement, allowing node operators to upgrade at their convenience until the hard deadline.

## Test Cases

Testing should focus on:

1. **Message Boundaries**: Verify each stream handles exactly one message type in the new protocol versions.

2. **Type Safety**: Confirm no generic byte arrays for complex structures in the new protocol versions.

3. **Protocol State**: Test correct state transitions in stateful protocols.

4. **Dual Version Support**: Verify nodes correctly handle both old and new protocol versions during the transition period.

5. **Version Preference**: Confirm nodes prefer new protocol versions when both peers support them.

6. **Handshake Enforcement**: Test that nodes properly enforce the new protocol versions after the hard cutoff date.

## Security Considerations

This standardisation significantly improves security by:

1. **Preventing Type Confusion**: Strong typing reduces misinterpretation of message data.

2. **Limiting Attack Surface**: Clear message boundaries reduce opportunities for exploitation.

3. **Enabling Static Analysis**: Well-defined types allow better static analysis tools.

4. **Simplifying Validation**: Structured messages enable more thorough validation.

5. **Clarifying Protocol States**: Explicit message types make unexpected state transitions easier to detect.

6. **Coordinated Transition**: The phased migration approach reduces security risks associated with network fragmentation.

## Copyright Waiver

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
