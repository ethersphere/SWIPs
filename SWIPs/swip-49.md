---
swip: SWIP 049
title: Fixed postage-stamp usability for redistribution rounds
author: lat-murmeldjur
status: Draft
type: Standards Track
category: Core
created: 2026-06-24
---

# Fixed postage-stamp usability for redistribution rounds

## Abstract

Phase 5 adds a postage-stamp sample beside the existing chunk-data sample. For each distinct stamp identity, Bee calculates `hash(batchId, fullStampIndex, roundAnchor)` and keeps the required lowest values. One purchased index can therefore contribute only one transformed value in a round, so overreporting storage depth requires a correspondingly large number of real stamp indexes. The separate chunk sample remains necessary to show that participants also store the same chunk data.

For the two samples to be usable for claim, Bee and the Redistribution contract must use the same set of batches and indexes. This SWIP fixes that set when sampling begins and keeps it fixed through the last claim block. A batch may be used only if it already existed, had at least 456 blocks of balance at the price in force when sampling began, and already contained the proved index at that time. New batches and newly created indexes remain usable for uploads immediately, but they cannot be used by an already open redistribution round.

Furthermore, the suggestion is for the PostageStamp contract to keep one previous price and two previous batch depths. The Redistribution contract can use that history to reconstruct the price and index range that applied when sampling began at claim. A top-up is allowed only while the batch still has at least six rounds of balance, and a dilution must leave at least six rounds of balance. The claim verifies that the batch is still present and live, verifies all postage proofs, including that the index existed at the start of sampling, and only then allows the price to change.

## Specification

### When the usable batch and index set is fixed

A redistribution round contains 152 blocks:

- 38 commit blocks;
- 38 reveal blocks; and
- 76 claim blocks.

For target round `r`, sampling begins at the first reveal block of round `r - 1`. This is the first scheduled block in which a successful reveal can produce the anchor used by target round `r`. If the preceding reveal phase has no successful reveal, the existing skipped-round seed derivation is used and the target round remains playable. The sampling boundary does not move.

The sampling-start block is:

```text
samplingStartBlock(r) = (r - 1) * 152 + 38
```

The state used by the round is the state after the preceding block has been processed. A batch creation or dilution included before `samplingStartBlock` may therefore affect the target round. An operation included in `samplingStartBlock` or later is too late for that round.

Counting the sampling-start block and the final target-round claim block, the round's sampling-to-claim window spans 266 blocks. During that window, later postage operations must not change:

- whether a batch may be used by the target round; or
- how many indexes from that batch may be used by the target round.

### When a batch and stamp index may be used

A stamp index may be used by target round `r` only when all of the following are true:

1. The batch was created before `samplingStartBlock(r)`.
2. At `samplingStartBlock(r)`, the batch had enough remaining balance for 456 blocks at the price then in force.
3. The full stamp index fitted within the batch depth that existed before `samplingStartBlock(r)`.
4. The batch is still present and live when the target claim verifies the stamp.
5. The existing signature, bucket-alignment, inclusion-proof, and other postage checks pass.

The target claim can be submitted as late as the end of the 266-block window. Requiring 456 blocks of balance at sampling start leaves 190 starting-price blocks of headroom over that claim window. This headroom is used to tolerate the price increase that the preceding round's claim may apply while target-round sampling is already in progress.

### Recovering the price and balance at sampling start

`PostageStamp` already stores:

- `lastPrice`, the price currently in force;
- `lastUpdatedBlock`, the block in which that price became active; and
- `totalOutPayment`, cumulative per-chunk outpayment at that update block.

This SWIP adds:

```text
previousPrice
```

`previousPrice` is the price that was in force immediately before `lastPrice`.

After activation, `PostageStamp.setPrice` is called only by a redistribution claim. The target claim verifies all postage proofs before applying its own price update. Therefore, when target-round postage proofs are checked, at most one price update can have occurred after sampling began: the update made by the preceding round's claim.

The price and cumulative outpayment at sampling start are reconstructed as follows:

```text
if lastUpdatedBlock < samplingStartBlock:
    priceAtStart = lastPrice
    outPaymentAtStart =
        totalOutPayment
        + (samplingStartBlock - lastUpdatedBlock) * lastPrice
else:
    priceAtStart = previousPrice
    outPaymentAtStart =
        totalOutPayment
        - (lastUpdatedBlock - samplingStartBlock) * previousPrice
```

