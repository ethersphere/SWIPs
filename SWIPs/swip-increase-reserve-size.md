---
SWIP: <to be assigned>
title: Increase of Reserve Size
author: Crt Ahlin <crt.ahlin@ethswarm.org> (@crtahlin)
discussions-to: https://discord.com/channels/799027393297514537/1204811309867204758
status: WIP
type: Standards Track
category (*only required for Standard Track): Core
created: 2024-01-12
requires (*optional): <SWIP number(s)>
replaces (*optional): <SWIP number(s)>
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->
This is the suggested template for new SWIPs.

Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`.

The title should be 44 characters or less.

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->

This proposal aims to increase the reserve size—measured in the number of 4KB chunks—that each full Bee node in the Swarm network can provide. By modestly increasing the storage each node can offer, the overall storage capacity of the Swarm network will grow, assuming unchanged participation levels. This adjustment seeks to decrease the relative cost per unit of storage for node operators, enabling more competitive storage prices for users without significantly impacting individual node costs.


## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->

The initiative to enhance the reserve size is driven more by business considerations than technical necessities. A larger reserve size allows for more efficient use of resources, enabling nodes to offer storage at lower relative costs. However, a key technical challenge arises from the increased reserve size: verifying node compliance becomes more resource-intensive. As proof of reserve is established through hashing the stored data, enlarging the reserve size necessitates greater computational resources or time for verification.

## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

The current reserve size results in relatively high storage costs when compared to alternative platforms. Lowering these costs could increase demand for storage within the Swarm ecosystem, benefiting both users and node operators by generating more traffic and revenue. The proposal seeks to strike a balance by implementing a modest yet significant increase in reserve size. This approach aims to:

- Signal potential reductions in Swarm storage costs,
- Expand the total storage capacity available on the Swarm network,
- Gather operator feedback on the implementation experience,
- Assess the feasibility of further reserve size adjustments.

This change, however, requires careful consideration of its implications, including the potential burden on node operators to provide additional storage quickly and the increased complexity in calculating proofs of reserve.


## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->


The technical specification for increasing the reserve size in the Swarm network involves two primary changes:

1. **Reserve Size Adjustment:** The reserve size for each full Bee node will be increased from its current capacity of 4 million chunks (2^22 chunks) to 8 million chunks (2^23 chunks). This adjustment aims to expand the overall storage capacity of the Swarm network, enabling nodes to offer more storage at reduced relative costs.

2. **Adjustment of Lottery Round Timings:** To accommodate the increased reserve size and the consequent extension in the time required for calculating the reserve hash, the timing for the relevant lottery rounds, specifically the commit phase, will be doubled. This modification will be reflected in the corresponding smart contracts to ensure that the increased computational requirements do not adversely affect the network's performance or security.

This specification assumes that the rest of the Swarm protocol's logic remains unchanged and that the time for calculating the reserve hash will proportionally increase with the doubling of the reserve size. This approach seeks to maintain the integrity and functionality of the Swarm network while facilitating a more efficient and cost-effective storage solution.




## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->


The choice to simply double the reserve size represents the most straightforward method to enhance storage capacity per node and, by extension, across the entire Swarm network. This approach was chosen for its relative modesty, ensuring that a majority of node operators can feasibly expand their storage without facing significant barriers. Additionally, the simplicity of the implementation was a key factor, prioritizing changes that could be readily integrated into the current Swarm framework.

Several alternative strategies were considered but ultimately not pursued due to their complexity, potential for prolonged development and testing periods, or indirect impact on storage capacity:

1. **Modifying the Hashing Algorithm:** One option explored was to adapt the hashing algorithm to process larger reserves more efficiently, possibly through sampling portions of the reserve. While this could theoretically reduce the time required for hash calculations, the implementation and testing of a new algorithm would demand significant time and resources. This concept remains a candidate for future improvement proposals.

2. **Altering Lottery Round Participation:** Another consideration involved changing the logic behind participating in lottery rounds, allowing nodes to engage across multiple neighbourhoods. Despite its potential to enhance network dynamics, this change would not directly increase storage capacity and posed challenges in terms of complexity and testing requirements.

3. **Raising Minimum Hardware Specifications:** Increasing the minimum hardware requirements for node operation was also reviewed. This change could expedite hash calculations due to better performance but at the cost of complicating node participation and potentially excluding operators with limited resources.

The chosen proposal aims to strike a balance between immediate impact on storage capacity and ease of implementation, with a view towards keeping the Swarm network accessible and efficient. Future SWIPs may explore more complex options as the network evolves and as feedback from this and other changes informs our understanding of the Swarm ecosystem's needs.



## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->

The proposed changes to increase the reserve size entail modifications that are not backwards compatible with older versions of the Bee client. The necessity for uniform reserve sizes across nodes for successful lottery participation means that nodes operating on different versions of the Bee client software—specifically those not updated to accommodate the increased reserve size—will not interact seamlessly with updated nodes.

Given these considerations, it is strongly recommended for node operators to upgrade their Bee client software to the latest version as soon as it becomes available. This upgrade is crucial not only to avoid potential penalizations but also to benefit from the relative reduction in storage costs and to contribute to the enhanced overall capacity and efficiency of the Swarm network.

The lack of backward compatibility in this instance is recognized as a necessary trade-off to achieve the desired improvements in storage capacity and network performance. 


## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->


1. **Reserve Size Verification Test:**
   - **Objective:** To verify that the reserve size of each full Bee node has successfully doubled from 4 million chunks to 8 million chunks.
   - **Procedure:** Deploy a test node with the updated Bee client and inspect the reserve size parameter to confirm it matches the expected 8 million chunks.
   - **Expected Outcome:** The node's reserve size can reach 8 million chunks (and not more).

2. **Lottery Round Timing Test:**
   - **Objective:** To ensure that the timing for lottery rounds, specifically the commit phase, has been correctly doubled.
   - **Procedure:** Monitor and measure the duration of the commit phase during lottery rounds in the updated network, comparing it against the duration in the previous version.
   - **Expected Outcome:** The commit phase timing in the updated network is precisely twice as long as in the previous version.

3. **Backwards Compatibility Test:**
   - **Objective:** To assess the behavior of the network when updated nodes interact with nodes running older versions of the Bee client.
   - **Procedure:** Set up a mixed environment with nodes running both the updated and the older versions of the Bee client and initiate storage transactions and lottery participation.
   - **Expected Outcome:** Nodes are experiencing penalizations at an expected rate, proportional to number of nodes on older and newer versions.

4. **Performance Impact Test:**
   - **Objective:** To evaluate the impact of the increased reserve size on the performance of individual nodes and the Swarm network as a whole.
   - **Procedure:** Compare key performance indicators (e.g., transaction speed, data retrieval times, proof of reserve calculations) before and after the update.
   - **Expected Outcome:** Performance remains within acceptable parameters, with any deviations from previous benchmarks accounted for by the increased computational load.

5. **Economic Impact Test:**
   - **Objective:** To gauge the economic effects of the increased reserve size on storage costs and node operator incentives.
   - **Procedure:** Analyze storage cost trends and node operator activity (e.g., number of new nodes, node upgrades) following the implementation of the increased reserve size.
   - **Expected Outcome:** A relative reduction in storage costs is observed, alongside increased or sustained node operator engagement.

6. **Security and Stability Test:**
   - **Objective:** To verify that the increase in reserve size does not introduce new vulnerabilities or stability issues into the Swarm network.
   - **Procedure:** Conduct a series of stress tests and security audits on the network, focusing on the new reserve size and lottery round dynamics.
   - **Expected Outcome:** The network maintains its integrity and resilience, with no new security vulnerabilities introduced.



## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
