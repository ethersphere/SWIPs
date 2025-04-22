---
SWIP: 35
title: Negative Incentives (Epic)
author: Viktor Trón <viktor@ethswarm.org> (@zelig)
discussions-to: discord SWIP channel, https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Core
created: 2025-03-09
---

# Advanced storage guarantees 
<!-- TOC -->
<!-- /TOC -->
## Abstract

This SWIP proposes an entire epic about adding further layers of incentives to the basic positive incentives in Swarm. By adopting this SWIP, swarm will offer a wider range of constructions for its users to secure the persistance of chunks and their metadata and at the same time allow a low-barrier-of-entry service for node operators.[^55] 

[^55]: Allowing for a broader range of hardware specs that operators can run their client software on.

## Motivation

The current storage incentive system has a few shortcomings mainly related to the following areas:
1.  **parameters of on-chain stamp purchase** --
Users typically have a hard time interpreting the transaction parameters required when buying a batch of postage stamps on the blockchain. Users need a clear interpretation of
	- insured amount 
	- insured period
	- mutability
1. **guarantees of durability and  retrievability** --
Users seek a wider range of options regarding the security guarentees for their uploaded content. Users and operators must be given adequate tooling for
	- upload to cache only
	- storage insurance
	- community-maintained data (global pinning)
	- cheap cold storage
2. **privacy** --
Postage stamps self-signed by the uploader as well as using a single batch per session leak information which weaken plausible deniability and open the door for targetted withholding or ransome attacks. Stamps leak
	- identity of uploader
	- co-constituency of chunks (which chunks belong together in a file, directory or upload session)

#### Interpreting postage batch parameters 

Lack of clarity regarding the interpretation of batch parameters has led to misguided expectations about the expiry of persistance guarantees as well as about the available amount insured. Mutability is also confusing users when it came to the reuse of postage slots. 

#### Privacy 

The signature on a stamp serves as *proof of relevance*[^2] when it comes to evidence submitted as part of the claim transaction. As long as stamps are self-signed by the uploader, the batch owner can be identified as the originator of the data for 3rd parties. 

[^2]: The validation of a batch owner associating a chunk with a postage batch serves to proof that someone is indeed willing to pay for the data in question.

Somewhat independently of this, the fact that same-owner batches are used when uploading a file, the chunks uploaded during one session leak co-constituency, i.e., which chunks are likely to constitute one file, directory or belong together in a single upload session. This overshadows somewhat Swarm's otherwise rather strong privacy claims.


#### Insurance

The storage incentives currently present in Swarm use an on-chain game which orchestrates the fair redistribution of postage payments to storers, thereby providing *positive incentivisation* at a collective level. Such a system, however, is suspect to *the tragedy of the commons* problem in that disappearing content will have no negative consequence to storers. Any particular chunk missing currently does not impose any punitive measures on the one or several storers who explicitly promised to store the chunk.[^6]

[^6]: Alternatively, such an insurance system can be provided as an insurance market place where the availability must be guaranteed through dynamically adopted to???

#### Global pinning, 

It is up to the insurer node to decide how they guarantee the integrity of the entire set of chunks available from any particular root hash reference. They got a few options where they keep the contents: 
- keep the content locally pinned under the root 
- keep the content stored on swarm.[^15] 
- use other external services like Filecoin, Arweave or Storj.

[^15]: In this case, the content may be reencrypted and protected with erasure codes and data avaiability sampling 

Swarm would benefit from the availability of such options either with  or without retrievability guarantees (*warm* vs *cold* storage). 

#### Free uplods to cache

Messages of real-time chat or notifications or frequently updated indexes without history are just obvious examples of data that are meant to be short-lived. Since, in these cases, preservation beyond temporary caching is unnecessary, paying for postage is wasteful. 
Such content meant not to be stored should just be be uploadable without a postage stamp and put to the cache and not to the reserve. In order to mitigate targetted attacks, bandwidth compensation must be adapted to express as well as transfer the cost between uploader and  storer in case postage stamps  are not able to.

## Solution

### Negative incentives
The lack of individual accountability makes Swarm's storage incentivisation limited as a security measure against data loss. Introducing non-compensatory insurance, on the other hand, adds an additional layer of *negative incentives*. In other words, the threat of punitive measures (losing the stake deposited against foul play) is introduced
in order to compell storage providers to ensure reliability of data retention and/or prompt retrievability for users. 