The fixed balance threshold for the target round is:

```text
requiredNormalisedBalance =
    outPaymentAtStart + 456 * priceAtStart
```

Bee and the Redistribution contract use this same threshold. A later price update does not change it.

### Minimum balance required for batch operations

Every operation that creates a batch or reduces its balance per chunk must respect a minimum of six complete redistribution rounds at the price in force when the operation executes. Six rounds are:

```text
6 * 152 = 912 blocks
```

The rules are:

- a new or imported batch must start with at least `912 * lastPrice` per chunk;
- a batch may be topped up only if it still has at least `912 * lastPrice` per chunk before the top-up; and
- a dilution is allowed only if the resulting per-chunk balance is at least `912 * lastPrice`.

A deployment may require a larger minimum, but it must not permit less than 912 blocks.

These rules remove the need for per-batch balance history. A top-up cannot rescue a nearly expired batch into an already open round, because the batch must already have six rounds of balance before it can be topped up. A dilution cannot remove a batch from an already open round, because the diluted batch must still have six rounds of balance afterward.

New batches and the additional indexes created by dilution remain usable for uploads immediately. The introduction block only determines the first redistribution round in which they may be sampled and used for claim.

### Recovering the depth that existed at sampling start

The live `Batch` continues to store its current depth and `lastUpdatedBlockNumber`. For this purpose, `lastUpdatedBlockNumber` is the block in which the current depth was introduced. Top-ups do not change it.

Each batch additionally stores the two depths immediately before the current depth, together with the blocks in which those depths were introduced:

```text
PreviousDepths {
    previousDepth
    previousDepthBlock
    olderDepth
    olderDepthBlock
}
```

For a target round, the usable depth is the newest recorded depth whose introduction block is earlier than `samplingStartBlock`. The contract checks the current depth first, then the previous depth, then the older depth. If none of them existed before sampling began, the batch did not yet exist for that target round.

Two preceding depths are required because neighboring sampling-to-claim windows overlap. A later round can fix its batch scope while the preceding target round can still be claimed.

For example:

```text
Before round r starts sampling:
    depth = 20

After round r starts sampling, but before round r+1 starts sampling:
    dilute to 21
    dilute again to 22

After round r+1 starts sampling, while round r is still claimable:
    dilute to 23
```

The required result is:

```text
round r uses depth 20
round r+1 uses depth 22
uploads and later rounds use depth 23
```

The contract must therefore retain:

```text
older depth    = 20
previous depth = 22
current depth  = 23
```

Depth 21 does not need to be retained because no sampling boundary observed it. The first dilution after a sampling boundary rotates the depth history once. Further dilutions before the next sampling boundary replace only the current depth. This permits multiple dilutions without losing a depth that an open target claim still needs.

### Target-claim verification and price-update order

The target round number determines `samplingStartBlock`. At the beginning of claim verification, the Redistribution contract reconstructs `requiredNormalisedBalance` once and uses the same value for every postage proof in the claim. This includes postage attached to the chunk-data sample and postage proved for the separate stamp sample.

For each proved stamp, the PostageStamp contract supplies:

- the current batch owner;
- the immutable bucket depth;
- the current normalised balance; and
- the historical batch depth that existed before sampling began.

The Redistribution contract accepts the stamp only if:

- a historical depth exists for the target sampling start;
- the batch's normalised balance is at least `requiredNormalisedBalance`;
- the batch is still live under `currentTotalOutPayment()`;
- the proved index already existed within the batch's index range when sampling began; and
- the existing bucket and signature checks pass.

The fourth check is the claim-time proof that a later dilution did not create the
proved index. The contract first resolves `depthAtSamplingStart`, extracts the
index-within-bucket from `fullStampIndex`, and checks:

```text
getPostageIndex(fullStampIndex)
    < postageStampIndexCount(depthAtSamplingStart, bucketDepth)
```

For example, an index can be valid under the batch's larger live depth at claim
time but still be rejected because it was outside the smaller index range that
existed when sampling began. Claim verification always uses the latter range.

An expired batch is never accepted. If expiry cleanup has already run, the batch is absent from the normal batch mapping. If cleanup has not yet run, the explicit live-balance check rejects it. No expired-batch tombstone or secondary claim registry is introduced.

