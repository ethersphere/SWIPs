---
SWIP: SWIP 050
title: Sequential Transformation Scheme 1 for Redistribution
author: lat-murmeldjur
status: Draft
type: Standards Track
category: Storage Incentives
created: 2026-07-06
requires: SWIP-049
---

# SWIP 050 - Sequential Transformation Scheme 1 for Redistribution

## Abstract

Sequential Transformation Scheme 1, or `STS-1`, extends Swarm redistribution from chunk-only sampling to a sequenced chunk-and-stamp proof. It keeps the deployed truth-teller draw shape, but an entry receives selection weight only after its selected stamp witnesses and STS-1 chunk-binding proofs pass.

The selected agreement value is:

```text
(chunkSampleHash, stampSampleHash, claimedDepth)
```

`chunkSampleHash` remains the chunk-side Schelling value. It encourages nodes to follow the same chunk rewrite and sample-construction conventions, but STS-1 does not open random chunk-sample witnesses and does not use chunk-sample density as a weight signal. Stamp density is the reliable density proof introduced by this SWIP.

For round `r`, `firstAnchor(r)` is the deployed round anchor consumed by the round. It selects the neighbourhood and transforms chunk addresses. A valid chunk sample hash reveal updates the deployed seed for `firstAnchor(r + 1)` and derives `stampAnchor(r)`, which orders transformed stamp addresses for the current round. A later valid stamp sample hash reveal creates `proofSeed(r)`, which only selects stamp-sample positions to prove.

Each selected stamp witness proves two links. First, the transformed stamp value is valid for `stampAnchor(r)`, the batch identifier, and the full stamp index, and the stamp signature proves that the batch owner authorized that stamp for a specific `chunkAddress`. Second, the transformed-chunk same-data proof verifies that a first-anchor transformed chunk address is derived from the same opened BMT data as that `chunkAddress`. The participant then proves that transformed address as a leaf inside its own `chunkTransformRoot`, committed in the first phase. Since `stampAnchor(r)` and `proofSeed(r)` are unknown when `chunkTransformRoot` is fixed, the participant cannot wait to learn the useful stamp range and add only those chunks later.

After the truth teller selects the Schelling point, the selected round payout is divided among all proof-validated entries that reported the same Schelling point, in proportion to proof-adjusted stake density. Every paid node must prove separately because `chunkTransformRoot` is participant-specific and not part of the Schelling point.

STS-1 preserves the deployed non-reveal freeze invariant across the longer sequence. A stage-one commit is unfinished until it becomes proof-validated. If its own round claims, that claim freezes unfinished entries using the selected truth depth. If its own round never claims, the unfinished entry is carried forward and finalized by the first later successful claim using the same duration rule.

## Motivation

The deployed mechanism already uses a transformed chunk-address sample as a Schelling value. STS-1 keeps that coordination role, but adds stamp sampling so depth overreporting depends on purchased stamp capacity. A transformed stamp address is computed from `stampAnchor(r)`, the batch identifier, and the full stamp index; a small witness set can verify batch existence, historical index range, signature, bucket alignment, balance, and liveness.

Stamp metadata alone is not enough. A node could keep valid stamps while missing the corresponding chunks. STS-1 therefore accepts a selected stamp only when the transformed stamp value is valid for the stamp slot, the batch-owner signature is valid for the stamped `chunkAddress`, the transformed-chunk same-data proof verifies that a first-anchor transformed chunk address is derived from the same opened BMT data as that `chunkAddress`, and that transformed address was already included in the first-phase `chunkTransformRoot`. At the time that root is committed, the later stamp ordering and proof positions are unknown, so the node must already have the chunk to preserve the option of using the stamp later.

The proposal addresses these issues:

1. **Chunk/stamp separation.** A selected stamp counts only when its chunk was already part of the first-phase content-derived commitment.
2. **Unproven selection.** A reveal has no truth-selection weight and no payout share until its stamp witnesses and binding proofs pass.
3. **Minimum-only density.** A denser valid stamp sample receives a continuous benefit instead of a stepwise all-or-nothing benefit.
4. **Batch utilization.** Lower within-bucket stamp indexes receive a continuous benefit because ordinary uploads tend to fill lower indexes before higher ones.

The existing participation rule remains load-bearing: after a node commits, it must finish the required reveal path or be frozen by claim. This is the deployed non-reveal rule applied to the longer STS sequence, with carry-over only so that a round without a successful claim does not let unfinished STS commitments disappear.

## Non-goals

STS-1 does not change the total size or source of the redistribution pot. It changes how the selected round pot is distributed after the Schelling point is selected.

STS-1 does not prove chunk-sample density. `chunkSampleHash` is a Schelling-point component, not a density witness path.

STS-1 does not prove independent physical replicas. It proves that selected stamps refer to chunks in the participant's own earlier content-derived commitment.

STS-1 relies on SWIP-049 for fixed historical postage scope. Node clients and contracts must evaluate the same batch and stamp-index set for the target round.

## Definitions

| Term | Meaning |
|---|---|
| `firstAnchor(r)` | The deployed round anchor consumed by round `r`; it selects the neighbourhood and transforms chunk addresses. It is produced by the existing seed, `currentRoundAnchor`, `currentSeed`, and skipped-round logic. |
| `stampAnchor(r)` | STS-1 domain-separated anchor created from the updated deployed seed after the first valid chunk sample hash reveal in round `r`; it transforms stamp addresses for round `r`. |
| `proofSeed(r)` | Randomness created by a valid stamp sample hash reveal; it selects stamp-sample positions to prove. |
| `selectionSeed(r)` | Randomness used by the deployed-style truth-teller draw after proof submission. |
| `chunkSampleHash` | Chunk-side Schelling value. STS-1 does not open random chunk-sample witnesses. |
| `stampSampleHash` | Root or hash of the ordered transformed stamp-address sample. Selected stamp witnesses are opened against it. |
| `chunkTransformRoot` | Participant-specific root over the claimed complete list of first-anchor transformed chunk addresses. |
| `Schelling point` | `(chunkSampleHash, stampSampleHash, claimedDepth)`. |
| `proof-validated entry` | Entry whose selected stamp witnesses and STS-1 binding proofs passed. |
| `truthy proof-validated entry` | Proof-validated entry matching the selected Schelling point. |
| `effectiveStakeDensity` | Deployed base stake density multiplied by the STS-1 stamp-density and utilization coefficients. |
| `postageScopeStartBlock(r)` | SWIP-049 historical boundary for batch existence, depth, balance, and index range. |

