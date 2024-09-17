---
SWIP: <to be assigned>
title: Feed Wrapping
author: Viktor Levente Tóth @nugaon
discussions-to: https://github.com/ethersphere/bee/pull/4677
status: Draft
type: Interface
category (*only required for Standard Track): ERC
created: 2024-09-17
requires (*optional): <SWIP number(s)>
replaces (*optional): <SWIP number(s)>
---

# Feed Wrapping

## Abstract

This SWIP proposes a modification to the existing feed payload structure to support wrapping entire content-addressed chunks (CAC) directly within feeds, eliminating the need for a separate JSON structure containing CAC references and timestamps. This change aims to streamline the retrieval process by allowing a single request to resolve SOC content, enhancing efficiency and compatibility with erasure coding techniques.

## Motivation

The current feed payload structure limits the flexibility and efficiency of content retrieval by requiring separate handling for JSON metadata and content data. By enabling direct wrapping of CACs within feeds, this proposal simplifies the data structure and retrieval process. This change is particularly beneficial for decentralized applications (dApps) that require rapid access to mutable information, potentially halving the time required to retrieve such data.

## Specification

- **Feed Payload Changes**:
  
  The feed payload must no longer use a JSON structure with `span`, `ts` (timestamp), and `swarmHash`. Instead, it should directly wrap a content-addressed chunk.

- **API Changes**:
  
  - The `GET /feeds/{owner}/{topic}` endpoint must be updated to handle the new payload structure. The `at` parameter should be deprecated for sequential feeds, reflecting the removal of the `ts` attribute.
  - Introduce `GET /soc/{owner}/{id}` endpoint, requiring path parameters `owner` and `id` (both hex-encoded strings). This endpoint should handle the root chunk as a Single Owner Chunk by default and resolve content similarly to the `GET /feed` endpoint.
  - Both endpoints must support a new request header `swarm-only-root-chunk`. When set to `true`, this boolean flag should instruct the node to retrieve only the root chunk of the content, without resolving the entire chunk tree.
  - Responses from these endpoints include a new header `swarm-soc-signature`, encoding the signature of the Single Owner Chunk.

- **Erasure Coding Support**:
  
  - To accommodate content that may exceed the size of one chunk and may be erasure-coded, relevant request headers for erasure coding must be introduced and supported by the updated endpoints.

## Backward compatibility 

It must be maintained by checking for the presence of `span + ts + swarmHash` in the payload. If present, the system should attempt to retrieve content using the `swarmHash`.

## Rationale

This enhancement simplifies the feed structure and aligns with the broader goals of optimizing data storage and retrieval within the ecosystem. By integrating the handling of CACs directly into the feed payloads, the proposal reduces the complexity and overhead associated with managing separate metadata and data streams, thereby improving performance.

## Test Cases

The tests for the feed wrapping feature in the [`feed_test.go`](github.com/ethersphere/bee/tree/master/pkg/api/feed_test.go) file cover various scenarios to ensure the functionality and robustness of the feed API. Here's a breakdown of the tests conducted:

1.  **Get Feed with Timestamp**:
    
    - This test checks the retrieval of a feed using a specific timestamp. It verifies that the correct chunk data is returned and that the appropriate headers are set.
    - See the test "with at".

2.  **Get Latest Feed**:
    
    - It tests the retrieval of the latest feed update. The test ensures that the correct chunk is returned and that the response headers are correctly populated.
    - See the test "latest".

3.  **Chunk Wrapping**:

    - This test verifies that data can be correctly wrapped in a chunk and retrieved through the feed API. It checks the integrity of the data returned against the original input.
    - See the test "chunk wrapping".

4.  **Legacy Payload with Non-Existing Wrapped Chunk**:
    
    - This scenario tests the behavior when a requested chunk does not exist in the storage. It ensures that the API correctly returns a not found error.
    - See the test "legacy payload with non existing wrapped chunk".

5.  **Bigger Payload than One Chunk**:
    
    - This test handles cases where the payload is larger than what can fit in a single chunk. It tests both the retrieval of the entire chunk tree and just the root chunk.
    - See the tests under "bigger payload than one chunk"

These tests collectively ensure that the feed wrapping feature handles various data sizes, correctly wraps and retrieves data.

## Implementation

The implementation of this proposal requires modifications to the feed API and underlying data structures. The changes should be implemented in a backward-compatible manner to ensure interoperability with existing clients. The updated endpoints should be thoroughly tested to validate the new functionality and ensure compatibility with erasure coding

The POC implementation can be followed on [feat: feed wrapping](https://github.com/ethersphere/bee/pull/4677) PR.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).