`winnerSelection` must not update the postage price. It returns the redundancy count to `claim`. The claim then verifies every chunk proof and postage proof. After all proofs have succeeded, it marks the round claimed, calls `PriceOracle.adjustPrice`, and continues with the existing withdrawal. Because `PostageStamp.setPrice` accounts up to the current block at the old price, this target-round price update is not retroactive and cannot invalidate the proofs just checked.

The stamp transformation is exactly:

```text
hash(batchId, fullStampIndex, roundAnchor)
```

### Tolerance of skipped-round price catch-up

The 456-block requirement is intended to keep a sampled batch in the normal batch registry for the complete 266-block sampling-to-claim window.

The earliest preceding-round claim can update the price 38 blocks after target sampling begins. A batch admitted with exactly 456 starting-price blocks has then spent 38 blocks and still holds 418 starting-price block units.

Under the current PriceOracle, the largest ordinary increase for the claimed round is:

```text
1049206 / 1048576
```

Each skipped round compounds the maximum increase:

```text
1049417 / 1048576
```

After 755 skipped rounds, the combined maximum price factor is approximately:

```text
1.832897789
```

This is an increase of approximately **83.2898%**. The remaining 418 starting-price block units then represent approximately:

```text
418 / 1.832897789 = 228.054 blocks
```

Using the conservative 266-block window, 228 blocks remain after the earliest possible price update. The batch therefore remains live through the latest target-round claim.

After 756 skipped rounds, the remaining balance represents approximately 227.871 blocks at the increased price, so survival through the complete conservative window is no longer guaranteed. Integer division in the oracle can only reduce the realised increase, so 755 skipped rounds is a conservative guaranteed tolerance under the current constants.

This number is a safety analysis, not an on-chain limit. If a larger catch-up causes a selected batch to expire before proof verification, the target claim rejects that batch normally. No expired-batch data is retained for redistribution.

### Bee behaviour

Before constructing the samples for target round `r`, Bee processes canonical postage events through the block immediately before `samplingStartBlock(r)`. It then applies the same rules as the contracts:

- the batch and applicable depth must have been introduced before sampling began;
- the batch must meet the 456-block threshold calculated from the price and cumulative outpayment at sampling start; and
- only indexes within that historical depth may be sampled.

Bee may reconstruct this state locally from events. The PostageStamp read functions defined by this SWIP are the canonical contract reference. Later creation, top-up, dilution, expiry, or price updates do not change an already constructed target-round sample.

### Batch ID reuse

Expiry continues to remove a batch from the ordered tree and delete its live batch data and depth history. The batch ID remains permanently consumed. Recreating an expired ID could make old signatures usable under a new batch incarnation, so creation and import paths must reject every previously used batch ID.

## Rationale

The design adds one global historical price and two historical depths per batch. It does not add per-round price snapshots, per-batch balance checkpoints, or retained expired batches.

One previous price is sufficient because claims are the only price-update path and the target claim updates the price only after proof verification. Two previous depths are sufficient because only two neighboring sampling-to-claim windows overlap under the current 152-block schedule. The six-round operation minimum prevents later top-ups and dilutions from crossing the 456-block usability boundary fixed for an open round.

## Security considerations

The fixed scope prevents a participant from learning a favorable anchor and then buying a batch or diluting an existing batch to create indexes for that target round.

The pre-top-up check prevents a nearly expired batch from being rescued into an open round. The post-dilution check prevents a usable batch from being forced out by dilution. Historical depth prevents later dilution from expanding the index range used by the claim. Historical price and reordered claim execution ensure that the preceding round's price update does not change the balance criterion used by Bee and the target claim.

The 755-skipped-round figure depends on the current phase lengths and PriceOracle constants. A future change to round length, adjustment rates, or price-update ordering must re-evaluate the 456-block and 912-block parameters.

This SWIP fixes on-chain batch and index usability. It does not guarantee that independent Bee nodes possess identical chunk or stamp sets; content arrival, stamp overwrites, reserve eviction, and sample convergence remain a separate topic.

## Appendix A: `PostageStamp` changes introduced by this SWIP

The entries follow the order of `PostageStamp.sol`. Unchanged code is not repeated.

1. **Add constants and state.**

