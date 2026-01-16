---
SWIP: 44
title: Remove skipped rounds guard
author: <author name and contact>
discussions-to: <URL>
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

## Rationale

The skipped rounds guard was originally implemented to mitigate the singleton-node zero-depth attack. With the implementation of phase 3 of storage incentives, which attaches r8 proofs to claims, this attack vector is now addressed through a different mechanism. The guard now serves only to create friction for legitimate operators experiencing radius decreases, without providing meaningful security benefits.

## Backwards Compatibility

This change modifies the redistribution contract behavior and will require coordination with node operators. Nodes running older versions may behave differently during radius decrease events.

## Test Cases

Test cases should verify:
- Claims succeed when depth decreases without requiring skipped rounds
- The r8 proof mechanism continues to provide protection against the singleton-node zero-depth attack
- Normal redistribution operations remain unaffected

## Implementation

The implementation requires removing the conditional check from the redistribution contract that enforces the relationship between depth decrease and skipped rounds.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