## Anchor and seed flow

The anchor ownership rule is:

```text
round r - 1 reveal/skip path        -> deployed seed yields firstAnchor(r)
round r                              -> consumes firstAnchor(r)
round r chunk sample hash reveal     -> updates deployed seed for firstAnchor(r + 1) and derives stampAnchor(r)
round r stamp sample hash reveal     -> creates proofSeed(r) and selectionSeed(r)
```

STS-1 does not add a second first-anchor storage system. `firstAnchor(r)` is the value returned by the deployed anchor path for round `r`. If round `r - 1` has no valid reveal, the deployed skipped-round path derives the next anchor by hashing the inherited seed once:

```text
firstAnchor(r) = H(firstAnchor(r - 1))
```

After `n` consecutive skipped rounds:

```text
firstAnchor(r + n) = H^n(firstAnchor(r))
```

A skipped round has no `stampAnchor`, no valid stamp sample, no `proofSeed`, and no STS-1 claim. The deterministic hash continuation is the deployed round-anchor continuation; STS-1 only consumes the resulting anchor.

`stampAnchor(r)` is derived from the updated deployed seed produced by the first valid chunk sample hash reveal in round `r`. It is unknown during first-stage commitment, so the participant cannot choose `chunkTransformRoot` after seeing the stamp ordering.

`proofSeed(r)` is created by the first valid stamp sample hash reveal in round `r`. It is unknown during stamp sample commitment, so a participant cannot precompute which stamp-sample positions will be opened.

## Round structure and sampling windows

An STS-1 round is 152 blocks. For a round starting at block `B`:

| Blocks | Length | Phase |
|---:|---:|---|
| `B` to `B + 37` | 38 | chunk sample hash commit |
| `B + 38` to `B + 56` | 19 | chunk sample hash reveal |
| `B + 57` to `B + 94` | 38 | stamp sample hash commit |
| `B + 95` to `B + 113` | 19 | stamp sample hash reveal |
| `B + 114` to `B + 132` | 19 | proof submission |
| `B + 133` to `B + 151` | 19 | truth selection, proportional payout settlement, and claim |

The actual chunk-sampling time depends on when the previous round created `firstAnchor(r)`. The chunk commit deadline is `B + 38`.

| Previous-round outcome | Chunk-sampling window |
|---|---:|
| Valid chunk sample hash reveal at `B - 114` | maximum: 152 blocks |
| Valid chunk sample hash reveal at `B - 96` | minimum: 134 blocks |
| Previous round skipped | maximum: 152 blocks |

The actual stamp-sampling time depends on when the current round created `stampAnchor(r)`. The stamp commit deadline is `B + 95`.

| Current-round outcome | Stamp-sampling window |
|---|---:|
| Valid chunk sample hash reveal at `B + 38` | maximum: 57 blocks |
| Valid chunk sample hash reveal at `B + 56` | minimum: 39 blocks |
| No valid chunk sample hash reveal | no valid stamp sample |

SWIP-049 fixes the postage scope at `B - 114`, the earliest scheduled block where `firstAnchor(r)` may be fixed. This boundary is an eligibility boundary, not a promise that every node has exactly 152 blocks after learning the actual anchor.

## Commit, hash-reveal, and proof sequence

During chunk sample hash commit, the participant submits an obfuscated commitment for a specific commit round. The hidden preimage contains that round number, `claimedDepth`, `chunkSampleHash`, `chunkTransformRoot`, and a nonce. The round binding prevents a commitment prepared for one round from being opened in another.

During chunk sample hash reveal, the participant opens that preimage with the same commit round. The contract checks the commitment and neighbourhood proximity against the deployed current reveal-round anchor. The first valid chunk sample hash reveal updates the deployed seed for `firstAnchor(r + 1)` and derives `stampAnchor(r)`. Without a valid chunk sample hash reveal, the round has no stamp proof path and the next first anchor comes from the deployed skipped-round hash continuation.

During stamp sample hash commit, the participant commits to `stampSampleHash` and a nonce, again bound to the same round. The stamp sample size is fixed at 16 and is not participant-supplied data. The commit is accepted only after that participant has a valid chunk sample hash reveal for the same round.

During stamp sample hash reveal, the participant opens the committed stamp sample hash. The first valid stamp sample hash reveal opens `proofSeed(r)` and `selectionSeed(r)`. There is no seed-only transaction that opens proof randomness while stamp sample hash reveals are still possible.

During proof submission, `proofSeed(r)` selects two random positions from 0 through 14 without replacement, and position 15 is always opened for density. The opened values must satisfy strict ordered-sample checks, so a fake sample built from repeated values risks the seed selecting a repeated or unsupported position.

A participant enters truth selection and payout settlement only after its selected stamp witnesses and binding proofs pass. For freeze purposes, a first-stage committer that never becomes proof-validated is treated like an unfinished deployed commit/reveal participant. The same round's claim freezes it when that round claims. If that round has no successful claim, the unfinished STS entry is finalized by the first later successful claim. The duration uses the selected truth depth of the claiming round, matching the deployed duration formula.

## Witness verification

STS-1 does not require chunk-sample witnesses. `chunkSampleHash` is part of the Schelling point, but the contract does not grant weight for unverified chunk-sample density. All STS-1 density weight comes from selected stamp witnesses.

For each selected stamp witness, the contract checks:

1. `transformedStampValue = H(stampAnchor(r), batchId, fullStampIndex)`.
2. The transformed stamp value is present at the selected position in `stampSampleHash`.
3. The selected position satisfies the ordered-sample proof rules.
4. SWIP-049 historical validity and ordinary non-signature stamp checks pass: the batch and index existed at `postageScopeStartBlock(r)`, the batch had enough balance then, the batch is still live, and bucket and proximity checks pass.
5. The batch-owner signature proves that the stamp is valid for the specific `chunkAddress`.
6. The transformed-chunk same-data proof verifies that the first-anchor transformed chunk address is derived from the same opened BMT data as the stamped `chunkAddress`.
7. A root-inclusion proof shows that this transformed chunk address is a leaf in this participant's `chunkTransformRoot`.

The final two checks are the participant-specific STS-1 binding. They prevent a proof from separately showing a valid stamp and an unrelated transformed chunk leaf. Since `chunkTransformRoot` is not part of the Schelling point, two nodes can reveal the same `(chunkSampleHash, stampSampleHash, claimedDepth)` while only one has the selected stamped chunks in its own root. Every weighted or paid node must therefore prove its own stamp-to-root binding.

