---
SWIP: <to be assigned>
title: Introduce support for multiple payment modules in Swarm
author: Aron Fischer <aron@ethswarm.org>, Rinke Hendriksen <rinke@ethswarm.org>, Vojtech Simetka <vojtech@iovlabs.org>, Diego Masini <dmasini@iovlabs.org>
discussions-to: <https://swarmresear.ch/>
status: Draft
type: Standards Track
category: Core
created: 2019-07-22
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
In the current Swarm design, accounting of the data exchanged between peers and the payment for such data is coupled. To promote widespread adoption of Swarm it is best to abstract the actual payment mechanism and let nodes participating in the network decide what payment system better adapts to their needs.

This SWIP proposes decoupling the accounting for services provided via Swarm from the actual handling of the payment. A generic payment module will be defined as an interface for handling the payments; the existing SWAP chequebook will be the first implementation of this interface. Doing this will pave the way for enabling other currencies to define their implementation of the payment module, which will increase the resilience of the Swarm network (i.e. if one payment module fails, others might still work) while making Swarm attractive to a wider user-base by allowing nodes to pay in their currency of preference.

To allow multiple payment modules to co-exist on the same network, nodes must be able to come to an agreement on which payment module (or modules) to use. We propose a mechanism for nodes to indicate these preferences during handshake; such preferences should be normalized and weighed. Furthermore, there must be a fallback option provided for the payment module to ensure that nodes can always connect. Finally, there should be a mechanism for each node to keep track of the payment methods negotiated with its peers.

This SWIP is part of a series of SWIPs (but can be implemented on its own). To see the full picture, please refer to [swip-message_to_honey](./swip-message_to_honey.md), [swip-honey_to_money](./swip-honey_to_money.md) and the diagram below:

![SWIP_Diagrams.svg](./../assets/multiple-payment_processing_support/SWIP_Diagrams.svg)

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
The payment module interface specifies the minimum requirements to allow different implementations to be supported by Swarm. An implementation of this interface will be responsible for handling payments, hiding the specifics of the underlying payment processing and providing a unified API, thus decoupling the distributed storage service from the actual payment system used by participants. 

Nodes need to keep track of the balances that result from consuming/servicing storage from/to other nodes. This leads to the need of an abstract accounting unit that can be used for storage and bandwidth. We define ```honey``` as the Swarm accounting unit. Since ```honey``` is not a currency in which nodes can settle their balances with each other there should exist a mechanism to convert honey to a given currency. For the full details on how ```honey``` works, please refer to [swip-message_to_honey](./swip-message_to_honey.md) and[swip-honey_to_money](./swip-honey_to_money.md).

A minimal payment module needs to accept a price in ```honey```, converts this price to a currency via an agreed-upon price oracle, sends the payment and returns when the payment is processed (either successfully or unsuccessfully). Making it clear in the code that this is the minimum expected from a payment module will both increase the readability and audibility of the Swarm source code, but will also make it easier for other payment methods to implement the payment module interface, hereby allowing users to choose how they want to settle their payments, which increases the resilience of the network and enlarges the potential user base. 

Incorporating the required abstractions to support payment modules will require modifying the handshake protocol, the message handling, and the accounting and payment strategies implemented at the moment.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Currently, Swarm is implementing the chequebook contract (with a base currency of Ether). While the chequebook contract is beautiful in its simplicity, it is expected that users of Swarm might prefer a different way of compensation for their services provided, especially if they are already participating in a payment network (e.g. Lumino, Raiden or Lightning network). 

Furthermore, storage providers might want to be compensated with a different currency or they might want to settle their payment using a different Blockchain altogether. 

