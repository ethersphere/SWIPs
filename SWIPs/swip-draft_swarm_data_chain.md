---
WIP: <to be assigned>
title: Swarm Data Chain
author: Mohamed Zahoor (jmozah)
discussions-to: https://discord.com/channels/799027393297514537/1068161013934985287/1239528605013377085
status: Draft
type: Standards Track
category: Layer 2
created: 2024-05-15
---



<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->
`SWIP-draft_title_abbrev.md`.



## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
One of the biggest issues that any blockchain face is to store and manage its ledger(data). The faster the transaction execution of a chain, the bigger the issue of making its data available and retrievabile to all its clients. This SWIP proposes to solve the data availabilty and retrievability problems of other blockchains by having a generic data chain to manage and store their data. This data chain will use Swarm as the storage layer to acheieve this goal.


## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
Blockchain scaling usually means to scale in the following dimensions
- Transaction Execution 
- Data storage 
- Bandwidth

Lately, Layer2 networks have helped scale Ethereum to a degree by offloading the Transaction Execution and compressing block data (rollup). Data storage related issues like availability and retrievability are still open problems. The proposed solution is to solve the data availability and retrievability problems of  blockchains (Especially Ethereum Layer2's). Chains will be able to store their data (blob, blocks, state, logs, receipts etc) and allow its clients to check for avilability and to retreive them later if needed. This will scale the respective chains by having more economicaland secure  data storage and efficient use if p2p bandwidth when retreiving the data.


## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

Modular blockchains are gaining popularity so that new chains can be build fast and with ease. Having a modular storage layer for blockchains will make the data storage of these chains more manageble. Storing a blockchain data in a decentralised storage will give rise to new dimensions for centralised applications like etherscan.

Following are some of the motivations for creating a generic Data chain
- Solving Data Availability problems
    - Light nodes need strong data availability assurances without the need to download the entire block.
    - Ethereum Layer2 is another example where the data should be available to other nodes for liveness.
    - This is also required to build future "stateless" clients where it need not be required to download and store the data.
- Solving Data Retrievability problems:
    - Blockchains have special archive nodes to store the entire data. most of the other clients rely on them to get the full data. This is a problem especially if the number of archive nodes are small.
    - Future chains can totally eliminate the storage of data in each client and instead support a stateless client model which will be light and thereby increase decentralisation. 

- Using Swarm as the base Layer:
    - Highly distributed storage network
    - Provable data storage (Merkle Proof)
    - Censorship resistance
    - Data redundancy (chunk is stored in all the neighbourhood)
    - Efficient use of Bandwidth if a chunk is requested often.


## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

The design consists of a new "Data Chain" and the existing Swarm network. 

- New Data Chain 

    - This is a new blockchain that uses a Delegated Poof of Stake (DPoS) consensus with multiple validators which manage the network. Validators need to stake a certain amount of BZZ to become active. Other BZZ holders can delegate their BZZ tokens to any of the existing validators. The voting power of a validator will be proportional to the number of BZZ tokens it has staked.

    - Validators arrive at consensus about a new data (ex: block) that is created by the supported blockchain. Once greater then 2/3 majority if reached about the data, it is then permenantly stored in the Swarm network. The Validators will take care of all the pre-processing work like data sampling and organising the data before storing them in Swarm. Any request for the original data or a piece of data (sample) will get the necessary mapping from the validators and will get the respective Swarm hash to access the data from Swarm network.

    - New data sources (blockchains) and types (block, state, logs, receipts, blobs etc) can be added for ingestion over time using governance.

    - The state of the Data chain should be updated to a smart contract in Layer 1 (Ethereum) so that it inherits the same security gurantees as in Ethereum.


## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

1) [SWIP-42](https://github.com/ethersphere/SWIPs/pull/42/files#diff-b0a6bcf1f6e706ea47edb89ad8b82c36c4ef6dee3576e1e91b2b0248fd31a5a8) proposes a similar design where every data that is ingested is updated to layer 1. This solution is prohibitively expensive and less in data capacity since it uses Layer 1.

2) Using a seperate blockchain for managing the storage makes it much more data centric and helps to create a generic solution to add dataspaces on the fly.

3) Using Swarm as the final resting place for data inherits all the goodies that has been built in Swarm over the years.

4) Later this chain can be upgraded to have an EVM so that more programmable usage and control of data can be enabled.

5) Having a seperate Swarm chain and bringing in more chain data in to the network and will help Swarm operators directly.

6) Future blockchains will be highly decentralised as the resource requirements of a client will come down drastically and at the same time they will have the same security as if they have stored all the chain data.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->

This is a new design for Data Chain so there is no specific backward compatibility requirement. Special care has to be taken to ensure that the data sampling algorithms are backward compatible. 

With r.to Swarm, the validators will use the Swarm API to push data and store their BZZ address as part of their state data.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->

AT first we should run a testnet that can capture some data from testnets of other blockchains. This will help in testing the working of the chain and the integration with Swarm network. 

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->

To start with, the Data chain ca be built with CometBFT and Cosmos SDK on top of it. We can start with few validators and then increase the number as we test. The BZZ can be brough in using a bridge from Ethereum Layer1 so that validators can stake and other users can delegate them to run the network.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