## Coefficients and effective stake density

The base weight is the deployed stake-density value:

```text
baseStakeDensity = stake * 2^(claimedDepth - overlayHeight)
```

STS-1 multiplies the base by two continuous cube-root coefficients. The SWIP defines the mathematical coefficients; the appendix represents them with Q64.64 fixed-point arithmetic. Q64.64 means that `2^64` represents `1.0x`, `2 * 2^64` represents `2.0x`, and fractional values are stored as integers between those points. A WAD value would instead use `1e18` as `1.0x`. WAD is common for token amounts and decimal fixed-point math, but Q64.64 is a cleaner internal scale here because these coefficients are binary ratios and cube roots of binary ratios. The implementation rounds conservatively: it never gives more weight than the mathematical formula.

### Stamp-density coefficient

Let `L` be the stamp sample limit for the claimed depth, and let `x` be the largest proven transformed stamp value. The proof passes only if `x < L`. Values farther below `L` mean the opened sample is denser than the minimum threshold.

The coefficient is:

```text
stampDensityCoefficient = cbrt(L / x)
```

This is the continuous form of the one-third-per-density-bit rule: `2x`, `4x`, and `8x` density give `cbrt(2)`, `cbrt(4)`, and `2x` coefficients.

| Largest proven stamp value `x` | Density ratio `L / x` | Coefficient |
|---:|---:|---:|
| `0.90L` | `1.111x` | `1.036x` |
| `0.75L` | `1.333x` | `1.101x` |
| `0.50L` | `2.000x` | `1.260x` |
| `0.40L` | `2.500x` | `1.357x` |
| `0.25L` | `4.000x` | `1.587x` |
| `0.125L` | `8.000x` | `2.000x` |

The table is illustrative; the contract uses the formula, so values between rows receive intermediate coefficients.

### Utilization coefficient

For each opened stamp witness:

```text
indexRatio = (withinBucketIndex + 1) / slotsPerBucket
```

Let `avgIndexRatio` be the opened-witness average. Lower ratios mean earlier bucket usage. The coefficient is:

```text
utilizationCoefficient = max(1, cbrt(1 / (2 * avgIndexRatio)))
```

The `1 / 2` baseline receives no benefit; better utilization receives a continuous benefit, and worse utilization is not penalized below `1x`.

| Average index-position ratio | Benefit ratio `1 / (2 * avgIndexRatio)` | Coefficient |
|---:|---:|---:|
| `1 / 2` | `1.000x` | `1.000x` |
| `3 / 8` | `1.333x` | `1.101x` |
| `1 / 4` | `2.000x` | `1.260x` |
| `1 / 5` | `2.500x` | `1.357x` |
| `1 / 8` | `4.000x` | `1.587x` |
| `1 / 16` | `8.000x` | `2.000x` |

The table is illustrative; the contract computes the continuous cube root with conservative fixed-point rounding.

### Effective stake density

```text
effectiveStakeDensity =
    baseStakeDensity
    * stampDensityCoefficient
    * utilizationCoefficient
```

A proof-validated entry receives truth-selection weight equal to `effectiveStakeDensity`. After truth selection, every proof-validated entry matching the selected Schelling point receives a payout share proportional to the same value.

## Coefficient safety argument

If a node underreports depth by `k` bits, it loses a factor of `2^k` in base stake density. The best case for the underreport is that the stamp-density coefficient improves by `cbrt(2^k)` and the utilization coefficient also improves by `cbrt(2^k)`. The combined gain is:

```text
cbrt(2^k) * cbrt(2^k) = 2^(2k/3)
```

The lost base weight is `2^k`, so underreporting remains worse by:

```text
2^k / 2^(2k/3) = 2^(k/3)
```

This is why both benefits use cube roots.

## Truth selection, payout, and freezing

Truth selection is a deployed-style running weighted draw over proof-validated entries. The selected entry is the truth teller, and its `(chunkSampleHash, stampSampleHash, claimedDepth)` becomes the selected Schelling point.

STS-1 changes payout after this point. Instead of drawing one paid beneficiary among the matching entries, the contract divides the selected round pot among all proof-validated entries matching the selected Schelling point:

```text
payoutShare_i = roundPot * effectiveStakeDensity_i / sum(effectiveStakeDensity_j)
```

where `j` ranges over proof-validated entries matching the selected Schelling point.

Proof-validated entries that do not match the selected Schelling point are frozen under the existing disagreement rule. Stage-one commitments that never became proof-validated are handled as the STS form of the deployed non-reveal case. They are frozen by the same round's claim when that claim exists; otherwise they remain pending until the first later successful claim. All such freeze durations use the selected truth depth of the successful claiming round.

## Rationale

The sequence is what creates the binding. `chunkTransformRoot` is fixed while `stampAnchor(r)` and `proofSeed(r)` are unknown. The participant therefore cannot wait to learn which stamp range or witness positions are useful before deciding which chunks to include.

`chunkSampleHash` remains in the Schelling point because it coordinates the chunk-side convention followed by honest nodes. It is not used for density because STS-1 does not verify random chunk-sample witnesses.

The stamp proof path supplies the reliable density signal because stamp slots are backed by verifiable postage state. SWIP-049 fixes that postage state at the sampling boundary so the contract and node clients evaluate the same batch/index set.

Proportional payout is introduced because every paid node must submit its own proof. Proof validity cannot be inherited from another node on the same Schelling point because `chunkTransformRoot` is participant-specific and outside the Schelling point.

## Security considerations

STS-1 prevents selected stamp witnesses from counting unless their chunks were already included in the participant's first-phase transformed chunk-address root. Proof-before-selection prevents unproven sample hashes from affecting truth selection or payout, and round-bound commit preimages prevent cross-round reveal reuse.

Delayed proof randomness makes repeated or unsupported stamp samples unsafe. SWIP-049 fixed historical postage scope prevents later batch operations from expanding the eligible stamp set for an already-open round. The cube-root coefficients reward better stamp evidence while preserving the depth-underreporting disincentive.

STS-1 does not solve one-copy-many-overlays and does not prove independent physical storage.

## Backwards compatibility

STS-1 keeps the deployed truth-teller draw shape and freeze-duration formula. It changes eligibility, proof-adjusted weight, and post-truth payout settlement. The round length remains 152 blocks, with new internal phase boundaries for the STS-1 sequence.

The transformed stamp address is:

```text
transformedStampValue = H(stampAnchor, batchId, fullStampIndex)
```

