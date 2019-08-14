---
Title: Honey to money oracle
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
Swarm needs a mechanism to set prices which makes sense relative to other (distributed storage) services in the market. As the absolute price of using Swarm is defined by the cost of honey (Swarm's internal accounting unit), we propose a minimal interface to enable upgrading the honey prices network-wide for all nodes. An initial reference implementation is provided for an *on-chain* oracle, managed by Swarm stakeholders and developers. 

## Abstract 
<!--A short (~200 word) description of the technical issue being addressed.-->
The ability to update prices is required in order to:
* Facilitate experimentation with the absolute price of honey (e.g. start at a low price and gradually increase);
* In the presence of cryptocurrency price-fluctuations: provide a stabilizing factor to the incentive received in terms of the costs of operating a node.
* Change the price of Swarm in the long run as the costs of operating a Swarm node is expected to change

Furthermore, such price updates must happen atomically or not at all, to prevent accounting disbalances to appear. We propose an on-chain price oracle that returns the current exchange rate when queried, but leave the room open for other implementations, as long as they satisfy a minimum criteria. The proposed price-oracle will be managed by Swarm developers and stakeholders.

This SWIP is part of a series of SWIPs (but can be implemented on it's own). To see the full picture, please refer to [swip-message_to_honey](./swip-message_to_honey.md), [swip-multiple](./swip-honey_to_money.md), [swip-multiple_payment_processing_support](./swip-multiple_payment_processing_support.md) and the diagram below:
![SWIP_Diagrams.svg](./../assets/swip-honey_to_money/SWIP_Diagrams.svg)

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Nodes keep track of the balances with each other nodes using an internal reference unit: honey. Since honey is not a currency in which nodes can settle their balances with each other - it is merely a unit of account - there is a requirement to facilitate converting honey to a currency. Furthermore, it is desirable that this conversion rate can fluctuate because:

* The Swarm developers plan to initially set the price of honey very low and progressively increase this price to the point where it is sufficiently high to incentivize nodes to offer their service to the network while being low enough not to scare away potential users of Swarm.  
* The costs of operating a Swarm node (electricity/hardware/time) is usually quoted in one of the major currencies (Dollar/Euro/Yen) or a local currency, while the benefit is paid-out in Ether. An incentive to operate a node is the difference between the costs of operating a node and it's benefit and this incentive must be stable, the price of the using Swarm must fluctuate *denominated in Ether*, such that the price does not fluctuate *compared to the costs of operating a node*. 
* The costs of operating a Swarm node is expected to change in the long-run. The price of honey must reflect this change in order to stay competetive with other (decentralized) storage networks and to offer nodes a realistic incentive. 

This update process should be atomic: either all nodes upgrade or none. If we would update the price by releasing a new version of the Swarm source code (as is currently the case), this would be violated as we can't guarantee that all nodes are on the same release. By externalizing the price to an oracle, we can completely decouple Swarm's core functions from price discovery. By building support for price oracles, we can coordinate price changes across the network. and set the stage for future experimentation with various mechanisms for setting prices, from DAOs, to bonding curves, to fixed prices. 

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->
### Minimal criteria
Any oracle implementation must satisfy the following minimal criteria:
* Nodes who query the oracle at the same time, must receive the same price. 
* The oracle must respond reasonably quick. 
* The oracle must be always up, or guarantee a fallback mechanism in case of downtime.
* The oracle must aim to quote a price that maximizes the total utility of the network. That is: the honey-price must be sufficiently high to incentivize net providers to join the network, but sufficiently low as to not scare away potential net users of the network. 
### Initial implementation
* The Swarm source code will reference the Ethereum address of a `HoneyToMoney` price oracle smart-contract
* The price oracle implements the `HoneyToMoney` interface (to-be specified) 
* The `HoneyToMoney` contract will be initially governed such that a subset of stakeholders can make decisions which are not high-impact (i.e. decide on small price-changes), but all stakeholders are required to make high-impact decisions (such as changing the implementation of the oracle, changing governance, decide on big price-changes, etc).
* Before sending a payment (denominated in currency), a node will look in his local cache wether he has an up-to-date price available. If not available, the node will query the `HoneyToMoney` price oracle to get the most up-to-date price conversion. 
* Upon receiving a payment, nodes will determine the honey amount paid by looking up the valid honey price price from the oracle upon receipt of the payment. This might cause payment imbalances between nodes, as the oracle might be queried by the payment sender one or several blocks before the transaction was sent. Experimentation must point-out wether this situation appears and is harming the network. If it does, it is possible to include a payload with the transaction, specifying the time at which the oracle was queried and let the receiving node decide query the oracle for a price at this time if it is within an acceptable time-window. 

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->
We need a way for prices in the Swarm to change over time. However, due to the nature of Swarm there is a need for this price to be decided network-wide, instead of peer-to-peer. Specifically:
- The requirement on connectivity in the local bin and far-away bins means that nodes *must agree* with all nodes in their local bin and at least one node in a far-away bin on the price.
- Zero marginal costs of serving data with perfect competition means that when nodes would engage in peer-to-peer price discovery, the price will tend to zero and a sub-optimal equlibrium of near-zero prices will be reached.
- The high-quantity of transactions implies that nodes cannot engage in price-discovery for every byte of data transacted, meaning they have to agree *beforehand* on how they will come to a price *at a later time*. 
- Nodes are most of the time just conduits for data and payments, meaning that most the time data requests and thus also payments will be because you want to send data to a peer who requested this data from you. 

## Backwards Compatibility 
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
Currently, the Swarm is not running with a live test net for settling prices, so we expect no problems with this SWIP if it is implemented before the Swarm will go live with price-incentivization. 

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
Not currently available

## Implementations 
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
Not currently available

## Copyright Waiver
 Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
