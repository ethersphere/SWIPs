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

## Abstract

This SWIP proposes an entire epic about adding further layers of incentives to the basic positive incentives in Swarm. By adopting the SWIP, swarm will offer a wider range of constructions for its users to secure the persistance of chunks and their metadata and at the same time allow a low barrier of entry service that node operators with extra storage or bzz future providers are able to increase their revenue with.

## Motivation

The current storage incentive system has a few shortcomings mainly related to the problem that postage batches are difficult to interpret. This interpretation problem leads to quite a bit of misunderstanding and misguided (also potentially failing) expectations regarding both the stored amount and the storage period. 

These issues are coupled with known privacy concerns regarding the shared ownership of chunks that are transparent to 3rd parties. Effectively information about the publisher as well as the chunks constituting the publication leak the system, somewhat overshadowing the otherwise rather strong privacy claims in swarm.

The latter issue is solved if the stamps on individual chunks are signed by other nodes. We will introduce *stamp mixer service* of sorts in a way that the system will not lose its capacity to prevent doubly sold postage slots.[^3]

[^3]: 

On top of all this: if batches are used one per upload session etc, bookkeeping of "what chunk to link with what batch index" is less relevant; in fact, it matters solely in order to save money in case the file is reuploaded.[^4]
In this SWIP we introduce a scheme in which uploads are not necessarily using a stamp; even though uploaders can purchase storage for arbitrary long periods.
No per-chunk metadata needs recording and made available in this case, meaning that the end-user case no longer raises portability concerns.

Last, but not least, enforcing payments for each upload does not really make sense: firstly, users had some difficulty to grasp that given the free-tier for bandwidth inentives allowing free downlad and upload with throttled throughput, how come they need to pay for the storage. This problem was most obvious for really short-lived messages that are used in chat or notifications. Since, in these cases, preservation is not meaningful or even actively not desired, paying for postage sounds not only a unnecessary but outright wasteful. Secondly, the fact that expired chunks are not deleted but are put to the *cache*[^5] poses the question how come there is no direct entry to it. 
This anomaly can be solved if we introduce free uploads, i.e., uploading chunks to Swarm without a postage stamp. 


[^5]: so that popular content can bring bandwidth revenue even if no longer available for storage inecntive rewards.

## Solution

### Free uploads to cache

Just like before, the swap protocol offers free (throttled) as well as paid (max throughput) service through cheques, now, upload also offers free (chunks are put to cache and purged if necessary) as well as paid (chunk put to the reserve until stamp expires) service using postage stamps.


### Stamp mixing 

#### Incentive to prevent double signing 

Postage batches primarily serve  to enforce the uniform distribution of chunks, and thereby achieve a balanced load of storage across the network. As part of the solution, a user must not double spend, i.e., assign more than one chunk to the same postage slot. Originally, this is guaranteed by the fact that the owner is interested in not being caught since that may lead to the loss of their own data, i.e.,  data that they themselves had uploaded. If a stamp mixer of sorts is introduced, we must make sure that issuers cannot use the same slots: which happens to be the case if all chunks are insured with *negative incentives* (punitive measures).

#### Contractual terms of storage 

The most natural way to pay for storage is by the *amount* and *time period*. Surely, the unit price of storage (per chunk, per block) already suggests this. However, for most, a deal (through an act of purchase) entails that the counterparty service can be kept to the terms *precisely*: i.e., you bought a fixed quota (amount of bytes) for a fixed period (duration starting now, expiring after a fixed period or on a fixed datte). Experience shows that any deviation from this expectation comes as a surprise for the user. 

The current primitive of storage compensation, the postage batch falls short on these. The primary reason is that it was designed with the simplicity in mind pertaining to the intergration into the redistribution system. 

##### Postage batch utilisation