```solidity
uint64 internal constant REDISTRIBUTION_ROUND_BLOCKS = 152;
uint64 internal constant REDISTRIBUTION_REVEAL_OFFSET = 38;
uint64 internal constant ROUND_USABILITY_BLOCKS = 456;
uint64 internal constant MIN_OPERATION_VALIDITY_BLOCKS = 912;

uint64 public previousPrice;

struct DepthHistory {
    // Most recent superseded depth that was visible at a sampling boundary.
    uint64 previousDepthBlock;
    // One older boundary-visible depth, needed while two round scopes overlap.
    uint64 olderDepthBlock;
    uint8 previousDepth;
    uint8 olderDepth;
}

mapping(bytes32 => DepthHistory) private depthHistory;
mapping(bytes32 => bool) public batchIdUsed;

error BatchIdAlreadyUsed(bytes32 batchId);
error BatchNotUsableForRedistribution(bytes32 batchId);
error FutureSamplingStartBlock();
error MinimumValidityTooShort();
error PriceHistoryUnavailable();
```

2. **Consume every batch ID permanently, enforce the creation minimum on imports, and require the six-round balance before top-up.**

```solidity
function _consumeBatchId(bytes32 batchId) internal {
    if (batchIdUsed[batchId] || batches[batchId].owner != address(0)) {
        revert BatchIdAlreadyUsed(batchId);
    }
    batchIdUsed[batchId] = true;
}
```

```diff
 // createBatch, after deriving batchId
-if (batches[batchId].owner != address(0)) revert BatchExists();
+_consumeBatchId(batchId);

 // copyBatch, after validating owner and depths
-if (batches[_batchId].owner != address(0)) revert BatchExists();
+_consumeBatchId(_batchId);
+if (_initialBalancePerChunk < minimumInitialBalancePerChunk()) {
+    revert InsufficientBalance();
+}

 // topUp
-if (remainingBalance(_batchId) + _topupAmountPerChunk < minimumInitialBalancePerChunk()) {
+if (remainingBalance(_batchId) < minimumInitialBalancePerChunk()) {
     revert InsufficientBalance();
 }
```

3. **Keep two earlier depths and replace `increaseDepth` with the following implementation.**

