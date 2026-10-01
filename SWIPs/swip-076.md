---
swip: 76
title: megatree-1 (MT-1)
author: lat-murmeldjur, Zelig
status: Draft
type: Standards Track
category: Storage Incentives
created: 2026-09-29
requires: SWIP-049
---

# SWIP 76 - megatree-1 (MT-1)

## Problem statement

The chunk sample and reserve proof serve different purposes. The sample lets nodes report agreement about the selected neighbourhood. The reserve proof tests each reported inventory and determines selection weight, used to select the agreement value and divide payment.

SWIP-050's Sequential Transformation Scheme (STS) links a stamp sample to an earlier transformed-chunk commitment through selected witnesses. These provide the density and utilization signals that adjust each participant's weight.

SWIP 76 replaces that construction with megatree-1 (MT-1), a counted reserve tree. Each leaf pairs a transformed stamp address with its transformed chunk address. The root commits to the inventory and reported size. Two unpredictable, distinct positions then select the entries to prove.

The separate sample retains the sixteen lowest transformed chunk addresses. Its hash and reported depth form the Schelling point, the agreement value submitted for selection. Sample entries are not proved; every participant must instead prove both selected tree entries to receive weight.

## Motivation

A sample-based reserve estimate varies with the sampled values. Larger samples reduce variance, but more full witnesses increase participation cost.

The counted tree tests positions directly. One random position is provable with probability equal to the supported fraction; two distinct positions give approximately its square for a large inventory. A fully provable tree faces no additional rejection from a sample-based density threshold.

One transaction submits both full witnesses, retaining the chunk-transformation check and density/utilization curves.

## The megatree

Each inventory entry is an eligible postage-stamp slot, identified by its batch and full index and authorizing a chunk. Its leaf contains:

```text
stampKey = keccak256(anchor || batchId || fullStampIndex)
leaf = (stampKey, transformedChunkAddress)
```

The round's anchor transforms stamps and chunks; no extra label enters the stamp hash. The existing round-keyed Binary Merkle Tree (BMT) transformation derives the chunk value from its data, not merely its ordinary address. Changing a timestamp or replacing a chunk creates no new slot. Separate slots may authorize the same chunk.

Leaves are arranged by the leading bits of their stamp keys. Where keys first differ, bit zero goes left and bit one goes right. Shared leading bits are recorded in the branch rather than expanded into a chain of one-child nodes. This is a compressed binary prefix tree; bit positions still refer to the full key.

Each leaf counts as one. A branch commits to its shared prefix, splitting position, ordered child hashes and populations; its population is their sum. The root commits to the inventory and total count `N`. The minimum `N_min` is at least two and is the same at every supported neighbourhood depth.

Construction excludes empty children, one-child branches and duplicate keys. Appendix A fixes the encoding; Bee storage choices must not change the root.

## The two witnesses

After commitment, each participant receives two different random positions, called ranks, between `0` and `N - 1`. At a branch, go left if the rank is below the left child's population. Otherwise go right after subtracting that population. The remaining rank is now a position within the selected child, not the whole tree. At a leaf, only one position remains, so this local rank must be zero even when the original challenge was not.

A uniform rank gives every entry the same chance. With six leaves left and two right, descent goes left 75% of the time and right 25%. Choosing each branch 50% of the time would test each leaf in the smaller subtree more often.

The contract derives the pair from the participant's recorded identity, inventory and the later audit seed. Ranks cannot repeat within one pair. Different participants get separate draws and may select the same ranks, even with identical trees. No list of other participants' assigned ranks is needed, and callers cannot provide an extra value to change their draw. Retries use the same challenges.

Each witness proves its leaf's assigned rank, root and count, then checks SWIP-049 eligibility, stamp authorization, bucket assignment and chunk neighbourhood. Ordinary and transformed BMT paths share the challenged segment, span (logical length) and first sibling (the adjacent segment), linking the stamped chunk to the leaf's transformed value.

For a single-owner chunk (SOC), a signed wrapper links its content to the outer address used by the stamp and neighbourhood check; its transformation includes this relationship. Distinct ranks require distinct stamp slots, not chunks or batches. Both witnesses must pass before weight is recorded. Other leaves and the chunk sample remain unproved.

## The chunk sample

The sixteen lowest transformed chunk addresses form the sample under the inherited client convention. Participants commit to and reveal:

```text
(chunkSampleHash, claimedDepth)
```

The witnesses need not refer to sample entries. Different roots, counts and utilization values can accompany the same agreement value; participants still prove independently.

The sample encourages agreement after stamp rewrites, without proving freshness or completeness. Its encoding is the content-addressed chunk (CAC) address of sixteen ordered `(ordinaryAddress, transformedAddress)` pairs, not a flat hash of transformed values.

Before activation, settle shared timestamp-cutoff, replacement and duplicate-content rules, including behavior with fewer than sixteen distinct chunks. Padding and shorter samples are not authorized here.

## Expanded explanation

### Counts and distinct positions

Suppose the left subtree reports 1.3 million entries and the right reports 1.7 million. Challenge 2.3 million goes right, subtracting 1.3 million and leaving position 1 million within that subtree. Repeat until reaching a leaf. At every opened branch, the two child counts must sum to the parent count.

Sibling hashes and counts are supplied without opening their contents. Unsupported positions still count and can be challenged.

When branching at consecutive bits, left-right-left-left requires prefix `0100`. In a compressed tree, the stored common bits and absolute splitting positions supply any skipped bits. Two different routes eventually require opposite values at one bit; the same stamp key cannot satisfy both. A timestamp or chunk change leaves that key unchanged, and a leaf cannot claim more than one position. This relies on the hash commitment preventing different branch data from being substituted under the same root. Different stamp slots may still authorize the same chunk.

### Eight claimed positions, four real entries

This balanced example has eight positions:

```text
                         root: 8
                     /             \
                   0: 4            1: 4
                 /      \        /      \
               00: 2   01: 2   10: 2   11: 2
                / \     / \     / \     / \
               A   x   B   x   x   C   x   D
rank           0   1   2   3   4   5   6   7
stamp prefix  000 001 010 011 100 101 110 111
```

