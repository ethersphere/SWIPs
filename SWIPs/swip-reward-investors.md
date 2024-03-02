---
SWIP: <to be assigned>
title: Reward Investors
author: Joshua Pritikin (@jpritikin)
discussions-to: https://discord.com/channels/799027393297514537/808329804268699678
status: Draft
type: Core
created: 2024-03-02
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->
Make the BZZ token appreciate in value to reward early investors.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->
A short (~200 word) description of the technical issue being addressed.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->
Under the current rules ([BZZ Tokenomics, Oct 25, 2021](https://medium.com/ethereum-swarm/swarm-tokenomics-91254cd5adf)), the BZZ token may not appreciate value. Some activities require purchasing BZZ:
- New node operators need to make a minimum deposit.
- Data archivists need to buy BZZ to purchase postage stamps.
- Data users need to buy miniscule amounts of BZZ to [pay for bandwidth](https://blog.ethswarm.org/foundation/2021/understanding-swarms-bandwidth-incentives/).

Other parties are natural sellers of BZZ:
- Node operators sell BZZ to pay for electricity and hardware.
- [Investors](https://cryptorank.io/ico/swarm) may like to cash out their investment.

Swarm had historically ignored the economics of BZZ because it was more important to get the technology to work. Now that the technology is on the cusp of working, investors should be rewarded.

One purpose of the BZZ token was to [reward early adopters](https://blog.ethswarm.org/foundation/2021/swarm-is-airdropping-1000000-bzz/). By this metric, BZZ is a failure. Sold to the public for 1.92 DAI on June 2021, the token is worth about 0.5 DAI as of Mar 2024. Investors deserve a return on investment. If the price of BZZ could be linked to network usage then investors would be incentivized to promote the network.

It's not an apples-to-apples comparison, but Filecoin has a market cap of about 4.5 billion while BZZ is only 34 million (Mar 2024). That's a difference of more than two orders of magnitude.

## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->

Call `shutDown()` on the bonding curve contract (0x4F32Ab778e85C4aD0CEad54f8f82F5Ee74d46904). Move the DAI to a Swarm Foundation owned Uniswap v2 DAI-BZZ pool.

Send 10% of the BZZ stamp payment to the Swarm Foundation owned Uniswap v2 DAI-BZZ pool before sending the remainder to the redistribution lottery.

Eventually the node operator minimum deposit will need to be reduced to compensate for the increase in the value of BZZ.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The choice of 10% going to investors is arbitrary. The community can decide on the most suitable burn rate.

Stamp payments are a great place to add this fee. Stamp buyers are expressing an intention to store data on the network which is the behavior that is synonymous with the success of the network.

To allow the value of BZZ to appreciate in proportional to demand, the bonding curve needs to be shutdown. The bonding curve imposes a non-linear function between BZZ and the price of BZZ. If the bond curve is kept active, it will impose a distorting effect on price discovery. See [here](https://medium.com/ethereum-swarm/swarm-and-its-bzzaar-bonding-curve-ac2fa9889914) for background.

To ensures that BZZ retains on-chain liquidity, the DAI in the bond curve and the fee on stamp payments will be deposited into to a Swarm Foundation owned Uniswap v2 DAI-BZZ pool. This concept has already been proven by [Maker's smart burn engine](https://makerburn.com/#/buyback).

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->
No backwards compatibility issues are anticipated.

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
*Pending*

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
*Pending*

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