```solidity
function _firstSamplingStartAfter(uint256 blockNumber)
    internal
    pure
    returns (uint256)
{
    if (blockNumber < REDISTRIBUTION_REVEAL_OFFSET) {
        return REDISTRIBUTION_REVEAL_OFFSET;
    }

    uint256 completedIntervals =
        (blockNumber - REDISTRIBUTION_REVEAL_OFFSET)
            / REDISTRIBUTION_ROUND_BLOCKS;

    return REDISTRIBUTION_REVEAL_OFFSET
        + (completedIntervals + 1) * REDISTRIBUTION_ROUND_BLOCKS;
}

/**
 * @dev Keeps only depths that were actually fixed for at least one round.
 *
 * Assume sampling starts at blocks 190, 342, and 494. With the current
 * schedule, the round sampled from block 190 begins its commit phase at block
 * 304 and can be claimed from block 380 through block 455. The round sampled
 * from block 342 can be claimed later, through block 607. This overlap is why
 * two old depths may be needed at the same time.
 *
 * The batch has depth 20 from block 120 onward:
 *
 * 1. At block 220, the batch is diluted from depth 20 to depth 21.
 *    Sampling already started at block 190 while depth 20 was current. Any
 *    later claim for that round must still validate indexes against depth 20,
 *    so record it as `previousDepth`.
 *
 *        older: -       previous: 20       current: 21
 *
 * 2. At block 260, the batch is diluted again, from depth 21 to depth 22.
 *    The next sampling start is not until block 342. No round fixed depth 21,
 *    so it was only an intermediate live value and does not need a history
 *    slot.
 *
 *        older: -       previous: 20       current: 22
 *
 * 3. At block 360, the batch is diluted from depth 22 to depth 23.
 *    Sampling at block 342 fixed depth 22 for the next target round. At the
 *    same time, the earlier round sampled at block 190 has not finished: its
 *    claim window runs through block 455. A claim for that earlier round must
 *    still reject indexes introduced after depth 20, while the newer round
 *    must use depth 22. Both old depths are therefore needed simultaneously.
 *
 *        older: 20      previous: 22       current: 23
 *
 * 4. At block 400, the batch is diluted from depth 23 to depth 24.
 *    No new sampling start occurred after depth 23 was introduced. The same
 *    two rounds still need depths 20 and 22, so depth 23 is another
 *    intermediate value and the retained history does not change.
 *
 *        older: 20      previous: 22       current: 24
 *
 * 5. At block 510, the batch is diluted from depth 24 to depth 25.
 *    Sampling at block 494 fixed depth 24 for another target round. The round
 *    sampled at block 190 can no longer be claimed because its final claim
 *    block was 455. Depth 20 can therefore be discarded without losing any
 *    state that a future claim may read. Depth 22 remains for the round sampled
 *    at block 342, and depth 24 becomes the newest retained depth.
 *
 *        older: 22      previous: 24       current: 25
 *
 * The code below implements that rule. It finds the first sampling start after
 * `oldDepthBlock`. If the next dilution happens before that sampling start, no
 * round used `oldDepth`, so nothing is recorded. Once that sampling start has
 * arrived, `oldDepth` is retained and the two-slot history is rotated.
 *
 * Equality matters. A dilution included in the sampling-start block is too
 * late to affect that round because the round uses the state at the end of the
 * preceding block. The old depth must therefore be retained.
 *
 * `oldDepthBlock` must be the block in which `oldDepth` became current. Top-ups
 * must not change it.
 */
function _recordDepthBeforeIncrease(
    bytes32 batchId,
    uint8 oldDepth,
    uint256 oldDepthBlock
) internal {
    uint256 firstSamplingStartThatCouldUseOldDepth =
        _firstSamplingStartAfter(oldDepthBlock);

    // If the increase happens before that sampling start, no round used the
    // old depth. Equality is different: an increase in the sampling-start
    // block is too late for that round, which reads the preceding block.
    if (block.number < firstSamplingStartThatCouldUseOldDepth) return;

    DepthHistory storage history = depthHistory[batchId];

    history.olderDepth = history.previousDepth;
    history.olderDepthBlock = history.previousDepthBlock;
    history.previousDepth = oldDepth;
    history.previousDepthBlock = uint64(oldDepthBlock);
}

function increaseDepth(bytes32 _batchId, uint8 _newDepth) external whenNotPaused {
    Batch storage batch = batches[_batchId];

    if (batch.owner == address(0)) revert BatchDoesNotExist();
    if (batch.owner != msg.sender) revert NotBatchOwner();
    if (_newDepth <= minimumBucketDepth || _newDepth <= batch.depth) revert DepthNotIncreasing();

    uint256 outPayment = currentTotalOutPayment();
    uint256 oldNormalisedBalance = batch.normalisedBalance;
    if (oldNormalisedBalance <= outPayment) revert BatchExpired();

    uint8 oldDepth = batch.depth;
    uint256 newRemainingBalance =
        (oldNormalisedBalance - outPayment) / (uint256(1) << (_newDepth - oldDepth));

    if (newRemainingBalance < minimumInitialBalancePerChunk()) revert InsufficientBalance();

    expireLimited(type(uint256).max);

    // `lastUpdatedBlockNumber` is the introduction block of `oldDepth`.
    _recordDepthBeforeIncrease(_batchId, oldDepth, batch.lastUpdatedBlockNumber);

    validChunkCount += (uint256(1) << _newDepth) - (uint256(1) << oldDepth);
    tree.remove(_batchId, oldNormalisedBalance);

    uint256 newNormalisedBalance = outPayment + newRemainingBalance;
    batch.depth = _newDepth;
    batch.lastUpdatedBlockNumber = block.number;
    batch.normalisedBalance = newNormalisedBalance;

    tree.insert(_batchId, newNormalisedBalance);
    emit BatchDepthIncrease(_batchId, _newDepth, newNormalisedBalance);
}
```

4. **Remember the previous price and prevent the configurable operation minimum from falling below 912 blocks.**

```solidity
function setPrice(uint256 _price) external {
    if (!hasRole(PRICE_ORACLE_ROLE, msg.sender)) revert PriceOracleOnly();

    uint64 newPrice = uint64(_price);
    if (lastPrice == 0) {
        previousPrice = newPrice;
    } else {
        totalOutPayment = currentTotalOutPayment();
        previousPrice = lastPrice;
    }

    lastPrice = newPrice;
    lastUpdatedBlock = uint64(block.number);
    emit PriceUpdate(_price);
}

function setMinimumValidityBlocks(uint64 _value) external {
    if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert AdministratorOnly();
    if (_value < MIN_OPERATION_VALIDITY_BLOCKS) revert MinimumValidityTooShort();
    minimumValidityBlocks = _value;
}
```