`A`, `B`, `C` and `D` have valid stamps and chunks. Each `x` is included in the commitment but cannot pass the full checks.

For challenge **5**, descent is:

```text
root: 5 >= 4  -> right, remaining position 1
1:    1 < 2   -> left,  remaining position 1
10:   1 >= 1  -> right, remaining position 0
101:  leaf C, population 1
```

Opening `C` passes this witness. A second rank of **2** reaches `B`, so `(5, 2)` passes; **6** reaches `x` at `110`, so `(5, 6)` fails entirely. Substituting `C` fails the second rank and prefix.

Ranks 0, 2, 5 and 7 are provable. Of 8 * 7 ordered pairs with distinct ranks, 4 * 3 contain only provable positions. For `G` provable positions among `N` committed positions:

```text
passRate = G * (G - 1) / (N * (N - 1))

4/8 * 3/7 = 3/14 = approximately 21.43%
```

Fewer than two provable positions cannot pass. For large inventories the rate approaches `(G / N)^2`; exactly 25% here would allow selecting the same position twice. Entries cannot move after the challenge. Passing earns weight, not a guaranteed win or validation of every position.

### Several participants sharing a padded tree

A padded tree includes claimed positions that cannot supply valid witnesses. For `m` fixed participants receiving independently derived pairs:

```text
p = G * (G - 1) / (N * (N - 1))
probability all m pass = p^m
expected number passing = m * p
```

Two participants both pass the eight-position example with probability `(3/14)^2`, about 4.59%. For a large half-supported tree, one passes with about 25%, two both pass with 6.25%, and four all pass with 0.39%. A shared pair would let the entire group pass with probability `p`. Separate draws remove this shared lucky outcome, not each node's individual pass rate; they do not prove separate physical copies.

## Building the megatree in Bee

### Construct the commitment

Once the round's sampling anchor is confirmed, Bee collects the stamp slots eligible at that round's sampling boundary. It selects the exact authorized stamp and chunk version for each slot under the shared client convention, then calculates the transformed stamp key and chunk value. Duplicate slot keys must be resolved before tree construction, not counted twice. Transformations can be reused for the separate sixteen-entry sample and for different stamps referencing the same chunk version under the same anchor.

Bee sorts compact leaf records by stamp key and builds the compressed tree bottom-up, calculating each subtree's hash and population. Sorting moves metadata rather than chunk payloads; bounded processing and disk-backed records can limit memory use. The root, count, sample hash, depth and nonce (a secret value opened at reveal) determine the commitment. Bee need not prepare every leaf's proof in advance.

### Retain the committed snapshot

Before broadcasting, Bee durably records the round, anchor, root, count, reveal data and ordered-leaf references. This is the round's snapshot: the exact inventory against which later proofs must be made. Each leaf must remain connected to its original stamp and chunk version, including any SOC wrapper. A lookup after a rewrite must not silently return replacement data. Retention must survive eviction, overwrites and restart, sharing unchanged data where possible and preserving referenced versions before replacement.

Bee also retains enough subtree information to recover paths efficiently. It can cache selected subtree roots and their leaf ranges, then rebuild only the ranges containing the two challenged leaves, reusing shared work. It need not retain every internal node or every chunk's BMT. Reconstructed paths must reproduce the committed tree, not a newly shaped one.

### Recover and submit the witnesses

After its reveal, Bee derives both ranks and segment challenges from the recorded round and participant state. Rank `j` identifies ordered leaf `j`. Bee retrieves the exact source records, reconstructs their counted paths and builds the ordinary/transformed BMT paths for each selected chunk version. The same chunk can reuse local BMT construction, but both assigned segments must still be proved.

This avoids rescanning the live reserve. Bee checks the paths against its root and count, then submits both witnesses in assigned order in one transaction. Shared path nodes are included twice; the excerpt does not define a combined proof format. Retries use the same pair and segments. Next-round construction must leave this snapshot intact. Keep it until the participation obligation has ended and the chosen chain-reorganization recovery window has passed. Storage layout, cache depth and scheduling remain Bee choices.

## Round structure

Each round has 152 blocks. For a round starting at `B`, the block containing a transaction determines its phase:

| Phase | Blocks | Offsets, inclusive | Action |
|---|---:|---|---|
| Commit | 19 | 0-18 | Fix sample, depth, root and count. |
| Reveal | 19 | 19-37 | Open commitment; first success fixes audit seed and next anchor. |
| Proof | 76 | 38-113 | Prove both ranks; first complete success fixes selection seed. |
| Claim | 38 | 114-151 | Select, pay matching proved participants and finalize. |

Phases never end early or shift with transaction arrival. All nineteen commit blocks are usable; transactions must be included, not merely broadcast, before their deadlines. Round zero has no preceding sampling round and is excluded.

### Sampling boundary

A round's sampling scope is its historical eligibility state at a fixed boundary: the first scheduled block of the preceding reveal phase, which supplies the anchor:

```text
round = floor(blockNumber / 152)
samplingStart(r) = (r - 1) * 152 + 19 = roundStart(r) - 133
```

Creation or dilution in that block cannot introduce eligible slots. A late reveal or fallback anchor does not move the boundary. Read metadata from before that block, but calculate rent accumulated up to the boundary itself.

Commit closes at `B + 19`: 152 blocks after the earliest preceding reveal, 134 after the latest, or 133 after no-reveal confirmation. Those windows also cover observation, finality and transaction inclusion, not just computation.

For `B = 1,520`: sampling starts at 1,387; commit is 1,520-1,538, reveal 1,539-1,557, proof 1,558-1,633, claim 1,634-1,671. Next-round sampling starts at 1,539; its commits start at 1,672.

### Stage requirements

Commit binds participant, inventory and sample fields to the round, contract and chain. Existing staking-age, minimum-depth and overlay checks remain; only accepted commitments create an obligation to finish.

Reveal checks the committed fields and `N >= N_min >= 2`, but gives no weight. Both witnesses must pass before offset 114. Failed submissions may retry the same challenges; duplicate successes are rejected. There is no partial credit or separate witness transaction.

Claim checks cancellation and uses completed proofs, without repeating them or batch-liveness checks. Payment failure reverts settlement and penalties for retry. A preferred caller may reduce duplicate effort, but claim remains open to anyone.