Node clients must construct `chunkTransformRoot`, construct the transformed stamp sample from the SWIP-049 historical postage scope, and submit selected stamp witnesses when required.

## Appendix A: Solidity implementation proposal

The appendix is limited to STS-specific deltas. The deployed contract already owns round calculation, round-bound commits, active `currentCommits` and `currentReveals`, reveal-round initialization, first-anchor selection, skipped-round seed continuation, and ordinary chunk proof checks. Those pieces are referenced by name where the STS code plugs into them, but they are not redefined here.

The storage shape follows the deployed redistribution pattern: active reveal data is reused for the active round, and STS-only data is guarded by the active reveal round. There is no STS mapping keyed by every historical round and no separate anchor-progression subsystem.

### A.1 STS-specific records and state

`Reveal.hash` remains the chunk sample hash. The stamp sample hash and STS-only proof state live in an extension keyed by overlay. This avoids duplicating the deployed `Reveal` struct in the proposal while still allowing the selected Schelling point to be `(chunkSampleHash, stampSampleHash, depth)`. The `StampProof` embeds the deployed `ChunkInclusionProof` shape for the stamped chunk; this is not a separate chunk-sample witness, but the existing content-to-transformed-address proof needed by each selected stamp witness.

```solidity
struct StsRevealData {
    uint64 roundNumber;
    uint256 revealIndex;
    bytes32 stampHash;
    bytes32 chunkTransformRoot;
    uint256 effectiveStakeDensity;
    bool stampSampleHashRevealed;
    bool proofSubmitted;
}

struct StampSampleCommitment {
    uint64 roundNumber;
    bytes32 obfuscatedHash;
}

struct StampProof {
    bytes32[] proofSegments;
    bytes32 leftValue;
    bytes32[] leftProofSegments;
    bytes32 rightValue;
    bytes32[] rightProofSegments;
    bool hasLeftValue;
    bool hasRightValue;
    uint32 sampleIndex;
    bytes32 chunkAddress;
    bytes32 postageId;
    uint64 index;
    uint64 timeStamp;
    bytes signature;
    ChunkInclusionProof chunkProof;
    bytes32[] chunkTransformProofSegments;
}

struct StampSnapshot {
    address batchOwner;
    uint8 depthAtSamplingStart;
    uint8 bucketDepth;
    uint256 normalisedBalance;
}

struct SelectedSchellingPoint {
    bytes32 hash;
    bytes32 stampHash;
    uint8 depth;
}
```

The current round's first anchor remains the deployed `currentRevealRoundAnchor`. The deployed seed path remains responsible for skipped-round continuation and the next round's first anchor. STS adds only the current round's stamp anchor and the later proof/selection seeds.

```solidity
bytes32 public currentRevealRoundStampAnchor;
bool public currentRevealRoundStampAnchorSet;

uint64 public currentStampSampleHashRevealRound;
bytes32 public currentProofSeed;
bytes32 public currentSelectionSeed;
bool public currentProofSeedSet;

mapping(bytes32 => StsRevealData) internal stsRevealOfOverlay;
mapping(bytes32 => StampSampleCommitment) internal stampCommitOfOverlay;
mapping(address => uint256) public pendingRedistributionPayouts;
```

The deployed contract already freezes commits that do not complete the reveal path when a claim is processed. STS-1 reuses that invariant for the longer sequence: after stage-one commit, the node is not complete until it has a proof-validated STS entry. The carry-over list exists only for the case that the committer's own round never reaches a successful claim. Completed entries are removed with swap-and-pop, so the list contains only unresolved unfinished participants.

```solidity
struct PendingCompletion {
    bytes32 overlay;
    address owner;
}

PendingCompletion[] internal pendingCompletion;
mapping(bytes32 => uint256) internal pendingCompletionIndexPlusOne;
```

### A.2 Round-bound commitment preimages

The deployed `commit` function already accepts the commit round. STS only changes what the hidden hash commits to. The explicit round inside the hidden preimage prevents a commitment made for one round from being opened in a later round.

```solidity
function wrapChunkSampleHashCommit(
    uint64 commitRound,
    bytes32 overlay,
    uint8 depth,
    bytes32 chunkSampleHash,
    bytes32 chunkTransformRoot,
    bytes32 revealNonce
) public pure returns (bytes32) {
    return keccak256(
        abi.encodePacked(
            commitRound,
            overlay,
            depth,
            chunkSampleHash,
            chunkTransformRoot,
            revealNonce
        )
    );
}

function wrapStampSampleHashCommit(
    uint64 commitRound,
    bytes32 overlay,
    uint8 depth,
    bytes32 chunkSampleHash,
    bytes32 chunkTransformRoot,
    bytes32 stampSampleHash,
    bytes32 revealNonce
) public pure returns (bytes32) {
    return keccak256(
        abi.encodePacked(
            commitRound,
            overlay,
            depth,
            chunkSampleHash,
            chunkTransformRoot,
            stampSampleHash,
            revealNonce
        )
    );
}
```

### A.3 Hooks on the deployed reveal path

The deployed reveal path already initializes the reveal round, fixes `currentRevealRoundAnchor`, calls `updateRandomness()`, appends the ordinary `Reveal` entry, and stores the reveal index on the matched `Commit`. STS adds two small hooks: one to clear current-round STS seed fields when the deployed reveal round changes, and one to record the participant-specific `chunkTransformRoot` after the ordinary reveal has been accepted. The reveal index is copied internally from the deployed commit record; later STS calls do not receive a caller-supplied reveal index.

