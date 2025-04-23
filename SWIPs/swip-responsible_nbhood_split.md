---
SWIP: <to be assigned>
title: Responsible Neighborhood Splitting
author: Crt Ahlin <crt.ahlin@ethswarm.org> (@crtahlin)>
discussions-to: https://discord.com/channels/799027393297514537/1196446970689101824
status: WIP
type: Standards Track
category (*only required for Standard Track): Core
created: 2024-02-07
requires (*optional): <SWIP number(s)>
replaces (*optional): <SWIP number(s)>
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

# Responsible Neighborhood Splitting

## Simple Summary
<!--"If you can't explain it simply, you don't understand it well enough." Provide a simplified and layman-accessible explanation of the SWIP.-->

This proposal introduces a socially responsible behavior for nodes within the Swarm network, particularly during events leading to a storage radius increase, commonly known as network split events. When a node reaches its storage limit, instead of automatically expanding its storage radius and potentially evicting a significant portion of its reserve, it first checks for any healthy neighbors willing to take over the sister neighborhood storage responsibilities. If no such neighbors exist, the node will temporarily stop accepting new chunks, clearly communicating the reason for this halt. This approach aims to maintain the integrity and reliability of the network by ensuring data is not lost due to overly rapid expansion or insufficient neighborhood support, thereby preserving user trust and the overall health of the Swarm ecosystem.

## Abstract
<!--A short (~200 word) description of the technical issue being addressed.-->

This proposal tackles the challenge of storage radius increases in the Swarm network, which risk data loss and network reliability. It introduces a socially responsible node behavior, where nodes monitor their neighborhood's health and require a minimum of X active nodes in both their own and sister sub-neighborhoods before expanding their storage radius. The threshold X, defaulting to 2, ensures no node expands its storage without sufficient neighborhood support, halting new chunks acceptance if the criteria are not met. This mechanism aims to prevent data loss and maintain network integrity.


## Motivation
<!--The motivation is critical for SWIPs that want to change the Swarm protocol. It should clearly explain why the existing protocol specification is inadequate to address the problem that the SWIP solves. SWIP submissions without sufficient motivation may be rejected outright.-->

The Swarm network's health and sustainability depend fundamentally on its nodes' ability to reliably store and serve data. Nodes, acting as the backbone of data storage, receive compensation from data storers. This economic model underpins the network's viability, incentivizing nodes to participate and ensuring data storers' needs are met. However, the current static approach to handling storage capacity and neighborhood distribution poses a significant risk: potential data loss due to inadequate neighborhood support during storage radius increases.

From a business perspective, data loss directly impacts the network's economic foundation. Data storers, upon facing data unreliability, are likely to withhold payment, undermining the financial incentive for storage providers. This scenario threatens the network's stability, as nodes may exit, unable to cover their operational costs. Consequently, ensuring data integrity is not just a technical issue but a critical business imperative. This proposal aims to mitigate such risks by introducing socially responsible node behavior, maintaining data integrity, and, by extension, the network's economic model. By preventing data loss through enhanced neighborhood support mechanisms, we safeguard the network's reliability, preserving both node operators' income and data storers' trust.


## Specification
<!--The technical specification should describe the syntax and semantics of any new feature. The specification should be detailed enough to allow competing, interoperable implementations for the current Swarm platform and future client implementations.-->




1. **Node Monitoring and Active Status Determination**:
   - Nodes will utilize peer information available in their /topology endpoint to assess neighborhood health, considering peers that advertise themselves as "healthy." 
   - An "active node" is defined by its `lastSeenTimestamp`, which should be no longer than `activeIfSeenWithin` minutes ago (default `activeIfSeenWithin`=10 minutes). Nodes not seen within this timeframe will be subject to a connection attempt to confirm activity.
   - The `activeIfSeenWithin` threshold for determining activity is configurable, allowing operators to adjust based on network conditions.

2. **Configuration**:
   - Node configurations are determined via a config file or environment variables before startup, enabling operators to set parameters such as the `minimumActiveNodesInNbhood` and the `activeIfSeenWithin` timeout.

3. **Operational Details**:
   - Nodes nearing capacity will check for a minimum of `minimumActiveNodesInNbhood` active nodes in their own and sister sub-neighborhoods. If insufficient active nodes are found, they will halt accepting new chunks and periodically check for changes every `checkForActive` minutes (default `checkForActive`=5 minutes).
   - Nodes will communicate their inability to accept new chunks with an error message stating "Not accepting new chunks as reserve is full and neighborhood cannot split." Additionally, a "canIncreaseRadius" boolean field will be introduced to indicate a node's capacity to expand its storage radius.

4. **Recovery and Resumption**:
   - Nodes will continue to assess their neighborhood's status at intervals of `checkForActive` minutes. Once adequate support is identified, the "canIncreaseRadius" flag will be set to TRUE, allowing the node to resume accepting chunks and proceed with radius expansion as conditions allow.

5. **Interactions with Other Nodes and Data Requests**:
   - Data retrieval requests will continue unaffected. Nodes should forward the "not accepting new chunks" status to the original uploader, enhancing transparency and communication within the network.



## Rationale
<!--The rationale fleshes out the specification by describing what motivated the design and why particular design decisions were made. It should describe alternate designs that were considered and related work, e.g. how the feature is supported in other languages. The rationale may also provide evidence of consensus within the community, and should discuss important objections or concerns raised during discussion.-->


The design decisions for this proposal are rooted in ensuring the Swarm network's robustness and reliability while fostering a socially responsible behavior among nodes. 