## Anchor and randomness

The anchor determines the neighbourhood, stamp keys, chunk transformations and sample. The audit seed determines witness challenges; the selection seed chooses the agreement value. Here `hash` means Keccak over Appendix A's exact ABI types.

### First successful reveal

```text
updatedSeed = hash(anchor(r), revealBlockPrevrandao)
anchor(r + 1) = updatedSeed
auditSeed(r) = updatedSeed
```

`prevrandao` is the block's supplied randomness. The current anchor stays fixed; the updated seed supplies witness challenges and next-round sampling, which Bee can begin immediately. Later reveals cannot replace it. During proof and claim, upcoming-participation views use `nextSeed()`; current witnesses use the saved anchor.

Each participant derives:

```text
participantSeed = hash(auditSeed(r), r, owner, overlay, root, N)
seed0 = hash(participantSeed, uint256(0))
seed1 = hash(participantSeed, uint256(1))
rank0 = uniform(seed0, N)
t = uniform(seed1, N - 1)
rank1 = t + (t >= rank0 ? 1 : 0)
segment0 = integer(hash(seed0)) % 128
segment1 = integer(hash(seed1)) % 128
```

Identity and inventory fields come from the accepted record. `uniform` converts a seed into a rank without favouring any position, using deterministic rejection sampling as specified in A.2. The second draw skips `rank0`, selecting uniformly from the other positions. Submit witness 0 first and witness 1 second, even when `rank1` is smaller. Each segment is derived by hashing its full witness seed, not the reduced rank. Segment numbers may coincide; ranks within a pair cannot.

### First successful proof

Only after both witnesses pass and their combined weight is calculated:

```text
selectionSeed(r) = hash(auditSeed(r), r, proofBlockPrevrandao)
```

The first prover sets the seed, not the winner. Later proofs and claim cannot change it; reverting the transaction undoes initialization. Boolean flags distinguish unset seeds from initialized hashes that happen to equal zero.

### Missing phases and fallback

No reveal means no audit challenge; no proof means no selection seed or winner. A predictable fallback cannot supply the missing audit challenge. A next-round seed established by reveal survives missed proof/claim and cancellation.

To obtain anchors after skipped rounds, retain a checkpoint `(S, k)`: seed `S` is the anchor first used by round `k`.

```text
anchor(k) = S
anchor(r) = keccak256(S || uint256(r - k))     for r > k
```

Each fallback hashes the saved seed with the skip count, not the previous fallback. It is provisional until the preceding reveal window closes or a successful reveal replaces it. Active rounds retain their saved anchors. Pause preserves the checkpoint; resumption waits for a clean sampling boundary.

## Weight and payment

Density uses the root count. For utilization, normalize each proved within-bucket index against its historical capacity, then average the ratios:

```text
density = min(32, cubeRoot(N / N_min))
u0 = (index0 + 1) / capacity0
u1 = (index1 + 1) / capacity1
u = (u0 + u1) / 2
utilization = min(32, max(1, cubeRoot(1 / (2 * u))))
weight = effectiveStake * 2^(claimedDepth - height)
         * density * utilization
```

Density is 1 at the minimum, about 1.2599 at twice it and 2 at eight times. Utilization is 1 at `u = 1/2`, and 2 at `u = 1/16`; it signals index position relative to capacity, not measured occupancy. Separate 32-fold caps allow a combined 1,024-fold multiplier. Average the ratios, not raw indexes or calculated bonuses. Appendix A specifies downward rounding with Q64 fixed-point numbers, which represent a value multiplied by `2^64`. Missing either witness gives zero weight.

After proof closes, visit participants in original accepted-commit order. Skip unproved entries without renumbering later ones:

```text
runningWeight = 0
for each proved participant at original commit index i:
    runningWeight += weight[i]
    draw = hash(selectionSeed, i)
    if uniform(draw, runningWeight) < weight[i]:
        selected = participant[i]
```

Each proved participant has a weight-proportional chance to replace the current selection. The final selected participant supplies `(chunkSampleHash, claimedDepth)`. All proved participants matching both fields share the pot by final weight: weights 2, 3 and 5 receive 20%, 30% and 50% before rounding. There is no second lottery for a sole recipient.

Claim reads the Postage pot once and pays directly. Rounding remainders stay in the pot; recipients need no withdrawal transaction. Neither caller nor claim-block randomness affects selection, so unchanged state gives the same result on retry.

## Finalization and cancellation

An accepted commitment is unfinished until both witnesses pass. Ordinary penalties use the selected proved participant's depth, or a configured no-truth depth when nobody proved:

```text
freezeBlocks = categoryMultiplier * 152 * 2^penaltyDepth
```

| Outcome | Treatment |
|---|---|
| Proved match | Proportional payment; no disagreement freeze. |
| Proved disagreement | No payment; configured disagreement penalty. |
| Accepted but unproved | No weight; unfinished-participation penalty. |
| Proofs but no claim | Finalize against completed proofs without payment. |
| No proof | Finalize using configured no-truth depth. |
| Exceptional cancellation | No penalty or remaining obligation from that scope. |

Each penalty category has a separate multiplier; zero disables it. Disagreement uses a per-commit-index draw from the selection seed, not a shared claim-block draw. Configure its probability and no-truth policy explicitly.

A freeze records a future block until which the stake is frozen. New penalties start at finalization, must not shorten a longer existing freeze, and must not be applied twice. The inherited admission check also requires that stored marker to be more than 304 blocks old, so reaching the freeze-end block does not immediately restore eligibility.

Before array reuse, anyone may finalize or cancel the old round as appropriate. That cleanup must persist even if it freezes the caller and prevents their new commitment. A transaction may therefore complete cleanup without accepting participation; Bee must check acceptance and retry. Proved entries are not unfinished merely because claim was missed. Unpaid funds remain shared, not reserved as individual credits.

Exceptional price changes or pause cancel affected unsettled sampling scopes. From offset 19, next-round sampling has already begun and can also be affected. Check cancellation before historical reads, proofs, settlement and later penalties. Participants need not submit another transaction to receive the exemption; it neither reimburses gas nor removes unrelated penalties.

