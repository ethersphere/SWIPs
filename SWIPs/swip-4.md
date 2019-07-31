---
SWIP: 4
Title: Generic payment module
Author: Aron Fischer <Aron@ethswarm.org>, Rinke Hendriksen <rinke@ethswarm.org>, Vojtech Simetka <vojtech@iovlabs.org>
Discussions-to: URL will be provided 
Status: Draft
Type: Standards track
Category: Core
Created: 31-07-2019
---

## Simple summary
This SWIP proposes to decouple the accounting for services provided via SWARM with the actual handling of the payment. A generic payment module will be defined as an interface for handling the payments; the chequebook will be the first implementation of this interface. Doing this will pave the way for enabling other currencies to define their implementation of the payment module, which will increase the resilience of the SWARM network as well as increase the user-base of SWARM. 
## Abstract 
A payment module is responsible for handling payments. A minimal payment module accepts a price (in honey), converts this price to a currency via an agreed-upon price oracle, sends the payment and returns when the payment is successful. Making it clear in the code that this is the minimum expected from a payment module will both increase the readability and audibility of the SWARM source code, but will also make it easier for other payment methods to implement this interface, hereby allowing users to choose how they want to settle their payments, which increases the resilience of the network and enlarges the potential user base. 
## Motivation
Currently, SWARM is implementing the chequebook contract (base currency: Ether) to allow nodes to receive payments without doing on-chain transactions. While the chequebook contract is beautiful in its simplicity, it is expected that users of the SWARM might prefer a different way of compensation for their service performed. Nodes might want to receive Ether via a different 2nd layer payment solution (e.g. Raiden), they might want to be compensated with a different currency (e.g. an ERC20 token) or they might want to settle their payment using a different blockchain. Allowing the network to be flexible in this way will make the network more resilient (i.e. if one payment module fails, others might still work) and it will make SWARM attractive to a wider user-base by allowing nodes to pay in the currency of their preference. This SWIP is not about implementing multiple payment modules. Instead, it is a proposal for a minimal interface needed for any payment solution to be compatible with SWARM and implementing the chequebook in such a way that it reflects this interface. 

## Specification
* The payment module accepts an amount (in honey) and a recipient
* The payment module is responsible for:
* Querying the agreed-upon price oracle with the recipient
* Sending the recipient a payment
* Returning true when the payment was successful 
* The payment module references a type, version and base currency 
* The payment module optionally exposes other methods such as querying balances, topping up balances or sending payments (outside of SWARM). 

## Rationale
To be defined
## Backwards Compatibility 
This SWIP is backward compatible, as nodes that don't give any preference will be considered to prefer the default currency with default oracle and default payout mechanism.
## Test Cases 
Not currently defined
## Implementations:
Not currently defined
Copyright Waiver: Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
