---
SWIP: 24
title: Time-Weighted Storage Proofs
author: darkobas2 (@darkobas2) 
discussions-to: <related discord url if exist>
status: Draft
type: Standards Track
category: Core
created: 2024-11-07
---

## Simple Summary
Introduce a time-based weighting mechanism for storage proof submissions to incentivize faster response times and reward nodes with better resources.

## Abstract
This SWIP proposes modifying the storage incentive mechanism to incorporate submission timing as a factor in reward distribution. Nodes that submit their storage proofs earlier in the 15-minute submission window will receive a higher weight in the reward calculation, encouraging better-resourced nodes and improving network performance.

## Motivation
Currently, all valid storage proofs submitted within the designated window are treated equally in the reward distribution process. This approach doesn't account for node performance and resource availability, potentially leading to:
- Equal rewards for both high-performance and resource-constrained nodes
- No incentive for faster proof submissions
- Reduced network efficiency due to delayed submissions
- Potential gaming of the system by nodes operating at minimum viable performance

## Specification

### Time Weight Calculation
For each storage proof submission window:

1. Define parameters:
   - `WINDOW_DURATION`: 15 minutes (approximately 75 blocks at 12-second block time)
   - `BASE_WEIGHT`: Minimum weight factor (proposed: 1.0)
   - `MAX_WEIGHT`: Maximum weight factor (proposed: 2.0)

2. Calculate submission weight:
```
weight = MAX_WEIGHT - (blockNumber - windowStartBlock) * (MAX_WEIGHT - BASE_WEIGHT) / WINDOW_DURATION
```

### Reward Distribution
Modified reward calculation:
```
nodeReward = totalReward * (nodeWeight * timeWeight) / sumOfWeightedSubmissions
```

### Parameters
- Submission Window: 75 blocks (~15 minutes)
- Base Weight: 1.0
- Maximum Weight: 2.0
- Weight Decay: Linear

## Rationale
- Early submissions indicate better node resources and network connectivity
- Linear decay provides predictable incentives
- 2x maximum multiplier balances incentive without overly penalizing slower nodes
- 15-minute window matches existing protocol timing while adding performance incentives
- Short window duration creates meaningful pressure for maintaining well-resourced nodes

## Backwards Compatibility
This change requires a hard fork as it modifies the reward distribution mechanism. All nodes must upgrade to participate in the new weighting system.

## Implementation
```solidity
contract StorageIncentives {
    uint256 public constant WINDOW_DURATION = 75; // ~15 minutes at 12-second blocks
    uint256 public constant BASE_WEIGHT = 1000; // 1.0 scaled by 1000
    uint256 public constant MAX_WEIGHT = 2000;  // 2.0 scaled by 1000
    
    struct Submission {
        address node;
        bytes32 storageHash;
        uint256 blockNumber;
        uint256 timeWeight;
    }
    
    function calculateTimeWeight(uint256 submissionBlock, uint256 windowStartBlock) 
        public 
        view 
        returns (uint256) 
    {
        if (submissionBlock <= windowStartBlock) {
            return MAX_WEIGHT;
        }
        
        uint256 blockDelta = submissionBlock - windowStartBlock;
        if (blockDelta >= WINDOW_DURATION) {
            return BASE_WEIGHT;
        }
        
        return MAX_WEIGHT - (blockDelta * (MAX_WEIGHT - BASE_WEIGHT) / WINDOW_DURATION);
    }
}
```

## Security Considerations
1. **Block Time Manipulation**: Miners could theoretically manipulate block timestamps
   - Mitigation: Use block numbers instead of timestamps
   
2. **Front-running**: Nodes might attempt to front-run other submissions
   - Mitigation: Commit-reveal scheme for proof submission

3. **Network Congestion**: High gas prices might delay submissions
   - Impact is more significant with shorter window
   - Mitigation: Base weight ensures nodes still receive meaningful rewards even with delayed submissions

4. **Network Latency**: Geographic distribution of nodes might affect submission times
   - Mitigation: Maximum weight multiplier (2x) keeps disadvantage manageable

## Economic Implications
1. Higher rewards for well-resourced nodes
2. Incentivizes infrastructure investment
3. Potential increased operating costs for competitive rewards
4. Natural balancing as nodes optimize for reward/cost ratio
5. Short window creates stronger incentives for maintaining good connectivity

## Additional Considerations
1. The 15-minute window might need adjustment based on:
   - Network performance metrics
   - Geographic distribution of nodes
   - Ethereum network congestion patterns
2. Weight multiplier could be adjusted based on:
   - Observed submission time distributions
   - Node operator feedback
   - Network performance goals