After activation, `setPrice` is reached only through a redistribution claim.

5. **Delete depth history on expiry, but do not release the batch ID.**

```diff
 tree.remove(fbi, batch.normalisedBalance);
+delete depthHistory[fbi];
 delete batches[fbi];
+// batchIdUsed[fbi] remains true.
```

6. **Add the round-start price, balance, and depth reads used by Bee and `Redistribution`.**

```solidity
function _priceStateAtSamplingStart(uint256 samplingStartBlock)
    internal
    view
    returns (uint64 priceAtStart, uint256 outPaymentAtStart)
{
    if (samplingStartBlock > block.number) revert FutureSamplingStartBlock();

    uint256 priceUpdateBlock = uint256(lastUpdatedBlock);
    if (priceUpdateBlock < samplingStartBlock) {
        return (
            lastPrice,
            totalOutPayment + (samplingStartBlock - priceUpdateBlock) * uint256(lastPrice)
        );
    }

    if (previousPrice == 0) revert PriceHistoryUnavailable();
    uint256 rollback = (priceUpdateBlock - samplingStartBlock) * uint256(previousPrice);
    if (rollback > totalOutPayment) revert PriceHistoryUnavailable();
    return (previousPrice, totalOutPayment - rollback);
}

function redistributionMinimumNormalisedBalance(uint256 samplingStartBlock)
    external
    view
    returns (uint256)
{
    (uint64 priceAtStart, uint256 outPaymentAtStart) =
        _priceStateAtSamplingStart(samplingStartBlock);
    return outPaymentAtStart + uint256(ROUND_USABILITY_BLOCKS) * uint256(priceAtStart);
}

function _depthAtSamplingStart(bytes32 batchId, Batch storage batch, uint256 samplingStartBlock)
    internal
    view
    returns (uint8)
{
    if (batch.lastUpdatedBlockNumber < samplingStartBlock) return batch.depth;

    DepthHistory storage history = depthHistory[batchId];
    if (history.previousDepth != 0 && history.previousDepthBlock < samplingStartBlock) {
        return history.previousDepth;
    }
    if (history.olderDepth != 0 && history.olderDepthBlock < samplingStartBlock) {
        return history.olderDepth;
    }

    revert BatchNotUsableForRedistribution(batchId);
}

function redistributionBatchAt(bytes32 batchId, uint256 samplingStartBlock)
    external
    view
    returns (address owner, uint8 depthAtSamplingStart, uint8 bucketDepth, uint256 normalisedBalance)
{
    Batch storage batch = batches[batchId];
    if (batch.owner == address(0) || batch.normalisedBalance <= currentTotalOutPayment()) {
        revert BatchNotUsableForRedistribution(batchId);
    }

    return (
        batch.owner,
        _depthAtSamplingStart(batchId, batch, samplingStartBlock),
        batch.bucketDepth,
        batch.normalisedBalance
    );
}
```

Add the matching signatures to `IPostageStamp`:

```solidity
function redistributionMinimumNormalisedBalance(uint256 samplingStartBlock)
    external view returns (uint256);

function redistributionBatchAt(bytes32 batchId, uint256 samplingStartBlock)
    external view returns (address owner, uint8 depthAtSamplingStart, uint8 bucketDepth, uint256 normalisedBalance);
```

## Appendix B: `Redistribution` changes relative to the Phase 5 starting diff

The Phase 5 diff already introduces the stamp commitment and proofs, including
the transformed-stamp encoding:

```solidity
keccak256(abi.encodePacked(postageId, index, roundAnchor))
```

That encoding remains unchanged. Only the following additional changes come
from this SWIP.

1. **Add the target-round context.**

```solidity
error InvalidTargetRound();
error BatchNotUsableForTargetRound(bytes32 batchId);

function _samplingStartBlock(uint64 targetRound) internal pure returns (uint256) {
    if (targetRound == 0) revert InvalidTargetRound();
    return uint256(targetRound - 1) * ROUND_LENGTH + ROUND_LENGTH / 4;
}
```

2. **Make `winnerSelection` return the round and redundancy count instead of adjusting the price.**

