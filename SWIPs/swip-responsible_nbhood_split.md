---
SWIP: <to be assigned>
title: Responsible Neighborhood Splitting
author: Crt Ahlin <crt.ahlin@ethswarm.org> (@crtahlin)
discussions-to: https://discord.com/channels/799027393297514537/1196446970689101824
status: WIP
type: Standards Track
category: Core
created: 2024-02-07
---

# Responsible Neighborhood Splitting

## Simple Summary

This proposal introduces a socially responsible behavior for nodes within the Swarm network, particularly during events leading to a storage radius increase, commonly known as network split events. When a node reaches its storage limit, instead of automatically expanding its storage radius and potentially evicting a significant portion of its reserve, it first checks for any healthy neighbors willing to take over the sister neighborhood storage responsibilities. If no such neighbors exist, the node will temporarily stop accepting new chunks, clearly communicating the reason for this halt. This approach aims to maintain the integrity and reliability of the network by ensuring data is not lost due to overly rapid expansion or insufficient neighborhood support, thereby preserving user trust and the overall health of the Swarm ecosystem.

## Abstract

This proposal tackles the challenge of storage radius increases in the Swarm network, which risk data loss and network reliability. It introduces a socially responsible node behavior, where nodes monitor their neighborhood's health and require a minimum of X active nodes in both their own and sister sub-neighborhoods before expanding their storage radius. The threshold X, defaulting to 2, ensures no node expands its storage without sufficient neighborhood support, halting new chunks acceptance if the criteria are not met. This mechanism aims to prevent data loss and maintain network integrity.


## Motivation

The Swarm network's health and sustainability depend fundamentally on its nodes' ability to reliably store and serve data. Nodes, acting as the backbone of data storage, receive compensation from data storers. This economic model underpins the network's viability, incentivizing nodes to participate and ensuring data storers' needs are met. However, the current static approach to handling storage capacity and neighborhood distribution poses a significant risk: potential data loss due to inadequate neighborhood support during storage radius increases.

From a business perspective, data loss directly impacts the network's economic foundation. Data storers, upon facing data unreliability, are likely to withhold payment, undermining the financial incentive for storage providers. This scenario threatens the network's stability, as nodes may exit, unable to cover their operational costs. Consequently, ensuring data integrity is not just a technical issue but a critical business imperative. This proposal aims to mitigate such risks by introducing socially responsible node behavior, maintaining data integrity, and, by extension, the network's economic model. By preventing data loss through enhanced neighborhood support mechanisms, we safeguard the network's reliability, preserving both node operators' income and data storers' trust.

### Why Erasure Coding Is Insufficient

Erasure coding (EC) provides redundancy at the data level, allowing content to be reconstructed from a subset of its chunks. However, EC cannot mitigate data loss caused by empty sub-neighborhoods after a split. When a neighborhood splits and one of the resulting sub-neighborhoods has no active nodes, the Bee client's `closestPeer()` function (in `pkg/pushsync/pushsync.go`) returns `ErrNotFound` for any chunk targeting that address range. The pusher retries up to 6 times with backoff and then gives up. This affects both data chunks and parity chunks targeting the empty sub-neighborhood — EC cannot deliver chunks to neighborhoods where no peers exist. EC mitigates random peer churn (where some peers in a neighborhood go offline), but it does not address wholesale neighborhood absence after a split.

Furthermore, EC only protects content uploaded with sufficient redundancy. Data already stored in the reserve at lower or no redundancy levels before the split is not retroactively protected. This proposal protects the existing reserve by preventing the split from occurring until the network can support it.

### Why Stewardship Is Insufficient

The stewardship tool (used to re-upload missing chunks) relies on the same pushsync mechanism as regular uploads. When a sub-neighborhood has no active nodes, stewardship repair attempts encounter the same `ErrNotFound` failure — there are simply no peers to push the chunks to. Stewardship is a valuable recovery tool for transient failures (e.g., a node temporarily going offline), but it cannot serve as a substitute for preventing empty-neighborhood splits.

### Silent Push Failures