The quota encoded in the batch's slots is not neutral: as per the previous section, it also serves to force balanced use across neighbourhoods: maxing out the subquota for one neighbourhood implies maxing out the same subquota for each neighbourhood which requires no variance across NH-s; so the effective batch  utilisation rate increases with overall volume, in other words there is a natural overhead for small batches[^1] 

[^1]: or more naturally put, there is wholesale bulk discount.

Incomplete utilisation can be counteracted with making sure you can rearrange between neighbourhoods by either [mining]() or having availability guaranteed by a constant influx of chunks (see section below). On the other hand, with the variance limited, the actual discount can also be made explicit in the current system and therefore [user expectations of their quota can bee managed](https://www.overleaf.com/4919957411cgrncysjqrmv#3b42ca).

#### Storage period and expiry

On the other hand, the redistribution  game is a *probabilistic outpayment scheme* in the sense that instead of paying -- on each game all the contributors for a recurring fixed proportion of used storage we just pay out the entire reward pot for the period to a random winner at every game. This allows for central pricing sensitive to supply and offers automatic and optimal price discovery as long as we assume a liquid market of operators providing storage. As a consequence, users do not need to speculate on the future price of storage at all, they can just trust the oracle to discover the best price of rent. Users provide the compensation for their quota as a "hot wallet" from which the price of rent is automatically deduced. The postage batch is such a construct: it serves as a hot wallet. The expiry is defined as the onset of insolvency, i.e., whenever the balance goes to zero. 

Let `s` and `e` be the start and end data of storage, period is `e-s` in units used in the oracle price. Let us propose the following scenario: owner `A` buys a postage batch `B` for `2^C` chunks and escrows amount `D` onto `B`. Now if we assume that price of storage per chunk per time unit at `s` is `p_s`, then we can guess that the expiry is `e'<=e` iff `D/(2^C*p_s)` then A assumes price will decrease. However, if the average price increases, then the effective period ends d units sooner if d is the smallest number such that the average price over the period [s, e] the cumulative rent goes above D `\Sum_{i=s}^e p_i*2^C >= D.`

In other words, increasing rent price may lead to earlier expiry. This can only be counteracted by having more funds on the batch, so users effectively pay for security (*upload and disappear experience*). After the intended expiry passes, all funds remaining on the batch can be used for more storage service.[^2]

[^2]: Using the current balance to create another batch (potenitally different size, period and owner) is currently not supported but should be.

In what follows we argue that instead of having fixed-quota-for-fixed-period deals as a primitive, Swarm will provide these as a solution through further smart contracts on top of the postage batches. 

##### Availability,  liquid market for storage

When users commit to a storage term, they usually have a use in mind, they want to commit to storing a particular (set of) file(s) for a period. While they understand that quota are quantised in an arbitrary way and might not match their immediate need, the surplus will often be considered waste. If users had a deal for a price for an amount for a period, leftover could be viewed as an opportunity to use the prenegotiated deal in the future. However, without such a deal, users have a hard time interpreting leftover quota on the one hand, and they expect immediate availability: a liquid market for both quota and duration. It is therefore crucial that storage providers always have available at any point, any amount for any period.[^1] 

[^1]: Instead of a continuous scale of options, period is guaranteed with an  accuracy of matching expected to decrease exponentially with time.

Upload and disappear experience with certainty can actually be guaranteed to users if storage providers themselves secure quota using their own postage batches. A liquid quota market is best provided by a *decentralised service network*: served by swarm nodes themselves. 

#### Stake providers in the address space

The insurance or availability provider had better not be in the same neighbourhood as the chunk would normally be stored in yet their distribution should be uniform. We argue that the insurance address of the chunk is the legacy Keccak hash of the chunk address H(addr). If the insurance address of the chunk falls exactly into the same neighbourhood as the address (well, the first byte match), then we fall back choosing the bitflip (bitwise XOR with the binary for $0xff$) on the first byte. This will place roughly one in every 256 chunk into the opposite side of the network which still keeps the balance of storage.

So when nodes swear on to provide insurance/availability level X service, they register their address with a stake on a (the?) staking contract.  It is important that providers should be distributed evenly in neighbourhoods, ideally of the same size as that disctated by the reserve. 
Maybe all full nodes are providers by default. This is very useful because
when a node provides the service, they expect chunks to their neighbourhood by the hash of the BMT address of a CAC --- from now a new chunk type. Once they receive it, they 
must provide the uploader with a signed receipt.
Some insurers may just take on the task of keeping the chunks retrieveable. For this, they need to create a postage batch matching the period requirement in the chunk request and eventually sign stamps and send the chunk with the stamp to their destination.

They can keep the chunk in this batch retrieveable by regularly topping up the batch. Since the hashes are uniformly distributed, this batch is expected to be naturally balanced as it should be for the node to be able to realistically fill it. 
The request will reference a specified expiry and the batch need to have a balance at least until that date. 

Due either to the increasing price of BZZ or to the organic decrease of the cost of storage,  the value may increase potentially beyond what is deduced with the rent every game. This eventuality could quietly implement Arweave's promise ("pay once, store forever"), except that you can always stop it and use it to store something else. Surely, the difference is that this is neither promised to happen with any amount in advance nor is the construction enforced.

#### Upload to the reserve:

Insurers can collect and then publish chunks with their own stamp. The batch that they use will be grouping chunks by 
1. H(address); locality of their node address
2. expiry; past request date
3. arrival time of request; 

As long as 3.~is undifferentiating due to a large number of (near) simultaneous requests
1 and 2 will not easily help align identity to chunk or even chunk to chunk.
This is why push-syncing all the chunks in the batch can be delayed: exactly in order to achieve that a larger number of simultaneous requests get published together. Ideally the time of delay coincides with the time of batch completion, i.e., whenever the batch (prepared to support the time until original uploaders want the chunk to be stored) is fully utilised, it is closed and all the chunks are uploaded. The problem is that if the traffic is not great, especially long term storage (more expensive), publishing may need to wait beyond the chunks of the file already disappear from the swarm's cache. These chunks therefore need to be first uploaded with a rather short period just to survive and later maybe also  have their subscription renewed. Such a strategy creates more usage for the short periods which then leads to the ability to fill bigger batches faster and more efficiently: the bigger the batch, the bigger the anonimity set, thus, the better the anonimity that you get. 

In fact this opens up the possibility that livekeepers keep alive batches practically for short time periods representing a unit the others are multiples of, then they can always preserve information about how long the relevant chunks are meant to be stored.

This construction is virtually a stamp mixer in that it blinds any originator address's association with chunks and also obfuscates the belonging together of a set of chunks.
Since association by postage batch was always the wierd anomaly, solving it is a major improvement in swarm's privacy.



#### Insurer:

####  Livekeeper-insurer: 

Even though treating the postage batch as a hot wallet has quite a few advantages, such an insurance scheme bring improvement in several areas:

  - *privacy*:
    - effective *stamp mixing*
    - complete obfuscation (and plausible deniability) of chunk originator
    - no leakage of shared ownership through signature by the same batch owner
  - *precision*:
    - exact period
    - exacy amount 
  - *predictability*: 
    - easier to understand pprimitives
  - *preparedness*:  
    - real *upload and disappear* experience (no need to be around to secure)
    - immediate availability of uploads for any amount/period without wait or prepurchase
  - *pricing*:
    - easier to understand/more pricing
    - potentially complete utilisation of batches leading to cheaper prices or easier to coordinate subsidies 
    - prepurchase (keeping batches open) makes sense (speculation on price deal)
    - moderate future price speculation needed
    - 'pay once, store forever' now available to providers (only)
    - no benefit from rent price drop
  - *portability*:
    - only providers need to keep track of batches and batch utilisation
    - since users got all they need from just knowing that a file/root was insured/kept alive









## Specification

## Rationale

## Backward compatibility 

## Test Cases

## Implementation

## Copyright


Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
