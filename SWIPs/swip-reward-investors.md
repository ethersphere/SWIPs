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

Send 10% of the BZZ stamp payment to the Swarm Foundation owned Uniswap v2 DAI-BZZ pool before sending the remainder to the redistribution lottery.

Eventually the node operator minimum deposit will need to be reduced to compensate for the increase in the value of BZZ.

## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->

The choice of 10% going to investors is arbitrary. The community can decide on the most suitable burn rate.

Stamp payments are a great place to add this fee. Stamp buyers are expressing an intention to store data on the network which is the behavior that is synonymous with the success of the network. Backing BZZ only with DAI loses value to inflation just as USD loses value to inflation. BZZ should be backed by future stamp fees, unlinked from USD.

To ensures that BZZ retains on-chain liquidity, the fee on stamp payments will be deposited into to a Swarm Foundation owned Uniswap v2 DAI-BZZ pool. This concept has already been proven by [Maker's smart burn engine](https://makerburn.com/#/buyback). See [here](https://vote.makerdao.com/polling/QmQmxEZp#poll-detail) for more background. Maker chose Uniswap v2 instead of more modern solutions because it is battle tested and has less attack surface. Uniswap v2 is the simplest way to provide market depth to a free floating token pair.

While on-chain liquidity is a public good, the pool fee should not be so low as to encourage speculation (e.g., 0.01%). Excessive BZZ price volatility is not in the interest of actual users of the Swarm network. Therefore, the Uniswap pool fee should be fairly high, like 0.5%, to increase transaction costs a bit and reduce short-term speculation.

### Legal Analysis

Disclaimer: *The information contained in this section is intended for informational purposes only and does not constitute legal advice. The author is not a licensed attorney and cannot offer legal guidance or representation. Readers should not rely on this information to make decisions regarding any legal matter. It is strongly recommended that you consult with a qualified attorney in your jurisdiction for personalized legal advice specific to your situation. The author does not assume any responsibility for any actions taken or not taken based on the content of this section. The information presented may not be up-to-date or applicable to every situation.*

[The Howey test](https://www.investopedia.com/does-crypto-pass-the-howey-test-8385183) established criteria for whether a transaction qualifies as an investment contract. As of the June 2021 crowdsale, it could be anticipated that BZZ would not appreciate much in value. Developers owned at least 20% of the initial issuance and planned to redeem for DAI to fund development. Node deposits could be anticipated to reduce the supply of BZZ, but this would only matter if the network grew very large. Therefore, BZZ seems to fail the Howey criterion of *expectation of profits*.

This SWIP proposes to change the economic properties of the BZZ token. Supported by revenue coming in from stamp fees, BZZ is expected to appreciate in value. However, the success of BZZ is no longer in the hands of a small team of developers. The Howey criterion of *reliance on the efforts of others* no longer applies. Even more so than Bitcoin, all holders of BZZ are responsible for the success of the network. Software developers, node operators, and postage stamp purchasers contribute value. In addition, BZZ investors contribute value by their implicit belief in the network, and optionally, promoting the network.

## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->

The bonding curve (0x4F32Ab778e85C4aD0CEad54f8f82F5Ee74d46904) imposes a non-linear function between quantity of BZZ issued and the price of BZZ. Keeping the bond curve active and, at the same time, allowing BZZ to trade freely for price discovery, will involve extra arbitrage transactions to keep these markets in synch. See [here](https://medium.com/ethereum-swarm/swarm-and-its-bzzaar-bonding-curve-ac2fa9889914) for background. There is no urgency, but it would be desireable to retire the bonding curve for the following reasons:

- The DAI locked in the bonding curve does not earn any return.
- This idle capital no longer helps much with market depth because the Uniswap market has plenty of depth.
- Extra arbitrage transactions are needed to keep the bonding curve in synch with the free floating price.

The bonding curve has a `shutDown()` function. However, after `shutdown()`, the is no way to retrieve any DAI that is still locked. To both retire the bonding curve and retrieve the DAI will require some careful planning. Here is one solution:

- Let the current BZZ token be called BZZv1 and introduce a new BZZv2 token. BZZv2 trades freely against DAI and has no bonding curve.
- Create a contract BCManager that will issue BZZv2 for deposits of BZZv1.
- BCManager only converts in one direction and BZZv1 is locked in the contract.
- BZZv1 and BZZv2 are both valued equally in the Swarm ecosystem. Both can serve as a node deposit. Both can be paid to purchase postage stamps.
- BZZv1 and BZZv2 are likely worth the same amount in DAI.
- As BZZv2 becomes more valuable, BZZv1 can be minted using the bonding curve (for a discount), converted to BZZv2 using the BCManager, and sold back to the market for a small profit.
- BZZv1 for node deposits will need to be converted to BZZv2 (somehow).
- After a few years, BCManager will own most of the BZZv1. BZZv1 will be effectively deprecated.
- BCManager is triggered to
  - Redeem BZZv1 to DAI.
  - Call `shutdown()` on the bonding curve.
  - Send the DAI to the Swarm Foundation

## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->
*Pending*

## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
*Pending*

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