The problem is compounded by known issues in the Bee client's push failure handling. As documented in [ethersphere/bee#5400](https://github.com/ethersphere/bee/issues/5400) (with a fix in progress in [ethersphere/bee#5390](https://github.com/ethersphere/bee/pull/5390)), chunks can be silently dropped or falsely marked as synced after retry exhaustion. The upload API returns a successful response before network distribution completes, so the uploader may believe their data is safely stored when it has not been distributed. While fixing this reporting gap is important (and is being addressed separately), the fundamental problem remains: chunks cannot be stored in neighborhoods with zero peers. Monitoring and EC-level recommendations — as suggested during the review of this proposal — are valuable complementary measures that should be pursued separately, but they do not eliminate the need for the preventive mechanism proposed here.


## Specification

1. **Node Monitoring and Active Status Determination**:
   - Nodes will utilize peer information available in their /topology endpoint to assess neighborhood health, considering peers that advertise themselves as "healthy." 
   - An "active node" is defined by its `lastSeenTimestamp`, which should be no longer than `activeIfSeenWithin` minutes ago (default `activeIfSeenWithin`=10 minutes). Nodes not seen within this timeframe will be subject to a connection attempt to confirm activity.
   - The `activeIfSeenWithin` threshold for determining activity is configurable, allowing operators to adjust based on network conditions.

2. **Configuration**:
   - Node configurations are determined via a config file or environment variables before startup, enabling operators to set parameters such as the `minimumActiveNodesInNbhood` and the `activeIfSeenWithin` timeout.

3. **Operational Details**:
   - Nodes approaching capacity (at or above `earlyWarningThreshold`, default 80%) will check for a minimum of `minimumActiveNodesInNbhood` active nodes in their own and sister sub-neighborhoods. If insufficient active nodes are found and the reserve reaches full capacity, they will halt accepting new chunks and periodically check for changes every `checkForActive` minutes (default `checkForActive`=5 minutes).
   - Nodes will communicate their inability to accept new chunks with an error message stating "Not accepting new chunks as reserve is full and neighborhood cannot split safely." Additionally, a `canIncreaseRadius` boolean field will be introduced to indicate a node's capacity to expand its storage radius.

4. **Recovery and Resumption**:
   - Nodes will continue to assess their neighborhood's status at intervals of `checkForActive` minutes. Once adequate support is identified, the "canIncreaseRadius" flag will be set to TRUE, allowing the node to resume accepting chunks and proceed with radius expansion as conditions allow.

5. **Interactions with Other Nodes and Data Requests**:
   - Data retrieval requests will continue unaffected. Nodes should forward the "not accepting new chunks" status to the original uploader, enhancing transparency and communication within the network.

6. **Early Warning Signal**:
   - When a node's reserve reaches `earlyWarningThreshold` percent of capacity (default `earlyWarningThreshold`=80%) and the node detects that a potential split would create a sub-neighborhood with fewer than `minimumActiveNodesInNbhood` active peers, the node SHOULD emit a warning event and set a `splitWarning` flag in its topology endpoint response.
   - This signal is informational: the node continues to accept chunks normally but alerts the network (and monitoring systems) that a problematic split is approaching.
   - The warning includes: current reserve utilization percentage, current storage radius, the would-be sister sub-neighborhood address prefix, and the count of active peers found in that prefix.
   - Network monitoring tools can aggregate these warnings to identify areas of the address space at risk of data loss. This signal can also serve as the basis for recommending appropriate erasure coding levels to uploaders, though the specifics of such recommendations are out of scope for this SWIP.

7. **Configurable Override (`allow-split-without-support`)**:
   - A node configuration option `allow-split-without-support` (default: false) allows operators to bypass the halt mechanism and permit radius increases even when sub-neighborhoods lack sufficient peers.
   - When set to true, the node logs a warning but proceeds with the radius increase. This is intended for operators who have external mechanisms for data recovery or who prioritize availability over data preservation.
   - This option does NOT suppress the early warning signal from point 6.


## Rationale


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

5. **Incentive Alignment**:
   - While it may appear non-incentive-aligned for a node to stop accepting chunks (foregoing immediate revenue), the long-term incentive is aligned: if data is routinely lost during splits, uploaders will stop using the network, reducing revenue for all node operators. Responsible splitting is a coordination mechanism analogous to congestion control in TCP — individual restraint enables collective throughput. The `allow-split-without-support` configuration option preserves individual operator autonomy while defaulting to the collectively beneficial behavior.