```solidity
function resetStsStateForNewRevealRound(uint64 roundNumber) internal {
    if (currentRevealRound != roundNumber) revert MissingAnchor();

    currentRevealRoundStampAnchor = bytes32(0);
    currentRevealRoundStampAnchorSet = false;
    currentStampSampleHashRevealRound = 0;
    currentProofSeed = bytes32(0);
    currentSelectionSeed = bytes32(0);
    currentProofSeedSet = false;
}

function recordChunkSampleHashReveal(
    uint64 roundNumber,
    uint256 commitIndex,
    bytes32 chunkTransformRoot
) internal {
    if (currentRevealRound != roundNumber) revert MissingAnchor();
    if (commitIndex >= currentCommits.length) revert NoMatchingCommit();
    if (!currentRevealRoundStampAnchorSet) openStampAnchorAfterDeployedRevealRandomness(roundNumber);

    Commit storage revealedCommit = currentCommits[commitIndex];
    if (!revealedCommit.revealed) revert NoChunkSampleHashReveal();
    if (revealedCommit.revealIndex >= currentReveals.length) revert NoChunkSampleHashReveal();

    Reveal storage revealRecord = currentReveals[revealedCommit.revealIndex];
    if (revealRecord.overlay != revealedCommit.overlay) revert NoChunkSampleHashReveal();

    stsRevealOfOverlay[revealedCommit.overlay] = StsRevealData({
        roundNumber: roundNumber,
        revealIndex: revealedCommit.revealIndex,
        stampHash: bytes32(0),
        chunkTransformRoot: chunkTransformRoot,
        effectiveStakeDensity: 0,
        stampSampleHashRevealed: false,
        proofSubmitted: false
    });
}

function openStampAnchorAfterDeployedRevealRandomness(uint64 roundNumber) internal {
    if (currentRevealRound != roundNumber) revert MissingAnchor();
    if (currentRevealRoundStampAnchorSet) return;

    currentRevealRoundStampAnchor = keccak256(
        abi.encodePacked(
            seed,
            roundNumber,
            "STS1_STAMP_ANCHOR"
        )
    );
    currentRevealRoundStampAnchorSet = true;
}
```

The first valid stamp sample hash reveal opens only STS-local proof randomness. It must not call `updateRandomness()`, because the deployed seed path has already advanced during the chunk sample hash reveal.

```solidity
function openProofSeedFromStampSampleHashReveal(uint64 roundNumber) internal {
    if (currentStampSampleHashRevealRound == roundNumber && currentProofSeedSet) return;
    if (currentRevealRound != roundNumber) revert MissingAnchor();
    if (!currentRevealRoundStampAnchorSet) revert MissingAnchor();

    currentStampSampleHashRevealRound = roundNumber;
    currentProofSeed = keccak256(
        abi.encodePacked(
            currentRevealRoundStampAnchor,
            block.prevrandao,
            roundNumber,
            "STS1_PROOF_SEED"
        )
    );
    currentSelectionSeed = keccak256(
        abi.encodePacked(
            currentRevealRoundStampAnchor,
            block.prevrandao,
            roundNumber,
            "STS1_SELECTION_SEED"
        )
    );
    currentProofSeedSet = true;
}
```

### A.4 Stage-one completion tracking

The deployed `commit` path should call `rememberStageOneCommitment` after accepting a stage-one commit. A successful STS proof removes the overlay from this list. Claim processing then freezes unresolved entries with the same selected-truth-depth formula used by the deployed non-reveal path. The list is a carry-over for rounds that never claimed; it is not a second anchor or round-state system.

```solidity
function rememberStageOneCommitment(bytes32 overlay, address owner) internal {
    if (pendingCompletionIndexPlusOne[overlay] != 0) revert PreviousCommitmentStillPending();

    pendingCompletion.push(
        PendingCompletion({
            overlay: overlay,
            owner: owner
        })
    );

    pendingCompletionIndexPlusOne[overlay] = pendingCompletion.length;
}

function markStageOneCommitmentProven(bytes32 overlay) internal {
    uint256 indexPlusOne = pendingCompletionIndexPlusOne[overlay];
    if (indexPlusOne == 0) return;

    uint256 index = indexPlusOne - 1;
    uint256 lastIndex = pendingCompletion.length - 1;

    if (index != lastIndex) {
        PendingCompletion memory moved = pendingCompletion[lastIndex];
        pendingCompletion[index] = moved;
        pendingCompletionIndexPlusOne[moved.overlay] = indexPlusOne;
    }

    pendingCompletion.pop();
    delete pendingCompletionIndexPlusOne[overlay];
}
```

### A.5 Stamp sample hash commit and reveal

The stamp sample size is fixed at 16, so the stamp-sample commitment hides only `stampSampleHash` and the nonce, together with the already revealed stage-one values. The caller does not supply a reveal-array index. The STS extension stores the reveal index when the deployed reveal path accepts the stage-one reveal, and later STS functions recover the active `Reveal` through the caller overlay.

```solidity
function revealIndexForOverlay(bytes32 overlay, uint64 roundNumber)
    internal
    view
    returns (uint256 revealIndex)
{
    StsRevealData storage data = stsRevealOfOverlay[overlay];
    if (data.roundNumber != roundNumber) revert NoChunkSampleHashReveal();

    revealIndex = data.revealIndex;
    if (revealIndex >= currentReveals.length) revert NoChunkSampleHashReveal();
    if (currentReveals[revealIndex].overlay != overlay) revert NoChunkSampleHashReveal();
}

function commitStampSampleHash(
    bytes32 obfuscatedHash,
    uint64 commitRound
) external whenNotPaused {
    requireStampSampleHashCommitPhase(commitRound);
    if (commitRound != currentRevealRound) revert NoChunkSampleHashReveal();

    bytes32 overlay = Stakes.overlayOfAddress(msg.sender);
    revealIndexForOverlay(overlay, commitRound);

    StsRevealData storage data = stsRevealOfOverlay[overlay];
    if (data.stampSampleHashRevealed) revert AlreadyRevealed();
    if (stampCommitOfOverlay[overlay].roundNumber == commitRound) revert AlreadyCommitted();

    stampCommitOfOverlay[overlay] = StampSampleCommitment({
        roundNumber: commitRound,
        obfuscatedHash: obfuscatedHash
    });
}

function revealStampSampleHash(
    uint64 commitRound,
    bytes32 stampSampleHash,
    bytes32 revealNonce
) external whenNotPaused {
    requireStampSampleHashRevealPhase(commitRound);
    if (commitRound != currentRevealRound) revert NoChunkSampleHashReveal();

    bytes32 overlay = Stakes.overlayOfAddress(msg.sender);
    uint256 revealIndex = revealIndexForOverlay(overlay, commitRound);
    Reveal storage revealRecord = currentReveals[revealIndex];
    StsRevealData storage data = stsRevealOfOverlay[overlay];
    StampSampleCommitment storage stampCommit = stampCommitOfOverlay[overlay];

    if (stampCommit.roundNumber != commitRound) revert NoStampSampleHashReveal();
    if (data.stampSampleHashRevealed) revert AlreadyRevealed();

    bytes32 expected = wrapStampSampleHashCommit(
        commitRound,
        overlay,
        revealRecord.depth,
        revealRecord.hash,
        data.chunkTransformRoot,
        stampSampleHash,
        revealNonce
    );

    if (expected != stampCommit.obfuscatedHash) revert NoStampSampleHashReveal();

    data.stampHash = stampSampleHash;
    data.stampSampleHashRevealed = true;
    openProofSeedFromStampSampleHashReveal(commitRound);
}
```

