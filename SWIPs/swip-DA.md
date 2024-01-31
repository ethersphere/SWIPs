---
SWIP: <to be assigned>
title: Data Availability Insurance Commitment
author: Antonio Gonzalo (@tonytony32)
discussions-to: <URL>
status: Draft
type: Standards Track
category: Core
created: 2024-01-31
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
A proposal to ensure data integrity and availability in Swarm through an onchain commitment in L1, leveraging staking mechanisms, a challenge-response protocol and zk-proofs.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
This SWIP introduces a Data Availability Insurance System for the Swarm network, ensuring the integrity and accessibility of data through a challenge-response mechanism. The system incorporates staked nodes (insurers), challenge-response protocols, and zkproofs to verify data availability, providing a reliable and efficient data ecosystem for Swarm.

## Motivation
The current Swarm protocol lacks a dedicated system ensuring data availability and integrity, leading to potential vulnerabilities in data accessibility. This SWIP aims to address this inadequacy by introducing a system that not only guarantees data availability but also incentivizes nodes through a stake-based mechanism, enhancing the overall security and reliability of the Swarm network.

## Specification
The system's cornerstone is the on-chain (L1) insurance commitment:

- Insurers Commitment: Insurers make an on-chain commitment to store specific data, identified by a hash verifiable by L1 EVM.
- Challenge Mechanism: Data availability can be challenged via an L1 transaction, costing both the challenger and the insurer.
- Response and Penalties: Insurers must respond with the requested data within a set timeframe. Failure to respond leads to stake slashing.
- Incentive Alignment: The cost structure deters unnecessary challenges. Insurers are motivated to store and keep data available on Swarm, ensuring no challenges arise.

**Data Availability Committee (Insurer Nodes)** 

Nodes stake tokens and make an on-chain commitment for each dataset, ensuring data integrity and availability.

**Challenge-Response Protocol**

Leverages Swarm and L1 transactions for data verification and retrieval.

   1. Insurers create an on-chain (L1) commitment ('Insurance') for storing a particular piece of data. This commitment is identified by a hash an can be checked by L1 EVM.
   2. It can be challenged by an L1 transaction (at cost), to which the insurer has a certain time to respond, also with an L1 transaction.
   3. If there is no response within the allotted time, the insurer’s stake is slashed.
   4. Challenges incur costs as well, ensuring only valid disputes are raised. Optionally, challengers might stake tokens to deter frivolous or malicious challenges, forfeited if the challenge is met successfully.

**Consensus over Swarm Hash**

The system ensures data integrity if there is node consensus over the swarm hash of the dataset. [Erasure coding](https://papers.ethswarm.org/erasure-coding.pdf) and inclusion proofs allows reconstruction of the full dataset from partial data and ensures data authenticity through cryptographic evidence, even from non-commitee (non insurers) members.

**Data Availability**

To prove in L1 that the dataset has reached and has been uploaded into Swarm nodes, and therefore it is available within Swarm, an additional zk-proof is required. That proof must include the merkle tree from data chunks (Swarm hash), representing the data stored in Swarm, and the corresponding postage stamps of the dataset.

The zk-proof circuit will need to include operations for verifying the association of the given swarm hash with the specific postage stamp, and it has sufficient balance to cover the cost of storing the data.

The members of the DAC (insurers) are responsible for verifying these proofs before posting the commitment to L1. 

Once the proofs are posted, the challenge-response protocol functions as 'data availability sampling', to allow anyone to check the availability of data without having to download all the data. By performing multiple rounds of randomised challenges on small parts of the dataset, the confidence that the data is available increases. Once it reaches a certain confidence level (e.g. 99%), it considers the entire dataset available.

**Economic Incentives**

- Insurers are compensated for their services and incur costs related to L1 gas, Swarm network queries and verifying publisher's valid proofs.
- Challengers are positively incentivised to detect faulty or malicious commitments from insurers.
- Publishers are required to the attach the postage stamp and compute the zk-proof to insure the data. 

### Rollup's Publishing

To verify the availability of a particular transaction, guaranteeing that the transaction data published by the sequencer is indeed the sequence of transaction that was executed in the rollup:

1. The sequencer uploads a batch of transactions to Swarm and buys insurance for them for a given amount of time.
2. An on-chain commitment will be placed in L1 including the number of transactions in the batch and the Merkle root of the array of transaction hashes. The challenge is the index of the missing transaction and the response is the transaction together with the Merkle proof of inclusion.
3. In order to guarantee that the sequencer indeed publishes the transaction batch in Swarm, a zk proofs are set to prove that the sequence of transactions committed to Swarm indeed results in the state transition posted to L1. 
4. Members of the DAC (insurers) are responsible for verifying these proofs before the state transition is insured.
5. The upload to Swarm, the on-chain commitment and the insurance fee must be cheaper than including all transaction data on the L1 blockchain.

An alternative would be to also include the transaction hashes in the on-chain commitment transaction and have this hash array signed by the insurer. Thus, the cost of creating the commitment would be increased by the cost of including this data, hashing this data and a fixed overhead for including and verifying the signature.

## Rationale
The proposed system addresses the specification of a dedicated data availability mechanism in Swarm. By integrating staking, challenge-response, and zkproofs, the system ensures data integrity, incentivizes proper behavior, and deters malicious activities. The stake mechanism and gas fees for challenges are designed to balance incentives and discourage frivolous or malicious challenges, ensuring network stability and reliability.

## Backwards Compatibility
The system is designed to be compatible with the existing Swarm infrastructure. Adjustments may be required in the Swarm node software to integrate the staking and challenge-response mechanisms. These changes are expected to be non-intrusive and backward-compatible with current Swarm functionalities.

## Test Cases
Test cases will be developed to assess:
1. The reliability of data retrieval by assurer nodes.
2. The accuracy of the challenge-response mechanism.
3. The efficiency and effectiveness of zk-proofs in data availability.

## Implementation
The initial implementation will focus on integrating the staking mechanism, establishing the challenge-response protocol, and incorporating erasure coding within the Swarm network. A phased approach will be adopted, starting with a proof-of-concept, followed by rigorous testing and community feedback before finalizing the implementation.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).

