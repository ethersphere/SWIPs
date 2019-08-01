---
swip: 1
title: Message to honey oracle
Author: Rinke Hendriksen <rinke@ethswarm.org>
Discussions-to: URL will be provided
Status: Draft
Type: Standards track
Category: Core
Created: 31-07-2019
---
## Simple summary
Nodes in the SWARM network can send various types of messages. Currently, the SWARM developers have limited data available to set the optimal price of these messages relative to each other and we expect to adjust the relative prices of messages based on advancing insights. It is important that an update of such prices happens simultaneously on all nodes in the network or otherwise accounting imbalances between nodes will come into existence, potentially severely harming the connectivity of the network. 
An on-chain price oracle, managed by a multi-signature wallet of SWARM stakeholders provides a clean way for updating relative prices; the SWARM source code will never require an update but instead references the address of the oracle which updates its quoted prices at predictable times.
## Abstract
To enable changing the relative prices of SWARM messages for all nodes simultaneously, SWARM will provide a msgToHoney payment oracle, initially managed by SWARM stakeholders and developers. The msgToHoney oracle receives a message type and returns a price + validUntil tuple. The msgToHoney oracle lives on the Ethereum blockchain and is managed by a multi-signature of Swarm stakeholders and developers. Once nodes receive a msg to account for, they will query their local database on whether they have a valid price for this message. If this is the case, this price will be applied by the node, if this is not the case, the nodes will query the msgToHoney oracle when needed. The oracle provides a new price before the old price expires, to allow nodes to pre-load new prices before old ones expire. If the oracle fails to submit a new price, while the old price is expired, nodes will continue querying the msgToHoney oracle at a set interval. 
## Motivation
In Swarm, nodes send various types of messages; chunk requests, chunk delivery, PSS… to name a few. Every message is priced differently to reflect the different load such messages have on the system. To ensure optimal usage and health of the network it is essential that these prices are quoted relative to their load on the network. If this is not the case certain messages will be too cheap - causing a burden on service providers without sufficient compensation, while others will be too expensive - causing such messages to be less frequently send. The SWARM network must be used by real nodes to get insights on how messages should be priced relative to each other. Because of this, there is a need for an update process of the relative prices of messages on a live network. This update process should be atomic: either all nodes upgrade or none, which is currently not facilitated by the SWARM source code. Without such a process updating will affect that, while not all nodes are on the same release, nodes with an old release will account for messages in one way and nodes with a new release will account for messages differently. Eventually, this will result in disconnects due to balance differences between nodes who run different versions of the software. This SWIP proposes an on-chain price oracle to enable an atomic update process of message prices without requiring nodes to update their source-code. 
## Specification
* The SWARM source-code references the address of a smart-contract which acts as a honey price oracle.
* The price oracle implements the MsgToHoneyPrice interface (to-be specified) 
* The MsgToHoneyPrice contract will be initially owned by an M/N multi-sig of SWARM developers and stakeholders.
* Upon receiving/sending of a message, a node checks his local database if he has a current valid price for this message type. If not, the node will query the price oracle to get the current price. The node will apply the current price to the balance of his peer. 
* The node will keep actively track of the retirement of prices and will query the price oracle an x-duration (e.g. 10 hours) before the expected release of a new price to pre-load the new-price in his local database. If no new price is quoted by the oracle after the old price has expired nodes will query the oracle at set intervals to ask for the new price
* If the oracle does not list a new price or cannot be reached while the old price is expired, nodes will apply the old price.   
* Upon start-up, nodes will look at the contents of their local database and query the price oracle if no or invalid prices are listed locally or the listed price expires soon.
* Nodes expect other nodes to apply the same price as they do themselves. Due to the asynchronicity of the network, this will not necessarily be true around the period that prices are updated, which causes accounting dust (pollen) to be collected. This SWIP does not facilitate a solution for this, as the expected amount of pollen is not high enough to cause disruptions in the network. 
## Rationale
To be defined
## Backwards Compatibility 
This SWIP is backward compatible as long as the price oracle quotes the same prices as listed in the price matrix of the non-upgraded SWARM nodes. It is up to the owner of the MsgToHoney oracle to ensure that he does not update prices too much while not all nodes run are on the new SWARM. Currently, the SWARM is not running with a live test net for settling prices, so we expect no problems with this SWIP if it is implemented before the SWARM will go live with price-incentivization. 
Test Cases Not currently available
##Implementations
Not currently available
##Copyright Waiver
Copyright and related rights waived via CC0.