### A.6 Stamp witness selection and proof submission

The proof seed selects two positions from `0..14` without replacement. Position `15` is always opened as the density witness. The selected random positions are sorted before verification.

```solidity
uint32 private constant STAMP_SAMPLE_SIZE = 16;
uint32 private constant STS_WITNESS_COUNT = 3;
uint32 private constant STAMP_DENSITY_WITNESS = 15;

function selectedStampPositions(uint64 roundNumber) public view returns (uint32[3] memory positions) {
    if (currentStampSampleHashRevealRound != roundNumber || !currentProofSeedSet) {
        revert MissingAnchor();
    }

    uint32 a = uint32(uint256(keccak256(abi.encodePacked(currentProofSeed, uint256(0)))) % STAMP_DENSITY_WITNESS);
    uint32 b = uint32(uint256(keccak256(abi.encodePacked(currentProofSeed, uint256(1)))) % (STAMP_DENSITY_WITNESS - 1));

    if (b >= a) b += 1;
    if (b < a) (a, b) = (b, a);

    positions[0] = a;
    positions[1] = b;
    positions[2] = STAMP_DENSITY_WITNESS;
}
```

Proof submission verifies only stamp witnesses. There are no random witnesses from the chunk sample. Each stamp witness carries the per-node chunk binding into that participant's `chunkTransformRoot`.

```solidity
function submitStsProof(
    uint64 roundNumber,
    StampProof[3] calldata proofs
) external whenNotPaused {
    requireProofSubmissionPhase(roundNumber);
    if (roundNumber != currentRevealRound) revert NoChunkSampleHashReveal();

    bytes32 overlay = Stakes.overlayOfAddress(msg.sender);
    uint256 revealIndex = revealIndexForOverlay(overlay, roundNumber);
    Reveal storage revealRecord = currentReveals[revealIndex];
    StsRevealData storage data = stsRevealOfOverlay[overlay];

    if (!data.stampSampleHashRevealed) revert NoStampSampleHashReveal();
    if (data.proofSubmitted) revert ProofAlreadySubmitted();

    uint32[3] memory positions = selectedStampPositions(roundNumber);
    uint256 sumIndexRatioQ64;
    bytes32 lastTransformedStamp;

    for (uint256 i = 0; i < STS_WITNESS_COUNT; ) {
        if (proofs[i].sampleIndex != positions[i]) revert StampWitnessPositionMismatch();

        (bytes32 transformedStamp, uint256 indexRatioQ64) = verifyOneStampWitness(
            roundNumber,
            revealRecord,
            data,
            proofs[i]
        );

        sumIndexRatioQ64 += indexRatioQ64;
        if (i == STS_WITNESS_COUNT - 1) lastTransformedStamp = transformedStamp;

        unchecked { ++i; }
    }

    uint256 weight = revealRecord.stakeDensity;
    weight = Math.mulDiv(weight, stampDensityCoefficientQ64(lastTransformedStamp, revealRecord.depth), Q64);
    weight = Math.mulDiv(weight, utilizationCoefficientQ64(sumIndexRatioQ64), Q64);

    data.effectiveStakeDensity = weight;
    data.proofSubmitted = true;
    markStageOneCommitmentProven(overlay);
}
```

### A.7 Stamp witness verification

A stamp witness proves inclusion in the 16-entry stamp sample, strict local ordering against its neighbours, historical postage validity under SWIP-049, and binding from the stamped chunk into the participant's stage-one chunk root. The stamp path proves a valid transformed stamp slot and a batch-owner signature for `chunkAddress`. The chunk-binding path then uses the transformed-chunk same-data proof to verify that the first-anchor transformed chunk address is derived from the same opened BMT data as the stamped `chunkAddress`, before that transformed address can be accepted as a leaf of `chunkTransformRoot`.

```solidity
function verifyOneStampWitness(
    uint64 roundNumber,
    Reveal storage revealRecord,
    StsRevealData storage data,
    StampProof calldata proof
) internal view returns (bytes32 transformedStamp, uint256 indexRatioQ64) {
    transformedStamp = keccak256(
        abi.encodePacked(
            currentRevealRoundStampAnchor,
            proof.postageId,
            proof.index
        )
    );

    verifyStampElement(data.stampHash, transformedStamp, proof.proofSegments, proof.sampleIndex);
    verifyLocalStampOrder(data.stampHash, transformedStamp, proof);

    StampSnapshot memory snapshot = verifyStampAtSamplingStart(
        roundNumber,
        revealRecord.depth,
        proof
    );

    verifyChunkBinding(currentRevealRoundAnchor, data.chunkTransformRoot, proof);

    uint256 slotsPerBucket = postageStampIndexCount(
        snapshot.depthAtSamplingStart,
        snapshot.bucketDepth
    );
    uint256 withinBucketIndex = getPostageIndex(proof.index);

    indexRatioQ64 = mulDivUp(withinBucketIndex + 1, Q64, slotsPerBucket);
}

function verifyStampElement(
    bytes32 root,
    bytes32 value,
    bytes32[] calldata proofSegments,
    uint256 sampleIndex
) internal pure {
    if (sampleIndex >= STAMP_SAMPLE_SIZE) revert StampWitnessPositionMismatch();

    bytes32 calculated = BMTChunk.chunkAddressFromInclusionProof(
        proofSegments,
        value,
        sampleIndex,
        uint256(STAMP_SAMPLE_SIZE) * 32
    );

    if (calculated != root) revert StampInclusionProofFailed(sampleIndex);
}

function verifyLocalStampOrder(
    bytes32 root,
    bytes32 value,
    StampProof calldata proof
) internal pure {
    if (proof.sampleIndex > 0) {
        if (!proof.hasLeftValue || uint256(proof.leftValue) >= uint256(value)) {
            revert StampLocalOrderCheckFailed(proof.sampleIndex);
        }
        verifyStampElement(root, proof.leftValue, proof.leftProofSegments, proof.sampleIndex - 1);
    }

    if (proof.sampleIndex + 1 < STAMP_SAMPLE_SIZE) {
        if (!proof.hasRightValue || uint256(value) >= uint256(proof.rightValue)) {
            revert StampLocalOrderCheckFailed(proof.sampleIndex);
        }
        verifyStampElement(root, proof.rightValue, proof.rightProofSegments, proof.sampleIndex + 1);
    }
}
```

### A.8 Historical stamp validity and per-node chunk binding