1. **Choice of Parameters**: 
   - The `activeIfSeenWithin` default of 10 minutes strikes a balance between minimizing data loss and avoiding network congestion. It's conservative enough to ensure node reliability without overwhelming the network with frequent checks.
   - The `checkForActive` interval is set at 5 minutes to allow for a prompt recovery of upload capabilities as soon as adequate node redundancy is restored, optimizing for network responsiveness without inducing excessive traffic.
   - Setting `minimumActiveNodesInNbhood` to 2 offers essential redundancy, aligning with Swarm's optimization for having 4 nodes in each neighborhood. This ensures that, even post-split, each sub-neighborhood maintains a basic level of redundancy without unnecessarily inflating the required node count.

2. **Implementation of "canIncreaseRadius"**:
   - The "canIncreaseRadius" field serves as an early warning system, alerting the network to potential storage capacity issues before they become critical. This foresight allows network operators to proactively address challenges, enhancing the network's resilience and scalability.

3. **Socially Responsible Behavior**:
   - Emphasizing socially responsible node behavior reflects Swarm's core values of providing secure and dependable data storage. While not directly solving rapid growth challenges, this safety measure prevents data loss during critical expansion phases, allowing time for addressing underlying issues.

4. **Technical and Operational Challenges**:
   - Balancing the interests of individual nodes and the network ensures that both benefit from avoiding data loss. A potential challenge lies in user experience, particularly in communicating why uploads may be temporarily halted. The protocol suggests that uploading nodes retry with other nodes or, if unsuccessful, convey meaningful feedback to users, integrating these events into the broader handling of unsuccessful uploads. This approach maintains user transparency and trust, crucial for the network's long-term success.




## Backwards Compatibility
<!--All SWIPs that introduce backwards incompatibilities must include a section describing these incompatibilities and their severity. The SWIP must explain how the author proposes to deal with these incompatibilities. SWIP submissions without a sufficient backwards compatibility treatise may be rejected outright.-->


This proposal is designed to integrate seamlessly with the existing Swarm network protocols, ensuring no breaking changes to data structures or fundamental communication protocols. The introduction of additional data fields and behavioral logic, as outlined in the specification, represents an enhancement rather than an overhaul of current node operations. 

1. **Protocol Changes**:
   - The proposal adds functionality to the node software, including new data fields and decision-making processes regarding storage radius adjustments. These changes are non-disruptive to existing protocols and are intended to enhance network reliability and data integrity.

2. **Node Software Updates**:
   - Implementation of this proposal requires node operators to update their software to the latest version incorporating these features. This update is crucial for enabling the socially responsible behavior and ensuring nodes can communicate and operate effectively under the new guidelines.

3. **Impact on Existing Data**:
   - There will be no adverse effect on data previously stored within the network. The proposal's mechanisms are forward-looking, focusing on improving how new data is handled and stored.

4. **Network Operation**:
   - Nodes operating under current protocols will be able to coexist with nodes that have implemented the new features. This compatibility ensures that the network's overall functionality and reliability are maintained during the transition period.

5. **Upgrade Path**:
   - The upgrade to incorporate these changes will follow the regular Bee client update process. Node operators are encouraged to update their software as these enhancements become available, with no special requirements beyond standard update practices.




## Test Cases
<!--Test cases for an implementation are mandatory for SWIPs that are affecting changes to data and message formats. Other SWIPs can choose to include links to test cases if applicable.-->


1. **Node Threshold Validation**:
   - **Objective**: Verify that nodes accurately assess the number of active neighbors based on the `activeIfSeenWithin` and `minimumActiveNodesInNbhood` parameters.
   - **Method**: Simulate environments with varying numbers of active and inactive nodes to ensure nodes correctly determine their ability to accept new chunks or need to halt.

2. **Radius Increase Decision Process**:
   - **Objective**: Ensure that nodes correctly decide whether to increase their storage radius based on the presence of the required number of active nodes.
   - **Method**: Create scenarios where the conditions for radius expansion are both met and not met, validating the decision to either proceed with the expansion or halt new chunk acceptance.

3. **Communication of Status**:
   - **Objective**: Test the effectiveness of nodes in communicating their "canIncreaseRadius" status and the error message when halting new chunk acceptance.
   - **Method**: Trigger conditions where a node halts chunk acceptance and observe if the status is accurately communicated to peers and data storers.

4. **Recovery and Resumption of Operations**:
   - **Objective**: Confirm that nodes can successfully resume accepting chunks and potentially increase their storage radius once the required conditions are met.
   - **Method**: After a halt, introduce additional active nodes to meet the `minimumActiveNodesInNbhood` criteria and verify that halted nodes resume operations as designed.

5. **Backwards Compatibility and Coexistence**:
   - **Objective**: Validate that updated nodes can coexist and operate seamlessly with nodes running previous versions of the software.
   - **Method**: Operate a mixed network of updated and non-updated nodes, ensuring that data storage, retrieval, and node communication function without issues.

6. **Impact on Network Performance**:
   - **Objective**: Assess the impact of the proposed changes on network congestion, latency, and overall performance.
   - **Method**: Compare network performance metrics before and after implementing the proposal under various load conditions.

7. **User Experience and Error Handling**:
   - **Objective**: Evaluate how effectively uploading nodes handle and relay error messages to users when encountering a halt in chunk acceptance.
   - **Method**: Attempt to upload data under halt conditions and assess the clarity and accuracy of feedback provided to the user.

These test cases are designed to comprehensively evaluate the functionality of the proposed socially responsible node behavior, ensuring it enhances network reliability and integrity without compromising performance or user experience.



## Implementation
<!--The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.-->
The implementations must be completed before any SWIP is given status "Final", but it need not be completed before the SWIP is accepted. While there is merit to the approach of reaching consensus on the specification and rationale before writing code, the principle of "rough consensus and running code" is still useful when it comes to resolving many discussions of API details.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