```diff
-function winnerSelection() internal {
+function winnerSelection() internal returns (uint64 targetRound, uint16 redundancy) {
     uint64 cr = currentRound();
     ...
-    bool success = OracleContract.adjustPrice(uint16(redundancyCount));
-    if (!success) emit PriceAdjustmentSkipped(uint16(redundancyCount));
-    currentClaimRound = cr;
+    return (cr, uint16(redundancyCount));
 }
```

3. **Create one eligibility context in `claim`, use it for every chunk-stamp and stamp-sample proof, and adjust the price only after all proofs.**

```diff
- winnerSelection();
+ (uint64 targetRound, uint16 redundancyCount) = winnerSelection();
+ uint256 samplingStartBlock = _samplingStartBlock(targetRound);
+ uint256 requiredNormalisedBalance =
+     PostageContract.redistributionMinimumNormalisedBalance(samplingStartBlock);

- stampFunction(entryProofLast);
+ stampFunction(entryProofLast, samplingStartBlock, requiredNormalisedBalance);
- stampFunction(entryProof1);
+ stampFunction(entryProof1, samplingStartBlock, requiredNormalisedBalance);
- stampFunction(entryProof2);
+ stampFunction(entryProof2, samplingStartBlock, requiredNormalisedBalance);

- stampInclusionFunction(stampProofLast, 15, _currentRevealRoundAnchor);
+ stampInclusionFunction(
+     stampProofLast, 15, _currentRevealRoundAnchor,
+     samplingStartBlock, requiredNormalisedBalance
+ );
 // Apply the same two added arguments to stampProof1 and stampProof2.

 // After every proof, order check, and density check, before withdraw:
+ currentClaimRound = targetRound;
+ bool adjusted = OracleContract.adjustPrice(redundancyCount);
+ if (!adjusted) emit PriceAdjustmentSkipped(redundancyCount);
```

4. **Replace both live-batch checks with one historical verifier.**

```solidity
function _verifyPostageForTargetRound(
    bytes32 chunkAddress,
    bytes32 batchId,
    uint64 fullStampIndex,
    uint64 stampTimestamp,
    bytes calldata signature,
    uint256 samplingStartBlock,
    uint256 requiredNormalisedBalance
) internal view {
    (
        address batchOwner,
        uint8 depthAtSamplingStart,
        uint8 bucketDepth,
        uint256 normalisedBalance
    ) = PostageContract.redistributionBatchAt(batchId, samplingStartBlock);

    if (normalisedBalance < requiredNormalisedBalance) {
        revert BatchNotUsableForTargetRound(batchId);
    }

    // This is the claim-time proof that the index already existed when
    // sampling began. A later dilution may make a larger index valid under the
    // live depth, but it cannot make that index valid for this target round.
    uint256 indexWithinBucket = getPostageIndex(fullStampIndex);
    uint256 indexCountAtSamplingStart =
        postageStampIndexCount(depthAtSamplingStart, bucketDepth);
    if (indexWithinBucket >= indexCountAtSamplingStart) {
        revert IndexOutsideSet(batchId);
    }
    if (getPostageBucket(fullStampIndex) != addressToBucket(chunkAddress, bucketDepth)) {
        revert BucketDiffers(batchId);
    }
    if (!Signatures.postageVerify(
        batchOwner, signature, chunkAddress, batchId, fullStampIndex, stampTimestamp
    )) {
        revert SigRecoveryFailed(batchId);
    }
}

function stampFunction(
    ChunkInclusionProof calldata entryProof,
    uint256 samplingStartBlock,
    uint256 requiredNormalisedBalance
) internal view {
    _verifyPostageForTargetRound(
        entryProof.proveSegment,
        entryProof.postageProof.postageId,
        entryProof.postageProof.index,
        entryProof.postageProof.timeStamp,
        entryProof.postageProof.signature,
        samplingStartBlock,
        requiredNormalisedBalance
    );
}
```

In the Phase 5 `stampInclusionFunction`, keep its BMT proof unchanged, add the two context arguments, delete the direct `PostageContract.batches(...)` validation block, and call:

```solidity
_verifyPostageForTargetRound(
    stampProof.chunkAddress,
    stampProof.postageId,
    stampProof.index,
    stampProof.timeStamp,
    stampProof.signature,
    samplingStartBlock,
    requiredNormalisedBalance
);
```