The stamp-validity helper calls the SWIP-049 postage snapshot for the round's sampling boundary, then applies the ordinary stamp checks.

```solidity
function verifyStampAtSamplingStart(
    uint64 roundNumber,
    uint8 claimedDepth,
    StampProof calldata proof
) internal view returns (StampSnapshot memory snapshot) {
    uint256 samplingStart = roundStartBlock(roundNumber) - POSTAGE_SCOPE_LEAD;

    (
        snapshot.batchOwner,
        snapshot.depthAtSamplingStart,
        snapshot.bucketDepth,
        snapshot.normalisedBalance
    ) = PostageContract.redistributionBatchAt(proof.postageId, samplingStart);

    if (
        snapshot.normalisedBalance <
        PostageContract.redistributionMinimumNormalisedBalance(samplingStart)
    ) {
        revert BatchInsufficientBalanceAtSamplingStart(proof.postageId);
    }

    if (snapshot.bucketDepth < claimedDepth) revert BucketDepthBelowClaimedDepth(proof.postageId);

    if (
        getPostageIndex(proof.index) >=
        postageStampIndexCount(snapshot.depthAtSamplingStart, snapshot.bucketDepth)
    ) {
        revert IndexOutsideSet(proof.postageId);
    }

    if (getPostageBucket(proof.index) != addressToBucket(proof.chunkAddress, snapshot.bucketDepth)) {
        revert BucketDiffers(proof.postageId);
    }

    if (
        !Signatures.postageVerify(
            snapshot.batchOwner,
            proof.signature,
            proof.chunkAddress,
            proof.postageId,
            proof.index,
            proof.timeStamp
        )
    ) {
        revert SigRecoveryFailed(proof.postageId);
    }

    if (!inProximity(proof.chunkAddress, currentRevealRoundAnchor, claimedDepth)) {
        revert OutOfDepthClaim();
    }
}
```

The chunk-binding helper is the reason every paid participant must prove separately: `chunkTransformRoot` is participant-specific and is not part of the Schelling point. The helper verifies membership only after another helper has checked the same-data relation between the stamp's `chunkAddress` and the first-anchor transformed chunk address.

```solidity
function verifyChunkBinding(
    bytes32 roundFirstAnchor,
    bytes32 chunkTransformRoot,
    StampProof calldata proof
) internal view {
    bytes32 transformedChunkAddress = transformedChunkAddressForStampedChunk(
        roundFirstAnchor,
        proof.chunkAddress,
        proof.chunkProof
    );

    if (
        !MerkleProof.verify(
            proof.chunkTransformProofSegments,
            chunkTransformRoot,
            transformedChunkAddress
        )
    ) {
        revert ChunkTransformMembershipFailed();
    }
}
```

The helper below is the STS-local wrapper around the transformed-chunk same-data proof. It does not treat the stamp as proving the transformed chunk address. The stamp proves an ordinary `chunkAddress`. This helper proves the same-data relation: the ordinary BMT address calculated from the proof equals that stamped `chunkAddress`, and the transformed BMT address is calculated from the same proof under the round's first anchor. For SOC chunks, the existing SOC adjustment is applied before the transformed value is checked against `chunkTransformRoot`.

```solidity
function transformedChunkAddressForStampedChunk(
    bytes32 roundFirstAnchor,
    bytes32 stampedChunkAddress,
    ChunkInclusionProof calldata chunkProof
) internal view returns (bytes32 transformedChunkAddress) {
    uint256 segmentIndex = uint256(
        keccak256(
            abi.encodePacked(currentProofSeed, stampedChunkAddress, bytes32("STS1_CHUNK_SEGMENT"))
        )
    ) % 128;

    transformedChunkAddress = TransformedBMTChunk.transformedChunkAddressFromInclusionProof(
        chunkProof.proofSegments3,
        chunkProof.proveSegment2,
        segmentIndex,
        chunkProof.chunkSpan,
        roundFirstAnchor
    );

    if (chunkProof.proofSegments2[0] != chunkProof.proofSegments3[0]) {
        revert InclusionProofFailed(2, transformedChunkAddress);
    }

    bytes32 ordinaryChunkAddress = chunkProof.socProof.length > 0
        ? chunkProof.socProof[0].chunkAddr
        : chunkProof.proveSegment;

    if (
        ordinaryChunkAddress != BMTChunk.chunkAddressFromInclusionProof(
            chunkProof.proofSegments2,
            chunkProof.proveSegment2,
            segmentIndex,
            chunkProof.chunkSpan
        )
    ) {
        revert InclusionProofFailed(3, transformedChunkAddress);
    }

    if (ordinaryChunkAddress != stampedChunkAddress) revert ChunkAddressMismatch();

    if (chunkProof.socProof.length > 0) {
        transformedChunkAddress = keccak256(
            abi.encode(chunkProof.proveSegment, transformedChunkAddress)
        );
    }
}
```

### A.9 Q64.64 coefficient arithmetic

Q64.64 is binary fixed point: `Q64` means `1.0x`, `2 * Q64` means `2.0x`, and `Q64 / 2` means `0.5x`. It is used here because the coefficients are cube roots of binary ratios.

The rounding rule is conservative. Benefit ratios round down when they are direct rewards. Average index ratios round up before they are used as denominators. The cube root returns the largest Q64.64 value whose cube is not greater than the input ratio.