6. **Erasure Coding Is Complementary, Not Sufficient**:
   - Erasure coding cannot deliver chunks — whether data or parity — to neighborhoods with zero peers. EC mitigates random peer churn (where some peers within a neighborhood go offline), but it does not address wholesale neighborhood absence after a split. Separate SWIPs or Bee configuration guidelines should address EC-level redundancy recommendations for uploaders, but this is out of scope for this proposal.

7. **Stewardship Limitations**:
   - The stewardship tool relies on the same pushsync mechanism as regular uploads and therefore encounters the same `ErrNotFound` failure when targeting empty neighborhoods. Additionally, known issues with push failure handling ([ethersphere/bee#5400](https://github.com/ethersphere/bee/issues/5400), fix in [ethersphere/bee#5390](https://github.com/ethersphere/bee/pull/5390)) mean that push failures can occur silently. Stewardship is valuable for recovering from transient failures but is not a substitute for preventing the conditions that cause data loss in the first place.

8. **Pseudo-Reserve Buffer Consideration**:
   - The idea of a pseudo-reserve buffer — where nodes reserve extra capacity for the sister neighborhood after a split — has been considered (as suggested during review). While this provides a short-term cushion, the amount needed is unpredictable, and when the buffer fills the same problem resurfaces. The early warning and halt mechanism proposed in this SWIP addresses the root cause rather than delaying it. However, a limited pseudo-reserve could be a complementary measure in future work.


## Backwards Compatibility

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

8. **Early Warning Signal Activation**:
   - **Objective**: Verify that the early warning signal fires when the reserve reaches `earlyWarningThreshold` and a split would create an under-supported sub-neighborhood.
   - **Method**: Configure a node with a small reserve capacity. Fill the reserve to the warning threshold. Verify that the topology endpoint includes the `splitWarning` flag with correct sub-neighborhood details. Confirm that the node continues accepting chunks (warning is informational only).

9. **Override Allows Split Despite Insufficient Peers**:
   - **Objective**: Confirm that `allow-split-without-support=true` permits radius increase even when sub-neighborhood support is insufficient.
   - **Method**: Configure a node with the override enabled. Fill the reserve to capacity with no peers in the sister sub-neighborhood. Verify the node increases its radius, logs a warning, and continues operating.


## Implementation

The implementation modifies three components of the Bee client: the reserve eviction logic (`pkg/storer/reserve.go`), the Kademlia topology tracking (`pkg/topology/kademlia/kademlia.go`), and the pushsync handler (`pkg/pushsync/pushsync.go`). The topology API endpoint (`pkg/api/topology.go`) is also extended to expose the early warning signal.

The following pseudo-code is illustrative and references actual Bee data structures and function names. It is not intended to be directly compilable.

### Sub-Neighborhood Peer Count Check

A new function in Kademlia determines whether both resulting sub-neighborhoods after a radius increase would have sufficient active peers:

```go
// Location: pkg/topology/kademlia/kademlia.go
//
// hasSufficientPeersForSplit checks whether both sub-neighborhoods
// resulting from a radius increase have at least minimumActive peers
// that were last seen within activeIfSeenWithin.
//
func (k *Kad) HasSufficientPeersForSplit(currentRadius uint8, minimumActive int, activeIfSeenWithin time.Duration) bool {
    newRadius := currentRadius + 1

    ownCount := 0
    sisterCount := 0
    now := time.Now()

    // Peers in bins >= newRadius fall in the node's own sub-neighborhood
    k.connectedPeers.EachBin(func(addr swarm.Address, bin uint8) (stop bool, err error) {
        if bin >= newRadius {
            if metrics := k.collector.Get(addr); now.Sub(metrics.LastSeen) <= activeIfSeenWithin {
                ownCount++
            }
        }
        return false, nil
    })

    // Peers in bin == currentRadius are in the sister sub-neighborhood
    // (they share currentRadius-1 prefix bits but differ at bit currentRadius)
    k.connectedPeers.EachBin(func(addr swarm.Address, bin uint8) (stop bool, err error) {
        if bin == currentRadius {
            if metrics := k.collector.Get(addr); now.Sub(metrics.LastSeen) <= activeIfSeenWithin {
                sisterCount++
            }
        }
        return false, nil
    })

    return ownCount >= minimumActive && sisterCount >= minimumActive
}
```

### Modified Reserve Eviction Logic

The check is inserted in the `unreserve()` function before incrementing the radius:

```go
// Location: pkg/storer/reserve.go, inside unreserve()
// Insert before the existing radius++ logic
//
func (db *DB) unreserve(ctx context.Context) {
    // ... existing eviction logic ...

    if evicted < target {
        // Before increasing radius, check sub-neighborhood support
        if !db.responsibleSplit.AllowSplitWithoutSupport {
            if !db.topology.HasSufficientPeersForSplit(
                radius,
                db.responsibleSplit.MinimumActiveNodesInNbhood,
                db.responsibleSplit.ActiveIfSeenWithin,
            ) {
                db.setHalted(true)
                db.logger.Warning("reserve full but split would create empty sub-neighborhood; halting chunk acceptance",
                    "radius", radius,
                )
                // Schedule periodic re-check
                db.startSplitCheckTicker(db.responsibleSplit.CheckForActive)
                return
            }
        } else {
            db.logger.Warning("proceeding with radius increase despite insufficient sub-neighborhood peers (override enabled)",
                "radius", radius,
            )
        }

        // Existing radius increase logic
        radius++
        db.reserve.SetRadius(radius)
    }
}
```

### Early Warning in Reserve Capacity Monitor

The early warning signal is emitted during the periodic capacity monitoring loop:

```go
// Location: pkg/storer/reserve.go, within the capacity monitoring goroutine
//
func (db *DB) checkEarlyWarning() {
    usage := float64(db.reserve.Size()) / float64(db.reserve.Capacity())

    if usage >= db.responsibleSplit.EarlyWarningThreshold {
        if !db.topology.HasSufficientPeersForSplit(
            db.reserve.Radius(),
            db.responsibleSplit.MinimumActiveNodesInNbhood,
            db.responsibleSplit.ActiveIfSeenWithin,
        ) {
            db.splitWarning = &SplitWarning{
                ReserveUsage:    usage,
                CurrentRadius:   db.reserve.Radius(),
                SisterPeerCount: db.topology.SisterPeerCount(db.reserve.Radius()),
                Timestamp:       time.Now(),
            }
            db.logger.Warning("approaching capacity with insufficient split support",
                "usage_pct", usage*100,
                "radius", db.reserve.Radius(),
            )
        }
    } else {
        db.splitWarning = nil
    }
}
```

### Pushsync Handler Modification

The pushsync handler rejects incoming chunks when the node is halted:

```go
// Location: pkg/pushsync/pushsync.go, inside handler()
// Insert after the existing storage radius check
//
func (ps *PushSync) handler(ctx context.Context, p p2p.Peer, stream p2p.Stream) {
    // ... existing chunk validation ...

    // Check if node is halted due to responsible split
    if ps.store.IsHalted() {
        return fmt.Errorf("not accepting new chunks: reserve is full and neighborhood cannot split safely")
    }

    // ... existing store logic ...
}
```

### Topology API Extension

The topology endpoint is extended to include the early warning and split readiness status:

```go
// Location: pkg/topology/topology.go
// Extend KadParams with new fields
//
type SplitWarning struct {
    ReserveUsage    float64   `json:"reserveUsage"`
    CurrentRadius   uint8     `json:"currentRadius"`
    SisterPeerCount int       `json:"sisterPeerCount"`
    Timestamp       time.Time `json:"timestamp"`
}

type KadParams struct {
    // ... existing fields ...
    SplitWarning      *SplitWarning `json:"splitWarning,omitempty"`
    CanIncreaseRadius bool          `json:"canIncreaseRadius"`
}
```

### Configuration Parameters

| Parameter | Default | Description |
|---|---|---|
| `minimum-active-nodes-in-nbhood` | 2 | Minimum active peers required in each sub-neighborhood for a split to proceed |
| `active-if-seen-within` | 10m | Duration threshold for considering a peer "active" based on `lastSeenTimestamp` |
| `check-for-active` | 5m | Interval for re-checking neighborhood support when the node is halted |
| `early-warning-threshold` | 0.80 | Reserve usage fraction (0.0–1.0) at which the early warning signal is emitted |
| `allow-split-without-support` | false | When true, permits radius increase even without sufficient peers (logs warning) |

## Notes

Parts of this SWIP — including the pseudo-code, some of the argumentation, and structural improvements — were generated with the assistance of AI. The pseudo-code references actual Bee data structures and function names but is illustrative only; it must be critically reviewed and validated against the current Bee codebase at implementation time.

## Copyright
Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
