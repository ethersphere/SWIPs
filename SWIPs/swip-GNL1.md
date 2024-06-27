---
swip: 0
title: Trustless Access to L1 Gnosis Chain State
status: Active
type: Meta
category: core
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
author: Antonio <antonio@ethswarm.org>
created: 2024-06-27
---

## Simple Summary
This SWIP proposes a method to access the current and historical L1 state of Gnosis Chain in a trustless, efficient, and scalable manner using Swarm and Erigon as the base client with a hook.

## Abstract
This proposal addresses the issues related to accessing the current or historical state of blockchain data on Gnosis Chain. It offers a principled way to ensure data access is verifiable, efficient, and scalable, thereby improving the usability and reliability of decentralized applications (DApps) that rely on Gnosis Chain state data.

## Motivation
When DApps need to access blockchain state, they typically call the API of a Gnosis Chain client. Running a full node to provide this state is resource-intensive and impractical for many users. Light clients and centralized service providers have emerged to address this but have their own limitations, including efficiency issues, syncronization times and privacy concerns. This SWIP aims to provide a more decentralized, scalable, and verifiable solution.

## Specification
### Protocol Outline with Swarm
1. **State Data Retrieval**:
    - Gnosis Chain’s state consists of small binary blobs addressed by their hashes.
    - Swarm can retrieve and cache binary blobs (chunks) up to 4 kilobytes in size.
    - Light clients request state data from Swarm, which serves from cache or routes to the closest node in XOR metric.

2. **Caching and Incentives**:
    - Nodes cache frequently accessed data and receive bandwidth incentives.
    - Storage incentives ensure long-term availability of data.

3. **Integration with Erigon**:
    - Modify the Erigon client to use Swarm for state data storage and retrieval.
    - Design a generic hook for easy integration with other decentralized storage solutions like IPFS and Arweave.

### Indexing for Querying State
1. **Indexing Requirements**:
    - To efficiently query Gnosis Chain state, indexing of the blockchain data is required.
    - Swarm will support the reindexing of data to allow for complex queries, such as filtering transactions by amount or identifying specific token holders.

2. **Indexing Mechanism**:
    - Implement a method to index the state data stored in Swarm.
    - Utilize inclusion proofs, BMT proofs, feeds, and integrity protection structures to ensure that query responses are verifiable.

3. **Query Processing**:
    - Support complex queries similar to database operations (e.g., filtering, sorting).
    - Ensure that all queries can be resolved with verifiable accuracy.

## Rationale
Current methods for accessing Gnosis Chain state data are either centralized or inefficient. This proposal leverages Swarm’s decentralized storage capabilities to provide a scalable and verifiable method for state data access. The use of Erigon with a hook ensures minimal impact on existing client roadmaps while promoting modularity. Adding indexing capabilities will address the need for more complex and efficient queries, making the system more versatile and powerful.

## Backwards Compatibility
This SWIP introduces no backwards incompatibilities. It involves modifications to the Erigon client to include a hook for Swarm, which does not affect the existing functionality of the client. The indexing mechanism will be an additional feature that enhances querying capabilities without disrupting current processes.

## Test Cases
Test cases will include:
- Retrieving state data using the modified Erigon client.
- Verifying the integrity and availability of state data retrieved from Swarm.
- Performance benchmarks comparing the modified client to existing methods.
- Testing complex queries to ensure accurate and verifiable results.

## Implementation
The implementation will involve:
- Modifying the Erigon client to integrate with Swarm.
- Developing the hook for Swarm and ensuring compatibility with other storage solutions.
- Implementing the indexing mechanism for efficient state querying.
- Comprehensive testing and validation of the modified client.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).