Resume at a scheduled sampling boundary after invalidation; never reopen a paid round. Once the old round is finalized or cancelled, mark its records inactive and reset round flags. Keep the seed checkpoint and long-lived settings/history. Cancellation of very old unfinalized rounds remains undecided.

## Relationship to SWIP-049

SWIP-049 supplies historical eligibility, balance requirements, depth retention and price history. PostageStamp need not understand redistribution phases or pause state.

`PO(a, b)` is the number of leading bits shared by two addresses:

```text
PO(overlay, anchor) >= claimedDepth - height
PO(chunkAddress, anchor) >= claimedDepth
bucketDepth >= claimedDepth
```

Depth is at most 16. Height relaxes only overlay admission, not chunk proximity. The bucket-depth rule ensures whole buckets fit inside the neighbourhood, so their eligible indexes can be determined from historical capacity.

Require the balance for 456 blocks at the starting price, calculated at the sampling boundary, and batch liveness at proof. SWIP-049's operation minimum remains 912 blocks at the live price.

Before activation, depth-history retention must use offset 19 instead of 38 so eligibility can be reconstructed at the new boundary. Missing history cancels the affected scope. Price feedback counts matching proved recipients, not their weight. SWIP-049 must synchronize prices after manual changes and limit work for missed adjustments. Skipped updates must not modify history; cancelling the next scope must not undo a valid payout.

## Limits and activation

MT-1 commits to a population; it does not prove that every eligible stamp was included, that nodes hold independent copies or that their data is available to others. The chunk check remains sampled. The chunk-sample hash is not independently verified, so a competing value can win; majority weight does not guarantee selection.

With supported count and utilization distribution held fixed, adding unsupported positions reduces expected admitted weight approximately as `N^(-5/3)` for large inventories below the density cap: the density bonus grows more slowly than the two-witness pass rate falls. This does not establish resistance to omitting valid entries. With five million valid entries, a minimum of 2.5 million and equal halves at normalized indexes `1/2` and `1/16`, the expected multiplier is about 1.7081. Committing only the low-index half gives 2 and always passes. Splitting stake across independently challenged identities can also change expected proportional payment.

After the first proof reveals selection randomness, later participants can still choose whether to submit their proofs. Both first-success triggers depend on transaction inclusion and block randomness, which is available during execution. Penalties make withholding costly but do not eliminate this influence.

Keep existing arrays and helpers, updating phase-sensitive views and every reader of reused slots. Bound admission and measure cleanup, expiry and oracle work. A stake snapshot alone does not reserve its backing for the participation obligation. Before activation, fix `N_min`, admission/penalty settings, no-truth depth, client sample/version rules and the initial anchor. Appendix A fixes count, path and arithmetic bounds.

Before activation, test encodings, rounds, interruptions, size and gas. Start from a new, unaffected sampling boundary; old commitments or discarded history cannot be reinterpreted. Appendix A is not a standalone audited contract.

## Appendix A: Core implementation excerpts

Apply these changes inside **`Redistribution.sol`** and **`PostageStamp.sol`**, adding the payment signature to the existing interface. Keep dependencies, access control, reusable arrays and helpers. No replacement contract or participant registry is proposed; SWIP-049 supplies historical postage and price integration.

The encodings below are protocol rules, but these are integration excerpts, not a complete compilable contract. Update Bee's bindings for `ReserveProof[2]` and the two-rank challenge.

### A.1 Reuse existing state and entry points

Keep `currentCommits`, `currentReveals` and the `Commit.revealIndex` link. Add these fields to `Reveal`:

```solidity
bytes32 reserveRoot;
uint64 reserveCount;
bool proved;
```

`stakeDensity` stores the final weight: set it to zero at reveal and write it only after both witnesses pass. Keep the admitted stake and height in `Commit`.

An array's allocated length may exceed the number of entries used in the current round. Track that active count separately, reusing existing counters where available:

```solidity
uint256 private commitsLength;
uint256 private revealsLength;
bytes32 private auditSeed;
bytes32 private selectionSeed;
bool private auditSeedSet;
bool private selectionSeedSet;
bool private roundFinalized;
uint256 private requiredNormalisedBalance; // Historical eligibility result for this scope
```

Every loop must stop at the active count, not the allocated length, to avoid reading old-round entries. Configure `uint64 minimumReserveCount >= 2` in the existing style and keep it fixed throughout each admitted scope. The arithmetic below assumes no more than 256 participants, depth at most 16 and effective stake fitting `uint128`; enforce these bounds at admission.

Use phase end offsets 19, 38, 114 and 152, excluding each end offset from the preceding phase. Keep `ROUND_LENGTH = 152` and `currentRound()`, but remove the old last-commit-block exclusion:

```solidity
function currentPhaseProof() public view returns (bool) {
    uint256 offset = block.number % ROUND_LENGTH;
    return offset >= 38 && offset < 114;
}

function _samplingStartBlock(uint64 round) internal pure returns (uint256) {
    if (round == 0) revert InvalidTargetRound();
    return uint256(round - 1) * ROUND_LENGTH + 19;
}
```

The existing anchor reader also needs to recognize proof. Insert this at the start of `currentRoundAnchor()`, before the condition handling rounds with no reveal:

```solidity
if (currentPhaseProof() || currentPhaseClaim()) return nextSeed();
```

This reader serves upcoming participation during proof and claim. Current witnesses instead use the saved `currentRevealRoundAnchor`. Without the new branch, the old reader can return zero during proof after a reveal, or the current fallback when it should return the next one. Retain its commit/pre-first-reveal behavior and later-reveal guard. Bee can call `nextSeed()` as soon as the first reveal establishes it.

Save the current anchor before updating the seed checkpoint. Finish or cancel old participation obligations before resetting active counts and round flags. Reuse reveal slots as follows:

```solidity
uint256 revealIndex = revealsLength++;
if (revealIndex == currentReveals.length) currentReveals.push();
Reveal storage entry = currentReveals[revealIndex];
// Assign ALL existing fields plus reserveRoot, reserveCount and proved=false.
// Set stakeDensity=0; store revealIndex in the accepted Commit.
```

