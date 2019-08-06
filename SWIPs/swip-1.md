---
swip: 1
title: Message to honey oracle
Author: Aron Fischer <aron@ethswarm.org>, Rinke Hendriksen <rinke@ethswarm.org>, Vojtech Simetka <vojtech@iovlabs.org>
Discussions-to: URL will be provided
Status: Draft
Type: Standards track
Category: Core
Created: 31-07-2019
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Nodes in the SWARM network can send various types of messages. Currently, the SWARM developers have limited data available to set the optimal price of these messages relative to each other and we expect to adjust the relative prices of messages based on advancing insights. It is important that an update of such prices happens simultaneously on all nodes in the network or otherwise accounting imbalances between nodes will come into existence, potentially severely harming the connectivity of the network. 
An on-chain price oracle, managed by a multi-signature wallet of SWARM stakeholders provides a clean way for updating relative prices; the SWARM source code will never require an update but instead references the address of the oracle which updates its quoted prices at predictable times.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
To enable changing the relative prices of SWARM messages for all nodes simultaneously, SWARM will provide a msgToHoney payment oracle, initially managed by SWARM stakeholders and developers. The msgToHoney oracle receives a message type and returns a price + validUntil tuple. The msgToHoney oracle lives on the Ethereum blockchain and is managed by a multi-signature of Swarm stakeholders and developers. Once nodes receive a message to account for, they will query their local database on whether they have a valid price for this message. If this is the case, the price will be applied by the node, if this is not the case, the nodes will query the msgToHoney oracle. The oracle provides a new price before the old price expires, to allow nodes to pre-load new prices before old ones expire. If the oracle fails to submit a new price, while the old price is expired, nodes will continue querying the msgToHoney oracle at a set interval and apply the most-recent price known to them. 

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
In Swarm, nodes send various types of messages; chunk requests, chunk delivery, PSS… to name a few. Every message is priced differently to reflect the different load such messages have on the system. To ensure optimal usage and health of the network it is essential that these prices are quoted relative to their load on the network. If this is not the case certain messages will be too cheap - causing a burden on service providers without sufficient compensation, while others will be too expensive - causing such messages to be less frequently send. The SWARM network must be used by real nodes to get insights on how messages should be priced relative to each other. Because of this, there is a need for an update process of the relative prices of messages on a live network. This update process should be atomic: either all nodes upgrade or none, which is currently not facilitated by the SWARM source code. Without such a process updating will affect that, while not all nodes are on the same release, nodes with an old release will account for messages in one way and nodes with a new release will account for messages differently. Eventually, this will result in disconnects due to balance differences between nodes who run different versions of the software. This SWIP proposes an on-chain price oracle to enable an atomic update process of message prices without requiring nodes to update their source-code. 

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
* The SWARM source-code references the address of a smart-contract which acts as a honey price oracle.
* The price oracle implements the MsgToHoneyPrice interface (to-be specified) 
* The MsgToHoneyPrice contract will be initially owned by an M/N multi-sig of SWARM developers and stakeholders.
* Upon receiving/sending of a message, a node checks his local database if he has a current valid price for this message type. If not, the node will query the price oracle to get the current price. The node will apply the current price to the balance of his peer. 
* The node will keep actively track of the retirement of prices and will query the price oracle an x-duration (e.g. 10 hours) before the expected release of a new price to pre-load the new-price in his local database. If no new price is quoted by the oracle after the old price has expired nodes will query the oracle at set intervals to ask for the new price
* If the oracle does not list a new price or cannot be reached while the old price is expired, nodes will apply the old price.   
* Upon start-up, nodes will look at the contents of their local database and query the price oracle if no or invalid prices are listed locally or the listed price expires soon.
* Nodes expect other nodes to apply the same price as they do themselves. Due to the asynchronicity of the network, this will not necessarily be true around the period that prices are updated, which causes accounting dust (pollen) to be collected. This SWIP does not facilitate a solution for this, as the expected amount of pollen is not high enough to cause disruptions in the network. 
## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->
No alternative solutions to updating the *relative* message pricing was considered. Noteworthy is perhaps to look at how op-code prices (in gas) are updated in Ethereum. Also here, it concerns relative prices and the developers are tweaking the gas-prices almost every hard-fork (see [opcode re-price discussion](https://ethereum-magicians.org/t/opcode-repricing/3024)). Using an oracle, updatable by a multi-signature of SWARM developers effectively also allows the developers to set prices (just as they do with ether opcodes). However, the ethereum opcode upgrade mechanism must also be approved by the majority of the hashing power of the Ethereum network (to have a succesfull hard-fork). This check is missing in the current design for messageToHoney price oracles. 

## Backwards Compatibility 
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
This SWIP is backward compatible as long as the price oracle quotes the same prices as listed in the price matrix of the non-upgraded SWARM nodes. It is up to the owner of the MsgToHoney oracle to ensure that he does not update prices too much while not all nodes run are on the new SWARM. Currently, the SWARM is not running with a live test net for settling prices, so we expect no problems with this SWIP if it is implemented before the SWARM will go live with price-incentivization. 

## Test Cases 
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
No test cases for this SWIP are provided at this moment.

## Implementations
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
No implementation for this SWIP is provided at this moment.
## Copyright Waiver
 Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