### Stampless uploads to cache

When expired chunks are removed from a node's reserve, they are not deleted but rather, are put to the *cache*[^5]. This suggests that chunks uploaded without a stamp should also start there (see [SWIP-36](https://github.com/ethersphere/SWIPs/pull/70)).

[^5]: so that popular content can bring bandwidth revenue even if no longer available for storage incentive rewards.

<!-- #### Bookkeeping
On top of all this: if one batch is used per upload session, bookkeeping of "what chunk to link with what batch index" is less relevant.: In fact, fit matters solely in order to save money in case the file is reuploaded.
 -->


### Stamp mixing 

Privacy issues related to signing  stamps  can be solved by introducing a construction we call *$tumbler (=stamp tumbler)* which, similarly to a currency *mixer*, stamp the chunks delegated to them by the uploader of the chunks, thereby obfuscating their identity.

This delegation is most efficient if obfuscation is  done 
in the neighbourhood designated by the *secondary chunk address* that is different from the  primary address which in turn designates the neighbourhood that the chunk is retrievable from. 

## Rationale


#### Contractual terms of storage 

The most natural way to pay for storage is to interpret it as *fixed period capacity rent* and expect parameters to be the *amount of capacity* and the *time period* (5Gb from no until a year from now) as the unit price of storage (per chunk, per block) already suggests. However, for most, a deal (through an act of batch purchase) entails that the counterparty service can be kept to the terms *precisely*: i.e., you bought a fixed *quota* (amount of bytes, 5 million) for a fixed period (duration starting now, expiring after a fixed period of a year). Experience shows that any deviation from this expectation comes as a surprise for the user. 



##### Mutability and Incentive to prevent double signing 

Postage batches primarily serve  to enforce the uniform distribution of chunk addresses, and thereby achieve a balanced load of storage across the network. This is solved by partitioning the `2^b` storage slots of a batch (of depth `b`) into `2^u` equal-sized buckets (of depth `2^{b-u}`). The stamp contains the index of the slot composed of a bucket index and a within-bucket index. Batches also  impose a constraint on the stamps' validity: the owner must not assign more than one chunk to the same postage slot.[^11] 

[^11]: Meaning that doing so will invalidate an immutable batch, make retrievals potentially fail in case the single chunk is not well-defined. 

Double signing of a slot (though detectable[^17]) will only be avoided if the owner is incentivised to avoid it. Originally, since uploaders are themselves the owners of the batch they use for stamping, they are naturally incentivised to avoid double signing which could threaten retrievability of the content that they upload. If stamping is delegated to a stamp tumbler, double signing must be avoided through negative incentives (the threat of losing their stake).


