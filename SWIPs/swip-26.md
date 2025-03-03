---
swip: 26
title: Standardised Chunk Type Framework
status: Draft
type: Standards Track
category: Core
author: mfw78 (@mfw78)
created: 2025-03-03
---

## Simple Summary
This SWIP introduces a standardised framework for defining chunk types in Swarm, improving security and interoperability through consistent type identification and validation.

## Abstract
This SWIP proposes a standardised framework for defining and processing chunk types in Swarm. By creating a formal type system for chunks, including content-addressed chunks (CAC) and single-owner chunks (SOC), we improve security, interoperability, and maintainability across the Swarm ecosystem. The proposal defines a structured approach to chunk identification, versioning, and validation without modifying the wire protocol. Key innovations include fixed-length type-specific headers, deterministic address calculation, and formalised validation rules.

## Motivation
Swarm's storage layer is built around chunks as the fundamental unit of data. Currently, the system supports multiple chunk types, but lacks a standardised type system. This creates several issues:

1. **Ambiguous Processing**: Without explicit type information, chunk processing depends on implicit detection methods, leading to potential security vulnerabilities.

2. **Limited Extensibility**: Adding new chunk types requires changes to core validation logic, making it difficult to evolve the system.

3. **Inconsistent Validation**: Chunk validation logic is spread across multiple components, leading to potential inconsistencies.

4. **Type-Safety Gaps**: Without formal type definitions, runtime type errors can occur when processing chunks.

A standardised chunk type framework would address these issues by providing a consistent, extensible system for defining, identifying, and validating different chunk types.

## Specification

### Core Concepts

#### 1. Chunk Structure

A standardised chunk shall conceptually consist of:

1. **Header**: Metadata describing the chunk and its contents
   - Common Header: Information common to all chunk types (type, version)
   - Type-Specific Header: Additional fields specific to the chunk type
2. **Payload**: The actual chunk data

The chunk's address is not part of the chunk itself but is deterministically derived from the chunk's contents based on its type.

#### 2. Common Chunk Header

The common chunk header shall contain:

1. **Type**: The chunk type identifier (1 byte)
2. **Version**: The chunk format version (1 byte)

| Type ID | Name | Description |
|---------|------|-------------|
| 0x00    | CAC  | Content-addressed chunk |
| 0x01    | SOC  | Single-owner chunk |
| 0x02-0xFF | Reserved | Reserved for future chunk types |

#### 3. Fixed-Length Type-Specific Headers

All type-specific headers MUST be of fixed length for their respective chunk types. This ensures that at a wire-level, the maximum size of a chunk is always known and predictable, based on the first 2 bytes (type and version).

Example header sizes:
- CAC header: 10 bytes (2 bytes common header + 8 bytes span)
- SOC header: 99 bytes (2 bytes common header + 32 bytes ID + 65 bytes signature)

### Address Calculation

The address of a chunk shall be deterministically calculated based on its type, version, and contents. We define the general address calculation function as:

$$\text{Address} = f_{\text{type}}(\text{header}, \text{payload})$$

Where $f_{\text{type}}$ is the type-specific address calculation function.

#### Generic Address Derivation Function

For any chunk type, the address derivation function can be formally defined as:

$$f_{\text{type}}(\text{header}, \text{payload}) = \mathcal{H}(g_{\text{type}}(\text{header}, \text{payload}))$$

Where:
- $\mathcal{H}$ is a cryptographic hash function (i.e. `keccak256`)
- $g_{\text{type}}$ is a type-specific data preparation function

Different chunk types will implement specific derivation functions based on their requirements.

### Chunk Type Specifications

The Swarm Specifications shall define the standardised format for each chunk type. Adding a new chunk type to the specifications requires:

1. Assignment of a unique type identifier
2. Definition of fixed-length type-specific header structure
3. Definition of payload structure
4. Specification of address calculation function $f_{\text{type}}$
5. Specification of validation requirements

These specifications ensure that all implementations handle chunks consistently and securely across the Swarm ecosystem.

### Type Processing

The chunk processing logic shall:

1. Receive the chunk type and version information from the wire protocol
2. Use the type and version to determine the expected fixed-length type-specific header size as defined in the Swarm Specifications
3. Verify that the received header matches the expected size for the given type
4. Fail fast if the header is malformed or incomplete
5. Extract the type-specific header fields
6. Calculate the chunk address using the type-specific address calculation function
7. Apply type-specific validation rules
8. Process the payload according to type-specific structure

This approach allows for early validation of chunk integrity based on protocol-level type information, reducing parsing errors and simplifying processing logic.

## Rationale

The proposed standardised chunk type framework addresses several key issues in the current implementation:

1. **Type Ambiguity**: By explicitly encoding chunk types in the header, we eliminate ambiguity in chunk processing, enhancing security and reliability.

2. **Extensibility**: The formal specifications allow for future chunk types to be added in a standardised way without modifying core validation logic.

3. **Validation Consistency**: Centralising validation rules in the specifications ensures consistent enforcement across components and implementations.

4. **Memory Efficiency**: Fixed-length headers enable predictable memory allocation and reduce fragmentation.

5. **Parsing Efficiency**: Type-specific parsing paths reduce the need for speculative parsing, improving performance.

The design choices prioritise:
- Security through explicit typing and validation
- Efficiency through predictable memory allocation and fail-fast validation
- Extensibility through the standardised specification system
- Backward compatibility with existing chunk types

## Backwards Compatibility

This proposal maintains backward compatibility by:

1. Preserving existing chunk address calculation methods for current chunk types
2. Supporting current chunk formats with version 0 of each type
3. Allowing for gradual adoption of the type system
4. Providing a conversion layer between legacy and new chunk formats

## Test Cases

Test cases should include:

1. **Header Validation**: Tests that verify correct parsing of type-specific headers for different chunk types
2. **Address Calculation**: Tests that confirm proper address derivation for each chunk type
3. **Size Verification**: Tests that ensure fixed-length headers meet their size requirements
4. **Malformed Input**: Tests that verify proper rejection of malformed chunks
5. **Version Handling**: Tests for correct processing of different versions of the same chunk type

## Implementation

Implementation will proceed in phases:

1. Formalise the chunk type specifications for CAC and SOC in the Swarm Specifications
2. Implement type-aware chunk processing in the node software
3. Add validation framework for existing chunk types based on the specifications
4. Develop compatibility layer for processing legacy chunks

## Security Considerations

The standardised chunk type framework improves security through:

1. **Explicit Type Checking**: Reduces the risk of type confusion attacks
2. **Fixed-Length Headers**: Prevents buffer overflow attacks
3. **Early Validation**: Enables fail-fast behaviour for malformed chunks
4. **Deterministic Addressing**: Ensures consistent and secure chunk addressing
5. **Versioned Security**: Allows security improvements via version updates

## Copyright Waiver

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
