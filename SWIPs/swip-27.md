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

This proposal requires a major version increment for all affected protocols, following the existing Swarm versioning methodology:

1. Protocols already include version information (e.g., "1.0.0")
2. Major version changes indicate backward-incompatible modifications
3. Version negotiation occurs during connection establishment

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

This proposal requires major version increments for all protocols, as it changes fundamental message structures. Compatibility will be maintained by:

1. Supporting both old and new protocol versions during transition
2. Using the existing versioning system to negotiate capabilities
3. Implementing conversion logic where necessary

## Test Cases

Testing should focus on:

1. **Message Boundaries**: Verify each stream handles exactly one message type
2. **Type Safety**: Confirm no generic byte arrays for complex structures
3. **Protocol State**: Test correct state transitions in stateful protocols
4. **Version Negotiation**: Verify correct handling of protocol versions

## Implementation

Implementation will proceed in phases:

1. Define common message types for cross-protocol use
2. Update protocol buffer definitions for each protocol
3. Modify protocol handlers to enforce single-message-type streams
4. Update documentation and client libraries

## Security Considerations

This standardisation significantly improves security by:

1. **Preventing Type Confusion**: Strong typing reduces misinterpretation of message data
2. **Limiting Attack Surface**: Clear message boundaries reduce opportunities for exploitation
3. **Enabling Static Analysis**: Well-defined types allow better static analysis tools
4. **Simplifying Validation**: Structured messages enable more thorough validation
5. **Clarifying Protocol States**: Explicit message types make unexpected state transitions easier to detect

## Copyright Waiver

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