Apply the same pattern to commits, assigning every field so no old owner, flag, index or weight survives. Update `findCommit`, uniqueness scans, event counts and returned lists to read only active entries. `currentRoundReveals()` must exclude unused trailing slots.

Truth and recipient views must use the proved-only selection in A.6. Do not leave `isWinner` exposing the former second lottery. Preserve the last paid truth used by `currentMinimumDepth()`; clearing round arrays must not erase that longer-lived state or unresolved obligations.

### A.2 Commitment and randomness

Use Ethereum Keccak-256 over binary values. The tuples here use `abi.encode`, which allocates 32-byte words. Round and count are `uint64`, depth is `uint8`, owner is an address and hashes are `bytes32`. Both clients must use the same types and field order. Extend `wrapCommit` while retaining chain, contract, round and participant binding:

```solidity
function wrapCommit(
    uint64 round, address owner, bytes32 overlay, uint8 depth,
    bytes32 sample, bytes32 root, uint64 count, bytes32 nonce
) public view returns (bytes32) {
    return keccak256(abi.encode(
        block.chainid, address(this), round, owner,
        overlay, depth, sample, root, count, nonce
    ));
}
```

The hash input is 320 bytes; the resulting commitment is 32 bytes. Commit records stake, height, owner and overlay after admission checks. Reveal verifies this preimage and `count >= minimumReserveCount >= 2`. It then initializes audit randomness once, replacing the old separate `updateRandomness()` call:

```solidity
// Inside the first accepted reveal, after its commitment check.
if (!auditSeedSet) {
    seed = keccak256(abi.encode(currentRevealRoundAnchor, block.prevrandao));
    currentRevealRound = round;
    auditSeed = seed;
    auditSeedSet = true;
    emit AuditOpened(round, auditSeed);
}
```

Together, `seed` and `currentRevealRound` record the checkpoint from which future anchors are derived. Its first consuming round is `currentRevealRound + 1`. Keep the checkpoint through array reuse and cancellation. The current proof uses the saved current anchor; `auditSeed` stores the next-round anchor value for deriving current challenges.

The commit index locates the record; it is not an extra challenge input. Use the saved owner even when someone else queries the challenge:

```solidity
function _challenge(
    uint64 round, address owner, Reveal storage entry
) internal view returns (uint64[2] memory ranks, uint8[2] memory segments) {
    if (entry.reserveCount < 2) revert InvalidRange();
    bytes32 participantSeed = keccak256(abi.encode(
        auditSeed, round, owner, entry.overlay,
        entry.reserveRoot, entry.reserveCount
    ));
    for (uint256 i; i < 2; ) {
        bytes32 witnessSeed = keccak256(abi.encode(participantSeed, i));
        uint64 rank = uint64(_uniform(witnessSeed, entry.reserveCount - i));
        if (i == 1 && rank >= ranks[0]) ++rank;
        ranks[i] = rank;
        segments[i] = uint8(uint256(keccak256(abi.encode(witnessSeed))) & 127);
        unchecked { ++i; }
    }
}

function _uniform(bytes32 challenge, uint256 bound) internal pure returns (uint256) {
    if (bound == 0) revert InvalidRange();
    uint256 threshold = addmod(type(uint256).max, 1, bound);
    uint256 value = uint256(challenge);
    uint256 attempt;
    while (value < threshold) {
        value = uint256(keccak256(abi.encode(challenge, ++attempt)));
    }
    return value % bound;
}
```

`threshold` is `2^256 mod bound`. Values below it are discarded because direct modulo reduction would give some ranks one extra possible input. Each retry hashes the original witness seed with counter 1, 2, and so on. This is deterministic: it does not let a participant request a new random draw.

The participant preimage is 192 bytes. Each witness seed hashes 64 bytes, ending in `uint256(0)` or `uint256(1)`. Each segment hashes the original 32-byte witness seed, not the rank or a rejection-sampling retry. The second rank skips the first, and witnesses must stay in their assigned order.

No state tracks ranks already assigned to other participants, because overlap across participants is allowed. Nor may callers provide an extra seed input to change their challenge. A.6 initializes selection only after both witnesses and weight calculation, using `keccak256(abi.encode(auditSeed, round, block.prevrandao))`. That 96-byte input excludes witness bytes and the prover address. A reverted transaction preserves no initialization; later successes cannot replace the seed. Guard challenge views against stale or unrevealed records and update Bee's bindings.

### A.3 Counted-prefix verifier

Unlike the ABI tuples above, tree hashes use tightly packed, fixed-width fields. Integers are **big-endian**; key bits are numbered from the most significant bit, `0..255`. Hash the binary bytes, not their hexadecimal text:

```text
stampKey: anchor32 || batchId32 || fullStampIndex8             (72 bytes)
leaf:     0x00 || stampKey32 || transformedChunk32             (65 bytes)
branch:   0x01 || splitBit1 || prefix32
               || leftHash32 || leftCount8
               || rightHash32 || rightCount8                (114 bytes)
```

`prefix` contains the key bits before `splitBit`, with every remaining bit zeroed. A root splitting at bit 3 after common bits `101` stores `101` followed by zeros. Compression skips nodes, not bit numbers.

Sort distinct keys. Split each non-singleton range at the first differing bit of its smallest and largest keys; a singleton is hashed directly as a leaf. Do not balance by entry count, sort child hashes, duplicate leaves for padding, or add empty/one-child nodes: those would produce a different tree.

Supply proof steps from **leaf to root**, with decreasing absolute splitting positions. The opened key determines the branch direction and common prefix at each step:

```solidity
struct TreeStep {
    bytes32 siblingHash;
    uint64 siblingCount;
    uint8 splitBit;
}

error InvalidTree();
error InvalidRange();

function _branchHash(
    uint8 bit, bytes32 prefix,
    bytes32 left, uint64 leftCount, bytes32 right, uint64 rightCount
) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(
        bytes1(0x01), bit, prefix, left, leftCount, right, rightCount
    ));
}

function _verifyTree(
    bytes32 root, uint64 totalCount, uint64 expectedRank,
    bytes32 key, bytes32 transformedChunk, TreeStep[] calldata path
) internal pure {
    if (totalCount == 0 || expectedRank >= totalCount || path.length > 256)
        revert InvalidTree();
    bytes32 hash = keccak256(abi.encodePacked(bytes1(0x00), key, transformedChunk));
    uint256 count = 1;
    uint256 rank;
    uint256 previousBit = 256;
    for (uint256 i; i < path.length; ) {
        TreeStep calldata step = path[i];
        uint256 bit = step.splitBit;
        if (bit >= previousBit || step.siblingCount == 0) revert InvalidTree();
        uint256 suffixBits = 255 - bit;
        if (suffixBits < 64) {
            uint256 capacity = uint256(1) << suffixBits;
            if (count > capacity || step.siblingCount > capacity) revert InvalidTree();
        }
        uint256 nextCount = count + step.siblingCount;
        if (nextCount > type(uint64).max) revert InvalidTree();
        bytes32 prefix = bit == 0 ? bytes32(0) :
            bytes32(uint256(key) & (type(uint256).max << (256 - bit)));
        if (((uint256(key) >> suffixBits) & 1) != 0) {
            rank += step.siblingCount;
            hash = _branchHash(step.splitBit, prefix,
                step.siblingHash, step.siblingCount, hash, uint64(count));
        } else {
            hash = _branchHash(step.splitBit, prefix,
                hash, uint64(count), step.siblingHash, step.siblingCount);
        }
        count = nextCount;
        previousBit = bit;
        unchecked { ++i; }
    }
    if (hash != root || count != totalCount || rank != expectedRank)
        revert InvalidTree();
}
```

The verifier starts with one leaf, population one and local rank zero. Moving upward, it adds sibling populations to the count, and adds a left sibling's population to the rank whenever the opened subtree lies on the right. At the root, hash, population and original challenged rank must all match.

An empty path can therefore verify only a one-leaf tree at rank zero. Participation separately requires at least two entries. An unopened sibling's hash and count are authenticated, but its contents are not checked by this proof; its positions can still be selected by another challenge. A library that sorts each pair of hashes cannot replace this directed verifier.

One step occupies 41 tightly packed bytes, but 96 bytes in ordinary ABI calldata. A packed calldata decoder is only an optional optimization after measuring its cost. Proofs may contain 256 steps; a typical logarithmic path length is not an accepted maximum.

### A.4 Connect existing stamp and chunk checks

Reuse `PostageProof`, `SOCProof`, `BMTChunk`, `TransformedBMTChunk`, `Signatures`, the bucket/index helpers and `inProximity`. Remove the former chunk-sample membership and ordering checks, not the selected inventory chunk's transformation check. Suggested input:

```solidity
struct ReserveProof {
    PostageProof postageProof;
    bytes32 chunkAddress;             // CAC address or outer SOC address
    bytes32 segment;
    uint64 chunkSpan;
    bytes32[] ordinarySiblings;       // exactly seven
    bytes32[] transformedSiblings;    // exactly seven
    SOCProof[] socProof;              // zero or one existing wrapper
    TreeStep[] path;
}
```

Submit two of these records in assigned rank order. Their stamps must identify different slots, but may share a batch or chunk. Derive each leaf's transformed value using the existing helpers:

```solidity
error InvalidReserveProof();

function _transformedChunk(
    ReserveProof calldata proof, uint8 segmentIndex, bytes32 anchor
) internal pure returns (bytes32 transformed) {
    if (segmentIndex >= 128 || proof.ordinarySiblings.length != 7 ||
        proof.transformedSiblings.length != 7 || proof.socProof.length > 1)
        revert InvalidReserveProof();
    if (proof.ordinarySiblings[0] != proof.transformedSiblings[0])
        revert InvalidReserveProof();

    bytes32 ordinary = BMTChunk.chunkAddressFromInclusionProof(
        proof.ordinarySiblings, proof.segment, segmentIndex, proof.chunkSpan
    );
    transformed = TransformedBMTChunk.transformedChunkAddressFromInclusionProof(
        proof.transformedSiblings, proof.segment, segmentIndex, proof.chunkSpan, anchor
    );
    if (proof.socProof.length == 0) {
        if (ordinary != proof.chunkAddress) revert InvalidReserveProof();
    } else {
        SOCProof calldata soc = proof.socProof[0];
        if (soc.signer == address(0) || soc.chunkAddr != ordinary ||
            calculateSocAddress(soc.identifier, soc.signer) != proof.chunkAddress)
            revert InvalidReserveProof();
        if (!Signatures.socVerify(soc.signer, soc.signature, soc.identifier, ordinary))
            revert InvalidReserveProof();
        transformed = keccak256(abi.encode(proof.chunkAddress, transformed));
    }
}
```

The BMT has 128 segments even for a short payload, with unwritten bytes zero-padded. Pass `chunkSpan` as a numeric ABI `uint64`; the existing helpers convert it to eight **little-endian** bytes for hashing. Reversing it before ABI encoding would reverse it twice. The span describes logical content length, which need not equal this chunk's payload length.

For an ordinary CAC, the reconstructed content address must equal the stamped address. For an SOC, the reconstructed address belongs to its wrapped content; the owner signature and identifier connect that content to the stamped outer address. The final SOC transformation includes this outer address rather than equating it with the content address.

SWIP-049's `_verifyPostageForTargetRound` checks history, liveness, balance, bucket alignment and authorization. Return the capacity and bucket depth already obtained by those checks, instead of querying them again. The caller then checks `bucketDepth >= claimedDepth` and full-depth chunk proximity.

The eight-byte index is `(uint64(bucket) << 32) | counter`: bucket `0x1234` and counter 7 encode as `0000123400000007`. Stamp signatures retain the existing outer-address/batch/index/timestamp message. The stamp-key hash instead uses exactly `abi.encodePacked(anchor, batchId, uint64(index))`, with no timestamp or extra label.

### A.5 Density and utilization arithmetic

Reuse a compatible `Math.mulDiv` to multiply then divide without intermediate overflow. Do not copy its implementation or add an external verifier. Calculate both coefficients once per participant:

```solidity
uint256 private constant Q64 = uint256(1) << 64;
uint256 private constant COEFFICIENT_CAP = 32 * Q64;
uint256 private constant RATIO_CAP = 32 * 32 * 32;

function _coefficient(uint256 numerator, uint256 denominator)
    internal pure returns (uint256)
{
    if (denominator == 0) revert InvalidReserveProof();
    if (numerator <= denominator) return Q64;
    if (numerator / denominator >= RATIO_CAP) return COEFFICIENT_CAP;
    uint256 ratioQ64 = Math.mulDiv(numerator, Q64, denominator);
    uint256 radicand = ratioQ64 << 128;
    uint256 y = COEFFICIENT_CAP;
    while (true) {
        uint256 next = (2 * y + radicand / (y * y)) / 3;
        if (next >= y) return y;
        y = next;
    }
}

function _weight(
    uint256 stake, uint8 depth, uint8 height, uint64 count,
    uint256[2] memory capacity, uint32[2] memory index
) internal view returns (uint256 result) {
    if (stake == 0 || stake > type(uint128).max || height > depth || depth > 16 ||
        minimumReserveCount < 2 || count < minimumReserveCount)
        revert InvalidReserveProof();
    for (uint256 i; i < 2; ) {
        if (capacity[i] == 0 || (capacity[i] & (capacity[i] - 1)) != 0 ||
            uint256(index[i]) >= capacity[i]) revert InvalidReserveProof();
        unchecked { ++i; }
    }
    uint256 scale = capacity[0] > capacity[1] ? capacity[0] : capacity[1];
    uint256 a = (uint256(index[0]) + 1) * (scale / capacity[0]);
    uint256 b = (uint256(index[1]) + 1) * (scale / capacity[1]);
    uint256 utilization = a >= scale - b ? Q64 : _coefficient(scale, a + b);
    result = stake << (depth - height);
    result = result * _coefficient(count, minimumReserveCount) / Q64;
    result = result * utilization / Q64;
    if (result == 0) revert InvalidReserveProof();
}
```

Capacities may differ, but powers of two allow exact scaling to the larger one. The resulting average is `u = (a + b) / (2 * scale)`, so the utilization ratio becomes `1 / (2 * u) = scale / (a + b)`. This is why the helper receives `scale` and `a + b`, rather than an average of raw indexes or bonuses.

Each scaled term is at most `scale`. Check `a >= scale - b` before adding them: that detects the no-bonus case without overflowing. In the remaining case, `a + b < scale`, so addition is safe.

Q64 stores a value multiplied by `2^64`. Round the ratio down to Q64, then round down the cube root and each weight multiplication. `Math.mulDiv` avoids overflowing the intermediate numerator, and integer division detects the cap without multiplying a large denominator.

The cube-root input stays below `2^207`. Newton's iteration starts at the coefficient cap, above the required root, and decreases until integer rounding prevents another decrease. Final weight stays below `2^154`, and 256 weights below `2^162`, under A.1's bounds. Changing admission bounds requires checking these arithmetic bounds again.

### A.6 Proof and selection changes

Locate participation by round and original commit index, then authenticate its owner. The **SWIP-049 integration** supplies `_cancelIfInvalid()`: persist a detected cancellation and return true. The caller must then return successfully, avoiding later checks that could revert that cancellation.

```solidity
error InvalidParticipation();
event AuditOpened(uint64 indexed round, bytes32 auditSeed);
event SelectionOpened(uint64 indexed round, bytes32 selectionSeed);
event Proved(uint64 indexed round, address indexed owner, uint256 weight);

function prove(uint64 round, uint256 commitIndex, ReserveProof[2] calldata proofs)
    external whenNotPaused
{
    if (_cancelIfInvalid()) return;
    if (!currentPhaseProof() || round != currentRound() || round != currentCommitRound ||
        round != currentRevealRound || roundFinalized || !auditSeedSet ||
        commitIndex >= commitsLength) revert InvalidParticipation();
    Commit storage commitment = currentCommits[commitIndex];
    if (commitment.owner != msg.sender || !commitment.revealed ||
        commitment.revealIndex >= revealsLength) revert InvalidParticipation();
    Reveal storage entry = currentReveals[commitment.revealIndex];
    if (entry.proved || entry.owner != commitment.owner || entry.overlay != commitment.overlay)
        revert InvalidParticipation();
    (uint64[2] memory ranks, uint8[2] memory segments) =
        _challenge(round, commitment.owner, entry);
    uint256[2] memory capacities;
    uint32[2] memory indexes;
    for (uint256 i; i < 2; ) {
        (capacities[i], indexes[i]) = _verifyReserveProof(
            round, entry, ranks[i], segments[i], proofs[i]
        );
        unchecked { ++i; }
    }
    entry.stakeDensity = _weight(
        commitment.stake, entry.depth, commitment.height, entry.reserveCount,
        capacities, indexes
    );
    entry.proved = true;
    if (!selectionSeedSet) {
        selectionSeed = keccak256(abi.encode(
            auditSeed, round, block.prevrandao
        ));
        selectionSeedSet = true;
        emit SelectionOpened(round, selectionSeed);
    }
    emit Proved(round, entry.owner, entry.stakeDensity);
}

function _verifyReserveProof(
    uint64 round, Reveal storage entry, uint64 rank, uint8 segmentIndex,
    ReserveProof calldata proof
) internal view returns (uint256 capacity, uint32 index) {
    uint8 bucketDepth;
    (capacity, bucketDepth) = _verifyPostageForTargetRound(
        proof.chunkAddress, proof.postageProof.postageId, proof.postageProof.index,
        proof.postageProof.timeStamp, proof.postageProof.signature,
        _samplingStartBlock(round), requiredNormalisedBalance
    );
    if (bucketDepth < entry.depth ||
        !inProximity(proof.chunkAddress, currentRevealRoundAnchor, entry.depth))
        revert InvalidReserveProof();
    bytes32 transformed = _transformedChunk(proof, segmentIndex, currentRevealRoundAnchor);
    bytes32 key = keccak256(abi.encodePacked(
        currentRevealRoundAnchor, proof.postageProof.postageId, proof.postageProof.index
    ));
    _verifyTree(entry.reserveRoot, entry.reserveCount, rank, key, transformed, proof.path);
    index = getPostageIndex(proof.postageProof.index);
}
```