Finally, new users of Swarm could bootstrap its participation in a payment channel network by providing storage services with zero cost of entry, as described in [Generalised Swap Swear and Swindle games (Tron & Fischer, 2019).](https://www.sharelatex.com/read/yszmsdqyqbvc) 

When it becomes possible for nodes to set their preference for a payment module, developers will be incentivized to implement payment modules on Swarm as it will be easy for users to choose to pay with this module. It will also seamlessly enable multicurrency support and foster interoperation across Blockchains without forcing participants to be tied to a single Blockchain or settlement technology.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

### Generic payment module
At high level a payment module is responsible for sending a payment to a recipient (a peer providing storage services) for services provided. How payments are actually performed will depend on the specific implementation of the payment module. The payment module is then responsible for:

* Resolving the conversion from honey to money.
* Ensuring that the user can engage in SWAP accounting for the chosen payment module before payment is due.
* Sending a payment to the recipient.
* Sending a message to the accounting module upon receipt of payment
* Ensuring that the user can send payments with the chosen payment module before payment is due.
* Handling any potential errors.
* Optionally exposing other methods such as querying balances, topping up balances or sending payments (outside of Swarm). 

### Allowing multiple payment modules
When allowing multiple payment modules, it is essential for nodes to communicate their preference. There are three dimensions to take into consideration for the payment preference: 

1. Currency to use
2. Price oracle to use
3. Payment provider to use

We propose a standardized way to communicate these preferences and an algorithm to resolve any two preferences lists.

For any dimension, nodes list the relative importance of them. Consequently, nodes specify their accepted options within each dimension. Importance is communicated through Swarm by any positive integer

The following is an example of the proposed configuration:

```yaml
# The relative importance of each dimension for the node
dimensions:
	currency: 70
	provider: 20
	oracle: 10

# Supported payment options by the node.
# A payment module is defined by a currency, provider and oracle. Weights are the associated preferences.
currencies:
	rif:
		weight: 36
		providers:
			lumino:
				weigth: 15
			raiden:
				weight: 45
		oracles:
			rifOracleA:
				weigth: 10
			rifOracleB:
				weigth: 70
			rifOracleC:
				weigth: 60
	xdai:
		weight: 9
		providers:
			Lumino: 
				weigth: 10
		oracles:
			xDaiOracle: 
				weight: 20
	dai:
		weight: 5
		providers:
			raiden:
				weight: 80
		oracles:
			daiOracleA: 
				weight: 30
			daiOracleB:
				weight: 20
	eth:
		weight: 40
		providers:
			swap:
				weight: 35
		oracles:
			ethOracleA:
				weight: 90
			ethOracleB:
				weight: 10
```

This configuration is used by the payment method selection algorithm in the following way: 

1. Based on the node configuration generate a set of triplets in the form ```[currency, provider, oracle]```. As an example let's take from the previous configuration the ```rif``` entry. From that entry we can build the triplets `[rif, lumino, rifOracleA]`, `[rif, lumino, rifOracleB]`, `[rif, raiden, rifOracleA]`, `[rif, raiden, rifOracleB]`, but triplets are generated for the other currencies as well. 
2. Exchange the generated set of triplets with the peer B.
3. Keep the set of triplets which are common (intersection between tripletsA and tripletsB). If no common set exist, choose the fallback option for each dimension, as shown in the following table:

	| Dimension  | Fallback option |
	| ---------- | --------------- |
	| Currency to use | Wei (Ether)                    |
	| Price oracle    | HonMon oracle <SWIP reference> |
	| Payment method  | Chequebook contract            |

4. Compute the weighted preference of each remaining triplet from node A and node B as:

	```golang
	weightedPreference := normalized(dimensions.currency) * normalized(triplet[n].weight) + 
		+ normalized(dimensions.provider) * normalized(triplet[n].provider.weight) + 
		+ normalized(dimensions.oracle) * normalized(triplet[n].oracle.weight)
	```

	Since weights and dimensions do not need to add up to a particular value (e.g. 100) they need to be normalized.
	As an example, let's take the first generated triplet (`[rif, lumino, rifOracleA]`). The normalized dimensions and weights are:
	
	***Sum of all dimension values = 100***
	* Normalized currency dimension: 70 / 100 = 0.7
	* Normalized provider dimension: 20 / 100 = 0.2
	* Normalized oracle dimension: 10 / 100 = 0.1

	***Sum of all currency weights = 90***
	* RIF normalized weight = 36 / 90 = 0.4

	***Sum of all provider weights for RIF = 60***
	* Lumino normalized weight = 15 / 60 = 0.25

	***Sum of all oracle weights for RIF = 140***
	* oracleB normalized weight = 70 / 140 = 0.5

	Then the ```weightedPreference``` for this triplet is:

	```golang
    weightedPreference := [0.7 * 0.4 + 0.2 * 0.25 + 0.1 * 0.5]
	weightedPreference := 0.38
	```

5. Add the weights of matching triplets from A and B and choose the one with the highest cumulative preference value:

	```golang
	max(weightedPreference for triplet[0] from A + weightedPreference for triplet[0] from B, ..., weightedPreference for triplet[N] from A + weightedPreference for triplet[N] from B )
	```

	where n is the number of intersecting triplets from A and B. 

6. If there is more than one triplet with the same ```weightedPreference``` value, both nodes will compute for each colliding triplet a tie breaker as follows:

	```golang
	tieBreaker := hash(triplet.coin || triplet.provider || triplet.oracle)
	```
	
	and then each node will select the triplet with the minimum ```tieBreaker``` value.

### Technical details

This section describes the existing code and provides suggestions on how it could be modified to achieve the end goal of this SWIP. It is by no means an indication on how this feature should be implemented, the final design and implementation will be agreed with the community and it could differ completely from what it is described here.

Swarm defines a ```Balance``` interface in ```p2p/protocols/accounting.go``` as an abstraction for the accounting process:

```golang
// Balance is the actual accounting instance
// Balance defines the operations needed for accounting
// Implementations internally maintain the balance for every peer
type Balance interface {
	// Adds amount to the local balance with remote node `peer`;
	// positive amount = credit local node
	// negative amount = debit local node
	Add(amount int64, peer *Peer) error
}
```

```Swap``` (as defined in swap/protocol.go) is an implementation of this interface and among the list of messages supported by its ```Spec``` there is the ```EmitChequeMsg``` message:

```golang
// Spec is the swap protocol specification
var Spec = &protocols.Spec{
	Name:       "swap",
	Version:    1,
	MaxMsgSize: 10 * 1024 * 1024,
	Messages: []interface{}{
		HandshakeMsg{},
		EmitChequeMsg{},
	},
}
```

When received, this message is handled by the ```handleEmitChequeMsg``` function defined in ```swap/swap.go```:

```golang
func (s *Swap) handleMsg(p *Peer) func(ctx context.Context, msg interface{}) error
```

The ```handleEmitChequeMsg``` function executes the accounting and payment processing required by Swap, tightly coupling both operations.

In the current codebase ```Swap``` is a member of the ```Peer``` struct defined in ```swap/peer.go```: 

```golang
// Peer is a devp2p peer for the Swap protocol
type Peer struct {
	*protocols.Peer
	swap               *Swap
	backend            contract.Backend
	beneficiary        common.Address
	contractAddress    common.Address
	lastReceivedCheque *Cheque
}
```

One option is to move the accounting responsibilities from ```Swap``` to a new component (from now on ```Accounting```), introduce it as a new member of the ```Peer``` struct and add a new collaborator on which we can delegate the payment processing. This collaborator (from now on ```SwarmPayments```) will provide access to the supported payment modules, being Swarm one of such modules. This design decouples the accounting from the payment processing. We refer to the concrete payment module implementations as a ```PaymentProcessor```s.

```golang
// Peer is a devp2p peer for the Swap protocol
type Peer struct {
	*protocols.Peer
	accounting         *Accounting
	payments           *SwarmPayments
	backend            contract.Backend
	beneficiary        common.Address
	contractAddress    common.Address
	lastReceivedCheque *Cheque
}
```

The ```payments``` member of the ```Peer``` struct holds the ```SwarmPayments``` component described previously, which is responsible to hold the particular ```PaymentProcessor``` implementations supported by the node and a mapping of:

* Peer (beneficiary) addressess.
* The currency to use.
* The ```PaymentProcessor``` negotiated during the handshake for the beneficiary.

The use (if required) of a price oracle will be handled internally by the ```PaymentProcessor```.

The ```Cheque```and ```ChequeParams``` defined in ```swap/types.go``` should be made more general to allow ```PaymentProcessor```s to generate the required data structures for the specific payment implementation (e.g. Balance Proof, in the case of payment channels). The current implementations of ```Cheque``` and ```ChequeParams``` should be part of the SWAP ```PaymentProcessor```. For clarity they could be renamed to ```Payment``` and ```PaymentParams```, respectively.

```golang
// PaymentParams encapsulate all payment parameters
type PaymentParams struct {
	Contract    common.Address // address of chequebook, needed to avoid cross-contract submission
	Beneficiary common.Address // address of the beneficiary, the contract which will redeem the cheque
	Serial      uint64         // monotonically increasing serial number
	Amount      uint64         // cumulative amount of the cheque in currency
	Honey       uint64         // amount of honey which resulted in the cumulative currency difference
	Timeout     uint64         // timeout for cashing in
}

// Payment encapsulates the parameters and the signature
type Payment struct {
	PaymentParams
	Sig []byte // signature Sign(Keccak256(PaymentParams), prvKey)
}
```

Upon connection and during the handshake, each peer should indicate its supported ```PaymentProcessor```s, being the SWAP ```PaymentProcessor``` the default and fallback payment method to use. The ```PaymentProcessor``` implementation negotiated during the handshake with a given Peer will be registered in the  ```SwarmPayments``` component. To support multiple payment methods this information could be stored in a map where the key will be each beneficiary address, and the value a list of supported ```PaymentProcessor```s:

```golang
// SwarmPayments registers the negotiated payment processors for each peer plus the default payment processor
type SwarmPayments struct {
    PaymentProcessors        map[common.Address][]PaymentProcessor // payment processors negotiated with each peer during handshake 
    DefaultPaymentProcessor  SwapPaymentProcessor                  // Swap PaymentProcessor implementation used as the default payment method
}

// PaymentProcessor is the general payment processor interface
type PaymentProcessor interface {
    params() PaymentProcessorParams
    pay(amount int64, beneficiary interface{}) error
}

/*
PaymentProcessorParams is the common interface for the parameters of a given PaymentProcessor. At least it should allow to query the params for the currency to be used by the PaymentProcessor.
*/
type PaymentProcessorParams interface {
    currency() string
}

/*
As an example, we can define a TokenPaymentProcessorParams implementation of the PaymentProcessorParams interface with the specific parameters needed by a TokenPaymentProcessorParams
*/
type TokenPaymentProcessorParams struct {
    TokenName       string
    TokenAddress    common.Address
    PriceOracle     common.Address
}

func (p TokenPaymentProcessorParams) currency() string {
    return p.TokenName
}
```

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The current Swap implementation uses Ether to settle debts and requires interactions with the chequebook smart contract. The settlement process is tightly coupled with the Swarm node, making hard to support other currencies besides Ether or other settlement methods such as payment channels. Moreover, this coupling tights Swarm to Ethereum-like Blockchains, impeding other Blockchain solutions to benefit from the integration of Swarm as a distributed storage solution. Several options were considered to decouple the payments technology to use from Swarm:

* Introduce ERC20 support directly into the chequebook smart contract: It seems feasible to follow this path, however for each new token to be supported a new chequebook needs to be deployed or multiple token support needs to be introduced to the chequebook. While this is possible, it might introduce unwanted complexity to the SWAP chequebook and not enough flexibility to support other means of payment.
* Introduce support for payment channels directly into the chequebook smart contract: This idea requires an additional level of abstraction for the cheques and the chequebook. The chequebook smart contract should be modified to directly interact with different on-chain payment mechanisms. In the case of payment channel networks cheques should be generalized to allow modeling Balance Proof. The interaction between the chequebook and the payment channel network will occur during the on-chain settlement when the chequebook smart contract should send the Balance Proof to the payment channel smart contract being used. As with the previous approach, this requires several changes to the SWAP chequebook smart contract. For every payment system to be supported a different chequebook should be designed. Having a single chequebook to handle multiple payment systems will result in a smart contract too difficult to maintain and keep secure.
* Completely replace chequebook by a different payment mechanism: this option is the least flexible of all since it does not solve the problem at all, it only changes the coupling with a given technology (chequebook) for another. Additionally, it could hurt the Swarm network, forcing the appearance of multiple subnetworks, each one handling its payment mechanism, a situation that still could happen with the current Swarm design.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
To preserve compatibility the chequebook smart contract will be the first implementation of the payment module interface. This will allow nodes willing to operate with Swarm as they do today. This SWIP does not introduce other backwards incompatibilities if implemented before the incentivized testnet goes live. If implemented after this time, further research must be performed to assess possible backward incompatibility and how to deal with it.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->

No test cases for this SWIP are provided at this moment.

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->

No implementation for this SWIP is provided at this moment.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
