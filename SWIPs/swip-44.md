---
SWIP: 44
title: Remove skipped rounds guard
author: Viktor Tron (@zelig)
discussions-to: https://github.com/ethersphere/SWIPs/pull/TBD
status: Draft
type: Standards Track
category: Core
created: 2026-01-16
---

## Simple Summary

Remove the skipped rounds guard check from the redistribution contract that was originally implemented to mitigate the singleton-node zero-depth attack.

## Abstract

In the redistribution contract, there is a check if at least the last $i\ge \Delta d$ rounds has been skipped if the depth decreased by $\Delta d$:

$$
\Delta d := depth_{last}-depth_{curr}
$$

$$
0<\Delta d \Rightarrow \Delta d\le round_{curr}-round_{last}
$$

This condition was put in there to mitigate the *singleton-node zero-depth attack*. But now after phase 3 (attach r8 proofs to the claim) of storage incentives, this criteria just creates unnecessary price increase and a pain for operators when there is a radius decrease. Thus the check needs to be removed.

## Motivation

After phase 3 (attach r8 proofs to the claim) of storage incentives, the skipped rounds guard check creates unnecessary price increase and a pain for operators when there is a radius decrease. The original purpose of mitigating the singleton-node zero-depth attack is now addressed through the r8 proof mechanism, making this guard redundant and burdensome.

## Specification

Remove the conditional check in the redistribution contract that enforces:

$$
0<\Delta d \Rightarrow \Delta d\le round_{curr}-round_{last}
$$

where $\Delta d := depth_{last}-depth_{curr}$

This check currently prevents claims when the depth has decreased by $\Delta d$ unless at least $\Delta d$ rounds have been skipped.

The specific implementation is in the `currentMinimumDepth()` function in the [Redistribution contract](https://github.com/ethersphere/storage-incentives/blob/master/src/Redistribution.sol#L854-L866):

```solidity
function currentMinimumDepth() public view returns (uint8) {
    uint256 difference = currentCommitRound - currentClaimRound;
    uint8 skippedRounds = uint8(difference > 254 ? 254 : difference) + 1;

    uint8 lastWinnerDepth = winner.depth;

    // We ensure that skippedRounds is not bigger than lastWinnerDepth, because of overflow
    return skippedRounds >= lastWinnerDepth ? 0 : lastWinnerDepth - skippedRounds;
}
```

The function calculates a minimum depth requirement based on the number of skipped rounds, which is then checked in the `reveal()` function at line 375:

```solidity
if (_depth < currentMinimumDepth()) {
    revert OutOfDepth();
}
```

This minimum depth check should be removed entirely. There should be no minimum depth requirement.

**Note:** Client implementations that rely on checking participation eligibility are not affected by this change, as the contract-level validation is the authoritative check.

See also: [storage-incentives#302](https://github.com/ethersphere/storage-incentives/issues/302)

## Rationale

The skipped rounds guard was originally implemented to mitigate the singleton-node zero-depth attack. With the implementation of phase 3 of storage incentives, which attaches r8 proofs to claims, this attack vector is now addressed through a different mechanism. The guard now serves only to create friction for legitimate operators experiencing radius decreases, without providing meaningful security benefits.

## Backwards Compatibility

This change is backwards compatible. The modification relaxes a constraint in the redistribution contract, allowing claims to proceed in cases that were previously blocked. Existing valid claims will continue to work as before, while additional scenarios (depth decreases without sufficient skipped rounds) will now also be permitted.

## Test Cases

Test cases should verify:
- Claims succeed when depth decreases without requiring skipped rounds
- The r8 proof mechanism continues to provide protection against the singleton-node zero-depth attack
- Normal redistribution operations remain unaffected

## Implementation

The implementation requires modifying the `currentMinimumDepth()` function in the redistribution contract to remove the logic that enforces the relationship between depth decrease and skipped rounds.

A reference implementation is available at: [storage-incentives#301](https://github.com/ethersphere/storage-incentives/pull/301)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