Failure of either witness reverts the submission, including any weight or newly initialized selection seed. No partial-proof state is stored. A guarded view can call `_challenge` to return the same assignments to Bee. When both stamps authorize the same chunk, both assigned segment proofs are still required.

Adapt the existing commit-order selection loop below. It returns an index into `currentReveals`, but uses the original **commit** index `i` for each random draw:

```solidity
function _selectTruth() internal view returns (bool found, uint256 selectedReveal) {
    if (!selectionSeedSet) return (false, 0);
    uint256 sum;
    for (uint256 i; i < commitsLength; ) {
        Commit storage commitment = currentCommits[i];
        if (commitment.revealed) {
            Reveal storage entry = currentReveals[commitment.revealIndex];
            if (entry.proved) {
                sum += entry.stakeDensity;
                if (_uniform(keccak256(abi.encode(selectionSeed, i)), sum) < entry.stakeDensity) {
                    selectedReveal = commitment.revealIndex;
                    found = true;
                }
            }
        }
        unchecked { ++i; }
    }
}
```

Call this only after proof closes. The `found` flag distinguishes no selection from a legitimate zero index; likewise, a zero depth or hash must not imply missing state. Do not renumber entries after skipping unproved participants or add claim-block randomness.

Integrate selection with the existing claim/finalization loops as follows:

- Check phase, round, cancellation and finalization status. With no proved participant, there is no payout.
- Collect proved participants matching both the selected sample hash and depth. Build recipient and weight arrays once in memory. Mark the round finalized before external state-changing calls, apply penalties once and call A.7 once. Payment failure must revert those state changes too, leaving claim retryable.
- Send the number of matching recipients to ordinary price feedback. SWIP-049 integration must prevent partially applied updates and allow legitimate skipped updates without undoing valid settlement.

A commitment is unfinished when it was not revealed **or** its reveal was not proved. Check for a reveal before accessing `revealIndex`. Keep disagreement separate, using the selected depth or configured no-truth depth rather than automatically applying the maximum depth. Its probability test is:

```text
uniform(keccak256(abi.encode(selectionSeed, "disagreement", commitIndex)), 100)
    < penaltyRandomFactor
```

The middle argument is a Solidity string, not a fixed `bytes32` label; clients reproducing the draw must encode it accordingly. Zero category multipliers disable their freezes. Finalization must prevent duplicate penalties. The existing Staking setter overwrites the stored freeze-end block, so call it only when the new end would be later:

```solidity
if (duration != 0 && block.number + duration > Stakes.lastUpdatedBlockNumberOfAddress(owner)) {
    Stakes.freezeDeposit(owner, duration);
}
```

This preserves the later freeze end without adding registry state.

After claim expires, cleanup uses the completed proofs but does not pay late. Proved participants are not unfinished merely because claim was missed. Keep the last paid truth separate from the marker that says cleanup finished.

Before array reuse, cleanup must succeed even when its caller cannot enter the new round. Returning successfully after cleanup, without accepting a new commitment, is sufficient. Empty rounds create no obligations. Cancellation exempts affected participants without requiring another transaction from each of them. Retain the existing administration and pause entry points.

### A.7 Minimal direct payment in `PostageStamp.sol`

Leave price/history/expiry implementation to SWIP-049. Add this proportional `withdraw` overload and its signature to `IPostageStamp`, reusing the existing role, transfer checks, event and compatible `Math.mulDiv` import:

```solidity
error InvalidShares();

function withdraw(address[] calldata beneficiaries, uint256[] calldata weights)
    external
{
    if (!hasRole(REDISTRIBUTOR_ROLE, msg.sender)) revert OnlyRedistributor();
    uint256 length = beneficiaries.length;
    if (length == 0 || weights.length != length) revert InvalidShares();
    uint256 sum;
    for (uint256 i; i < length; ) {
        if (beneficiaries[i] == address(0) || weights[i] == 0) revert InvalidShares();
        sum += weights[i];
        unchecked { ++i; }
    }
    uint256 amount = totalPot(); // Existing expiry/accounting path; called ONCE.
    pot -= amount;
    uint256 distributed;
    for (uint256 i; i < length; ) {
        uint256 share = Math.mulDiv(amount, weights[i], sum);
        distributed += share;
        if (share != 0 && !ERC20(bzzToken).transfer(beneficiaries[i], share))
            revert TransferFailed();
        emit PotWithdrawn(beneficiaries[i], share);
        unchecked { ++i; }
    }
    pot += amount - distributed; // Retain rounding dust in the common pot.
}
```

Redistribution supplies the bounded set of matching recipients. Read the pot once and divide that amount; calling the old whole-pot withdrawal for each recipient would empty it on the first call. Accounting is debited before transfers, and any transfer failure reverts the entire operation. Rounding remainders stay in the common pot, without stored recipient credits or a later withdrawal transaction.

If `totalPot()` is capped by the token balance, the overload also retains the unpaid accounting shortfall. Unlike rounding dust, this may be substantial. Confirm that difference from the old clear-to-zero withdrawal when integrating. During authority handover, the old overload must not remain a second way to pay the same round.

The excerpt assumes the existing BZZ token behavior. Changing the asset or adding callbacks requires a new reentrancy review. `totalPot()` still performs expiry work: reuse avoids duplicating that code but does not bound its gas cost. Measure worst-case work and use the existing maintenance path.

### A.8 Integration checks

Cache SWIP-049's `redistributionMinimumNormalisedBalance(samplingStart)` once for each valid scope. Do not copy its history journal or price setter here. Historical metadata comes from before the boundary, but accumulated rent is calculated up to the boundary itself. Using the previous block's outpayment plus only 456 price-blocks misses one block of rent.

Cancellation must cover affected overlapping scopes, persist even without a new accepted commitment, and suppress their deferred penalties. Activate offset-19 depth-history retention before the first clean scope; changing the schedule cannot recover discarded historical records.

Test Bee/contract encodings, both CAC/SOC witnesses, distinct rank pairs, malformed paths/counts, participant-specific challenges, failure of either witness, first-complete-proof initialization, reused slots, cancellation, mixed capacities and payment. Regenerate ABI fixtures. Compile against the actual host contracts, test dependency interactions, and measure deployed bytecode size and gas before release; model tests alone do not establish EVM behavior.