```solidity
uint256 private constant Q64 = 1 << 64;
uint256 private constant MAX_RATIO_REAL = 1 << 96;
uint256 private constant MAX_RATIO_Q64 = MAX_RATIO_REAL * Q64;
uint256 private constant MAX_COEFFICIENT_Q64 = (1 << 32) * Q64;

function mulDivUp(uint256 x, uint256 y, uint256 denominator) internal pure returns (uint256 result) {
    result = Math.mulDiv(x, y, denominator);
    if (mulmod(x, y, denominator) != 0) result += 1;
}

function ratioQ64(uint256 numerator, uint256 denominator) internal pure returns (uint256) {
    if (denominator == 0) return MAX_RATIO_Q64;
    if (numerator / denominator >= MAX_RATIO_REAL) return MAX_RATIO_Q64;
    return Math.mulDiv(numerator, Q64, denominator);
}

function cubeQ64(uint256 valueQ64) internal pure returns (uint256) {
    uint256 squareQ64 = Math.mulDiv(valueQ64, valueQ64, Q64);
    return Math.mulDiv(squareQ64, valueQ64, Q64);
}

function cubeRootQ64(uint256 valueQ64) internal pure returns (uint256) {
    if (valueQ64 <= Q64) return Q64;

    uint256 low = Q64;
    uint256 high = 2 * Q64;

    while (high < MAX_COEFFICIENT_Q64 && cubeQ64(high) <= valueQ64) {
        low = high;
        high *= 2;
    }

    if (high > MAX_COEFFICIENT_Q64) high = MAX_COEFFICIENT_Q64;
    if (cubeQ64(high) <= valueQ64) return high;

    while (low + 1 < high) {
        uint256 middle = (low + high) / 2;
        if (cubeQ64(middle) <= valueQ64) low = middle;
        else high = middle;
    }

    return low;
}

function stampDensityCoefficientQ64(bytes32 lastValue, uint8 depth) internal view returns (uint256) {
    uint256 x = uint256(lastValue);
    uint256 limit = sampleMaxValueForDepth(depth);

    if (x >= limit) revert StampReserveCheckFailed(lastValue);

    return cubeRootQ64(ratioQ64(limit, x));
}

function utilizationCoefficientQ64(uint256 sumIndexRatioQ64) internal pure returns (uint256) {
    uint256 averageIndexRatioQ64 = mulDivUp(sumIndexRatioQ64, 1, STS_WITNESS_COUNT);

    if (averageIndexRatioQ64 >= Q64 / 2) return Q64;
    if (averageIndexRatioQ64 == 0) return MAX_COEFFICIENT_Q64;

    uint256 benefitRatioQ64 = Math.mulDiv(Q64, Q64, 2 * averageIndexRatioQ64);
    return cubeRootQ64(benefitRatioQ64);
}
```

### A.10 Truth selection, payout settlement, and freezing

Truth selection keeps the deployed running weighted draw shape, but only proof-submitted entries have STS weight. The selected entry defines the Schelling point. Payout settlement then splits the pot among all proof-submitted entries matching that point, weighted by their effective stake density.

```solidity
function getCurrentStsTruth(uint64 roundNumber) public view returns (SelectedSchellingPoint memory truth) {
    if (currentStampSampleHashRevealRound != roundNumber || !currentProofSeedSet) {
        revert NoClaimableTruth();
    }

    bytes32 anchor = keccak256(abi.encodePacked(currentSelectionSeed, uint256(0)));
    uint256 totalWeight;

    for (uint256 i = 0; i < currentReveals.length; ) {
        Reveal storage revealRecord = currentReveals[i];
        StsRevealData storage data = stsRevealOfOverlay[revealRecord.overlay];

        if (data.roundNumber == roundNumber && data.proofSubmitted) {
            totalWeight += data.effectiveStakeDensity;
            uint256 draw = uint256(keccak256(abi.encodePacked(anchor, i)) & MAX_H);

            if (draw * totalWeight < data.effectiveStakeDensity * (uint256(MAX_H) + 1)) {
                truth = SelectedSchellingPoint({
                    hash: revealRecord.hash,
                    stampHash: data.stampHash,
                    depth: revealRecord.depth
                });
            }
        }

        unchecked { ++i; }
    }

    if (totalWeight == 0) revert NoClaimableTruth();
}

function matchesTruth(
    uint64 roundNumber,
    Reveal storage revealRecord,
    StsRevealData storage data,
    SelectedSchellingPoint memory truth
) internal view returns (bool) {
    return data.roundNumber == roundNumber
        && data.proofSubmitted
        && revealRecord.hash == truth.hash
        && data.stampHash == truth.stampHash
        && revealRecord.depth == truth.depth;
}
```

The deployed claim path keeps phase checks, pot withdrawal, price adjustment, and claim-round finalization. STS replaces the single paid winner with this settlement helper before the claim is finalized.

```solidity
function settlePayoutsAndFreezeDisagreements(
    uint64 roundNumber,
    SelectedSchellingPoint memory truth,
    uint256 pot
) internal returns (uint16 redundancyCount) {
    uint256 totalTruthyWeight;
    uint256 paid;
    address lastTruthyOwner;

    for (uint256 i = 0; i < currentReveals.length; ) {
        Reveal storage revealRecord = currentReveals[i];
        StsRevealData storage data = stsRevealOfOverlay[revealRecord.overlay];

        if (matchesTruth(roundNumber, revealRecord, data, truth)) {
            totalTruthyWeight += data.effectiveStakeDensity;
        }

        unchecked { ++i; }
    }

    if (totalTruthyWeight == 0) revert NoPayoutWeight();

    for (uint256 i = 0; i < currentReveals.length; ) {
        Reveal storage revealRecord = currentReveals[i];
        StsRevealData storage data = stsRevealOfOverlay[revealRecord.overlay];

        if (matchesTruth(roundNumber, revealRecord, data, truth)) {
            uint256 share = Math.mulDiv(pot, data.effectiveStakeDensity, totalTruthyWeight);
            pendingRedistributionPayouts[revealRecord.owner] += share;
            paid += share;
            lastTruthyOwner = revealRecord.owner;
            redundancyCount += 1;
        } else if (
            data.roundNumber == roundNumber &&
            data.proofSubmitted &&
            block.prevrandao % 100 < penaltyRandomFactor
        ) {
            Stakes.freezeDeposit(
                revealRecord.owner,
                uint256(penaltyMultiplierDisagreement) * ROUND_LENGTH * uint256(2 ** truth.depth)
            );
        }

        unchecked { ++i; }
    }

    if (pot > paid) pendingRedistributionPayouts[lastTruthyOwner] += pot - paid;
}
```

The completion finalizer runs after successful payout settlement. It applies the same selected-truth-depth duration formula as the deployed non-reveal freeze path to any unresolved STS stage-one participant that has not already been removed by a successful proof.

```solidity
function finalizeIncompleteCommitments(uint8 selectedTruthDepth) internal {
    for (uint256 i = 0; i < pendingCompletion.length; ) {
        PendingCompletion storage entry = pendingCompletion[i];

        delete pendingCompletionIndexPlusOne[entry.overlay];
        Stakes.freezeDeposit(
            entry.owner,
            uint256(penaltyMultiplierNonRevealed) * ROUND_LENGTH * uint256(2 ** selectedTruthDepth)
        );

        unchecked { ++i; }
    }

    delete pendingCompletion;
}

function withdrawRedistributionPayout(address receiver) external whenNotPaused {
    uint256 amount = pendingRedistributionPayouts[msg.sender];
    if (amount == 0) revert NoPayout();

    pendingRedistributionPayouts[msg.sender] = 0;
    transferRedistributionToken(receiver, amount);
}
```