[^17]: The number of buckets must at all times be greater than the number of neighbourhoods, so each bucket belong in a neighbourhood, i.e.,  all the chunks assigned to a slot in a  particular bucket are stored within the neighbourhood (as the nodes' area of responsibility), which guarantees that the double signing of a slot is detectable by any node in the neighbourhood.


##### Postage batch utilisation

The quota represented by the set of storage slots of a batch is evenly distributed in a number of buckets, as it also serves to force balanced use across neighbourhoods. 
Even though the most effecient utilisation of a batch is if stamps can max out each bucket, already a single bucket filled up will make an immutable batch practically not usable since, as it has no slots available in the bucket filled, it cannot be guaranteed to stamp just any chunk.[^31]

[^31] Incomplete utilisation can be counteracted with making sure you can reassign the 
'same' chunk to another bucket by either [mining]() or having availability guaranteed by a constant influx of chunks (see section below). On the other hand, with the variance limited, the actual discount can also be made explicit in the current system, and, therefore [user expectations of their quota purchased that is suggested bt the batch depth must be modulated by factoring in the packed address chunks needed to represent files, and the manifest nodes to serve as directories, erasure code parities  
 
Instead the volume called [*effective utilisation*](https://www.overleaf.com/4919957411cgrncysjqrmv#3b42ca) must be given to users.
The effective batch  utilisation rate increases with overall volume implying a natural overhead for small batches[^1] 

[^1]: or more naturally put, there is an incerasing discount rate when purchasing larger volumes.


##### Storage period and expiry

On the other hand, the redistribution  game is a *probabilistic outpayment scheme* in the sense that instead of paying -- on each game all the contributors for a recurring fixed proportion of used storage we just pay out the entire reward pot for the period to a random winner at every game. This allows for central pricing sensitive to supply and offers automatic and optimal price discovery as long as we assume a liquid market of operators providing storage. As a consequence, users do not need to speculate on the future price of storage at all, they can just trust the oracle to discover the best price of rent. Users provide the compensation for their quota as a "hot wallet" from which the price of rent is automatically deduced. The postage batch is such a construct: it serves as a hot wallet. The expiry is defined as the onset of insolvency, i.e., whenever the balance goes to zero. 

Let `s` and `e` be the start and end date of storage, period is `e-s` in units used in the oracle price. Let us propose the following scenario: owner `A` buys a postage batch `B` for `2^C` chunks and escrows amount `D` onto `B`. Now if we assume that price of storage per chunk per time unit at `s` is `p_s`, then we can guess that the expiry is `e'<=e` iff `D/(2^C*p_s)` then A assumes price will decrease. However, if the average price increases, then the effective period ends d units sooner; if d is the smallest number such that the average price over the period `[s, e]` the cumulative rent goes above D `\Sum_{i=s}^e p_i*2^C >= D.`

In other words, increasing rent price may lead to earlier expiry. This can only be counteracted by having more funds on the batch, so users effectively pay for security (*upload and disappear experience*). If the intended expiry passes without the batch running out of funds, then storage just continues, or alternatively all funds remaining on the batch can be used for more storage service.[^12]

[^12]: Using the current balance to create another batch (potenitally different size, period and owner) is currently not supported but it should be.

Due either to the increasing price of BZZ or to the organic decrease of the cost of storage,  the value held on a batch may increase potentially at a rate beyond what is countered by rent deduced at every game. This eventuality could quietly implement **Arweave's promise** *("pay once, store forever")*. 
The differences are:

1. the construct is not promised to happen with just any amount, 
2. with the right amount it happens even if not planned,
3. it is just one of the construction offered,
4. the funds on a batch can be used to seed fund a new batch and store other things 



In what follows we argue that instead of having fixed-quota-for-fixed-period deals as a primitive, Swarm will provide these as a solution through further smart contracts on top of the postage batches. 

#### Availability of storage quota

When users commit to a storage term, they usually have a use in mind, they want to commit to storing a particular (set of) file(s) for a particular period (importance). While they understand that quota are quantised in a way that might not match their immediate need, and will leave them with leftover storage slots, a surplus.[^22]
On the other hand, uploaders prefer immediate availability of any quota for any period.

[^22]:  If users had a deal for a price for an amount for a period, leftover could be viewed as an opportunity to use the prenegotiated deal in the future when prices are higher. However, without such a deal, users have a hard time interpreting leftover quota for  anything else than waste.

If insurance providers themselves are to secure the quota using their own postage batch, then the surplus is all the more likely to be filled. Completely filled batches result in a lower unit prices of storage. 

The stumbler construction is virtually a stamp mixer in that it blinds any originator address's association with chunks and also obfuscates their co-constituency (belonging together of a set of chunks).
Since association by postage batch was always the wierd anomaly, solving it is a major improvement in swarm's privacy.


#### Distribution of responsibility: providers in the overlay address space
  
A liquid quota market is best provided by a *decentralised service network*: served by swarm nodes themselves. Ideally providers will have a density not too dissimilar to the nodes providing the reserve, but the system also needs to be prepared to provide service in the case of a lot (a couple of orders of magnitude) fewer or more nodes. This is taken care of by the swear contract, which maintains a balanced set of providers according to *smart neighbourhood management* ([described in a separate SWIP (SWIP-39)](https://github.com/ethersphere/SWIPs/pull/74))

A *withholding attack* is when an insurer is grieving[^7] consumers by only providing the chunk if challenged. If a chunk is to be retrievable from a different neighbourhood (belong to the reserve based on the chunk's address) than the one that insures it, then the onus of retrievability falls on nodes that are independent in terms of operation.

[^7]: a grieving attack is where the adversary is able to make their victim(s) suffer losses, time or other inconvenience without them gaining.

We propose that chunks have a *secondary address*, defined as the (legacy Keccak) hash of the primary chunk address with or without the first bit flipped (bitwise XOR the first byte with 0x80). This will place roughly one in every 256 chunk into the opposite side of the network which still keeps the balance of storage.

So when nodes swear on to provide insurance (or insurance/availability level X service), they register their address with a stake on a (the?) staking contract.  It is important that providers should be distributed evenly in neighbourhoods, ideally of the same size as that dictated by the reserve. 

Maybe all full nodes are providers by default. This is very useful because when a node provides the service, they expect chunks to their neighbourhood by the secondary address (the hash of the BMT address) of a CAC --- from now a *new chunk type*. Once they receive it, they must provide the uploader with a storage receipt as an acknowledgment which they send back to the originator using the same route (backwarding).

Some insurers may just take on the task of keeping the chunks retrieveable. For this, they need to keep a postage batch alive that issued the stamp of the chunk, throughout the period matching the requirement in the chunk request.

They can keep the chunk in this batch retrieveable by regularly topping up the batch if needed. Since the hashes are uniformly distributed, this batch is expected to be naturally balanced as it should be. So it is quite realistic for the node to be able to fill it. 
The request will reference a specified expiry and the batch needs to have a balance at least until that date. 


### Insurance

#### Punitive measures

Unlike in the case of bandwidth incentives where retrievals are immediately accounted and settled, long-term storage guarantees are promissory in nature and do not allow the instant gratification of forwarding/backwarding. It is only after the end of its validity that one can check if a promise has been kept.
Nodes wanting to sell storage space should have a stake verified and locked-in at the time of making their promise. This implies that nodes need to register in advance, agreeing to the contract by placing a security deposit. Once registered, a node may start selling storage promises. While their registration is active, if they are found to have lost a chunk that was covered by their promise, they stand to lose their deposit.


Particular attention is required in the design of the incentive system to make sure that failure to store every last bit promised is not only unprofitable but outright catastrophic to the insurer.[^16] 

[^16]: Merely losing reputation is not sufficient as a
deterrent against foul play in these instances: since new nodes must be allowed to provide services right away, cheaters could just resort to new identities and keep selling (empty) storage promises.


Now we will elaborate on a class of incentive schemes we call
"swap, swear, and swindle" due to the basic components:

- *SWAP*: The swarm accounting protocol makes sure that peers exchange chunks
and receipts, triggering swap accounting and settlement. This must be used for payment 
in order for true uploaders to remain anonymous.
- *SWEAR*: Storer nodes register with their stake and make an implicit promise to store the chunks whose secondary address falls within their area of responsibility.
- *SWINDLE* -- Storers can be challanged on their promise through an on-chain litigation process.

In case an escrow is used, the reward is vested over a period of 
the storer is only awarded the locked funds if they are able
to provide *proof of entitlement*. This procedure is analogous to the postage
stamp redistribution game. Out-payments conditional on proofs of custody can be implemented in a way similar to the reserve redistribution game.

The SWEAR contract allows nodes to register their public key to become
accountable participants in the swarm. Registration involves sending
the deposit to the SWEAR contract, which serves as collateral in case
the terms that registered nodes "swear" to keep are violated (i.e. nodes
do not keep their promise to store). The registration is open-ended  Users of Swarm should be able to count on the loss of deposit as
a disincentive against foul play for as long as the insurer node has open commitments.
Therefore, even a well-performing Swarm node is only eligible to reclaim their
deposit after all their commitments are closed or taken over by new nodes.

#### Challenge

If a node fails to observe the rules of the Swarm they swear to keep, they are to face
the enforcement of punitive measures. This must be preceded by an on-chain litigation
procedure called *SWINDLE (Secured With INsurance Deposit Litigation and Escrow)*.
When a user attempts to retrieve insured content and fails to find a
chunk, they can report the loss by submitting a challenge analogously to a court
case in which the insurers the defendants who are guilty until proven innocent. Similarly to a court procedure, public litigation on the blockchain should be a last resort when the rules have been abused despite the deterrents and positive incentives.
The challenge takes the form of a transaction sent to the SWINDLE
contract, in which the challenger presents evidence  implicating a particular node having made a promise to insure that particular chunk for a period that has not ended yet. 

Any node is allowed to send a challenge for a chunk as long as
they have evidence available to back the claim.  The validity of the challenge as well as its refutation must be easily verifiable by the contract. The contract
verifies challenge by checking the following conditions:
1. *covered* -- The chunk in question is (implicitly) covered by the insurance.
1. *authentic* -- The insurance was signed with the key the node registered with.
2. *active* -- The expiry date of the insurance has not passed.
3. *funded* -- Sufficient funds are sent in the transaction[^13] 


[^13]: in order to compensate the insurer for uploading the chunk in case of a refuted challenge. The payment sent with the transaction is to disincentivise frivolous litigation,
i.e. bombarding the blockchain with bogus challenges and potentially
causing a DoS attack.

Upon succcessful challenge,   an event is logged by the contract to notify the accused of their obligation to refute. The challenge remains open for a fixed time period, the end of which is the deadline for refuting the challenge. Refutation itself consists of uploading the entire chunk. This (1) serves as 3rd party verifiable proof that they keep their promise as well as (2) makes the disputed data available to nodes that require it.
Upon successful refutation,  the challenge is cleared from the blockchain state. While the stake of the accused node remains untouched, the cost of uploading
the chunk must be borne by the challenger and is paid from the deposit. 


If the deadline passes without successful refutation of the challenge,
then the charge is regarded as proven and the case enters into the en-
forcement stage. Nodes that are proven guilty of losing a chunk must lose
their stake. Enforcement is guaranteed to be successful by the fact
that nodes' stakes are kept locked up (in the SWEAR contract).
If, on litigation, it turns out that a chunk (that was covered)
was lost, the deposit must be at least partly burned.[^4] 

[^4]: Note that this is necessary because, if penalties were paid out as compensation, it would provide an avenue of early exit for a registered node by "losing" bogus chunks that had been challenged on by colluding users.

#### Incentivising promissory services
Delayed payments without locked funds leave storers vulnerable to
non-payment. Advance payments (i.e. payments settled at the time of
contracting, not after the storage period ends) on the other hand, leave
the buyers vulnerable to cheating, since after collecting more from sales than their stake, they can afford losing it and they still walk away with  a profit even without doing any work.
Stake must be set high enough so this attack is no longer economical.
When paying for the insurance, the  amount for the entire period must be paid in full to eliminate the insurer’s distrust due to potential insolvency. This amount is then released in installments on the condition that the node provides a proof of custody.



## Specification




## Evaluation

Even though treating the postage batch as a hot wallet has quite a few advantages, the proposed insurance scheme will bring improvement in several areas:

  - **privacy**:
    - effective *stamp mixing*
    - true *permissionlessness* and *plausible deniability* of uploads, i.e., complete obfuscation of the chunk originator
    - no leakage of co-constituency (infrmation that chunks belong to the same file)
  - **precision**:
    - exact period of data retention
    - exact amount: what you insure is what you pay for.
  - **predictability**: 
    - easier to understand parameters yet primitives are pure
  - **preparedness**:  
    - real *upload and disappear* experience (no need to be around to secure)
    - immediate availability of uploads for any amount/period without wait or prepurchase
  - **pricing**:
  	- free upload into cache
    - easier to understand pricing
    - potentially complete utilisation of batches leading to cheaper prices or easier to coordinate subsidies 
    - prepurchase (keeping batches open) makes sense (speculation on price deal)
    - moderate future price speculation needed
    - 'pay once, store forever' now available 
    - no benefit from rent price drop
  - **portability**:
    - only providers need to keep track of batches and batch utilisation
    - implicit storage receipts, 

## Implementation notes and roadmap

Due to the complexity of this epic, components will be  discussed in separate SWIPs (together implementation notes, test cases, tooling support):
- stampless upload - [SWIP-36](https://github.com/ethersphere/SWIPs/pull/70)
- smart neighbourhood management - [SWIP-39](https://github.com/ethersphere/SWIPs/pull/74)
- global pinning, incentives, notifications
- stamp mixing, requests, receipts and address indexes

The  will be detailed in the individual SWIPs for the components.

### Backward compatibility 

Due to secondary addresses, the new chunktype we define, as well as  parameters relating to insurance requirements within a core protocol, implementing this swip will break the **backard compatibility** with earlier vrsik .

## Copyright


Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
