---
SWIP: 51
title: Redistribution spam and griefing mitigation
author: Mark Bliss (@n00b21337)
discussions-to: https://discord.gg/Q6BvSkCv (Swarm Discord '#swips')
status: Draft
type: Standards Track
category: Core
created: 2026-07-16
requires: 21
---

# Redistribution spam and griefing mitigation

## Simple Summary

Sybil stakers can inflate `Redistribution` commit count so honest `claim()` becomes too expensive or fails proofs, blocking round payout without penalty. This SWIP documents the attacks and bugs, specifies **shared** mitigations (bounded admission and related eligibility), and defines **two alternative claim-path options**: decouple `claim()` now, or keep a single `claim()` after [SWIP-49](https://github.com/lat-murmeldjur/SWIPs/blob/6ef788105eaefd7055135c89f2ba14beb59722b2/SWIPs/swip-49.md) and [SWIP-50](https://github.com/lat-murmeldjur/SWIPs/blob/617972b9f4bf009db91e456d0b5fde819057665b/SWIPs/swip-050.md) land.

## Abstract

`Redistribution` runs commit → reveal → claim to pay storers and update the price oracle ([SWIP-21](./swip-21.md)). `currentCommits` is unbounded; claim work scales O(N). On Gnosis (~17M block gas), ~100 sybils can exceed wallet caps and ~660 can approach the block limit.

Penalties in `winnerSelection()` roll back when later proof verification fails (**B1**). Failed pot withdrawal can still consume the round (**B2**). Depth floors raise cost but do not cap N (**B3**).

**This SWIP splits mitigations into:**

1. **Shared package** — implement regardless of claim shape: stake-weighted `MAX_COMMITS`, fixed-cap state, supporting eligibility, and a safe payout/retry rule for **B2**.
2. **Claim-path choice (pick one):**
   - **Option A — Decouple `claim()`** (this SWIP): staged `finalizeParticipation` → `verifyWinner` → `settleRound` so objective non-reveal penalties persist before proofs.
   - **Option B — Keep single `claim()`** after **SWIP-49 + SWIP-50**: proof-before-selection and unfinished-commit carry-over largely remove the need for staging for truth-poison / **B1**.

Fabricated all-revealing coalitions may still need further validity or timeout/fallback beyond either option.

## Motivation

`claim()` liveness is a protocol requirement: stalled rounds stop rewards and price discovery. No real Bee storage is required to commit or reveal under the current contract; chunk proofs are checked only at claim.

Production deploys on Gnosis Chain (chainId 100), not Ethereum L1.

Shared work (admission, eligibility, payout safety) should not wait on the claim-path decision. Claim decoupling and STS-1 are **alternatives** for the same failure modes around penalty rollback and fabricated truth — not a stack of both by default.

---

## Specification

### 1. Background

#### Attacker model

- **Sybil farm:** many staked addresses, one commit per overlay per round (`AlreadyCommitted`), one reveal per commit (`AlreadyRevealed`).
- **Entry cost per sybil:** `MIN_STAKE * 2^height` (10 BZZ at height 0), two-round stake wait, commit/reveal gas. `manageStake()` resets the wait.
- **Commit vs reveal:** `commit()` has no proximity check; `reveal()` requires proximity. Cheapest path: `depth == height` (proximity always passes, lowest `stakeDensity`).
- **`claim()`:** permissionless — any caller with valid proofs pays gas; pot goes to `winner.owner`. Failed `claim()` does not set `AlreadyClaimed`; anyone may retry until one succeeds. Junk proofs only burn caller gas and are not a standalone DoS.

#### Where N hurts

| Phase  | Function            | Cost        |
|--------|---------------------|-------------|
| Commit | overlay uniqueness  | O(n) / tx   |
| Reveal | `findCommit()`      | O(n) / tx   |
| Claim  | `getCurrentTruth()` | O(n)        |
| Claim  | `winnerSelection()` | O(n) + freeze calls |

Commit-only sybils are cheap in truth selection but expensive in `winnerSelection()` (`freezeDeposit()` per non-revealer). Bulk `delete currentCommits` on rollover can also grief the next round if N is unbounded.

#### Gas and economics (illustrative)

```
G_claim(N) ≈ 450k + (N − 1) × 25k
```

| Limit   | Context              | ~Sybils to exceed |
|---------|----------------------|-------------------|
| ~3M     | Wallet / RPC cap     | ~100              |
| ~17M    | Gnosis block limit   | ~660              |

Examples: N = 100 → ~2.9M; N = 500 → ~12.9M; N = 660 → ~17M (block cliff).

Commit-phase attacker cost is O(N²) (uniqueness scans) — partial deterrent, not protection for the single `claim()` tx. ~100 sybils ≈ 1,000 BZZ locked at height 0; ~660 ≈ 6,600 BZZ. If every claim is blocked, no freeze applies (rollback bug). Figures are engineering estimates; benchmark on a Gnosis fork before setting `MAX_COMMITS`.

---

### 2. Attacks

All scenarios assume **honest nodes are playing** and at least one reveal exists in the round.

| # | Name | Attacker action | Effect on honest nodes | Blocks payout when |
|---|------|-----------------|------------------------|--------------------|
| **1** | Claim gas grief | N commits + ≥1 reveal (sybil or honest) | `winnerSelection()` O(N); claim gas grows linearly | Gas exceeds tx/block limit; every retry repeats full work |
| **2** | Truth poisoning | Sybil reveals fabricated `(hash, depth)`; may win stake-weighted truth lottery | Honest proofs fail on selected hash | Proof revert rolls back entire `claim()` including penalties |
| **3** | Commit-only spam | Same as **1** with one revealer, N−1 commit-only | Same loop bloat | Same as **1** — not a separate vector |

**Attack 1 detail:** Failed or OOG `claim()` reverts all `freezeDeposit()` calls. Attacker need not pass proofs — one sybil reveal is enough to enter the claim path.

**Attack 2 detail:** Truth is a stake-density lottery keyed on commit index, not correctness. Sole sybil reveal wins truth deterministically; with multiple reveals, outcome is probabilistic. `reveal()` does not verify storage.

**Out of scope as sybil grief:** rounds where nobody reveals (empty network). No honest participant is harmed; pot accrues until someone plays.

---

### 3. Current contract bugs

| ID | Bug | Symptom |
|----|-----|---------|
| **B1** | Penalties inside same tx as post-selection proofs | Proof / OOG failure reverts all `freezeDeposit()` and `currentClaimRound` — blocking nodes stay unpenalized |
| **B2** | Payout failure treated as success | `WithdrawFailed` emitted but round marked claimed; winner cannot retry |
| **B3** | Unbounded `currentCommits` | Claim and rollover work scale with attacker-chosen N |

**Economic limitation (not a bug):** `freezeDeposit()` is a time-lock, not a slash; capital can return after freeze + two rounds.

**Penalty table (only if full `claim()` succeeds today):**

| Participant | Condition | Penalty |
|-------------|-----------|---------|
| Commit, no reveal | `!revealed` | Always frozen |
| Reveal, wrong truth | hash/depth ≠ truth | Frozen (`penaltyRandomFactor`) |
| Reveal, matches truth | exact match | None |
| Winner | bad proofs | Whole tx reverts; no one penalized |

---

### 4. Mitigation architecture

Mitigations fall into a **shared package** (always) and a **claim-path choice** (exactly one of Option A or Option B).

```text
                    ┌─────────────────────────────────────┐
                    │  SHARED (§4.1)                        │
                    │  MAX_COMMITS + fixed-cap state        │
                    │  eligibility + B2 payout safety       │
                    └──────────────┬──────────────────────┘
                                   │
              ┌────────────────────┴────────────────────┐
              ▼                                         ▼
   Option A (§4.2)                             Option B (§4.3)
   Decouple claim now                          Keep single claim
   (this SWIP)                                 after SWIP-49 + SWIP-50
```

| Concern | Shared | Option A (decouple) | Option B (49+50, single claim) |
|---------|--------|---------------------|--------------------------------|
| Gas grief / **B3** / rollover | **Required** | — | — |
| Truth poison / **B1** | — | Staged penalties before proofs | Proof-before-selection + unfinished-commit carry-over |
| **B2** payout retry | **Required** (either path) | Via `settleRound` | Via claim ordering / pending payout design in 49–50 |
| Do both A and B? | — | **No** — pick one claim path | **No** — pick one claim path |

---

### 4.1 Shared package (implement either way)

These items do **not** depend on decoupling `claim()`. They can ship before the claim-path decision is final.

#### 4.1.1 Bounded admission (`MAX_COMMITS`)

- Hard cap on selected commits bounds all O(N) loops and freeze calls.
- **Not FCFS** — sybils would race to fill slots. Use stake-weighted online selection:

```text
weight = objectivelyLockedEffectiveStake(owner)
entropy = H(domain, round, fixedRoundSeed, overlay)
priority = auditedWeightedPriority(entropy, weight)
```

Keep best K by priority; O(log K) eviction per commit. Emit admission/eviction events. Set K only after fork benchmarks at N = MAX with margin.

See [ADMISSION_COMPARISON.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/ADMISSION_COMPARISON.md).

Under Option B, also bound any **carry-over** unfinished-commit list (SWIP-50 `pendingCompletion`) so a later successful claim cannot OOG on accumulated unfinished sybils.

#### 4.1.2 Fixed-capacity round state

No bulk-delete of attacker-sized dynamic arrays. Use fixed-cap / generation-tagged storage (or equivalent cursor-bounded cleanup) so rollover cannot become the next-round DoS.

#### 4.1.3 Eligibility rules (supporting — do not cap N alone)

1. `commit(obfuscatedHash, round, depth)` — store `declaredDepth`; reveal must match.
2. Commit requires proximity, `depth > height`, depth floor — see [MINIMUM_DEPTH_OPTIONS.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/MINIMUM_DEPTH_OPTIONS.md).
3. Validate `potentialStake >= MIN_STAKE * 2^newHeight` on every height change.
4. Lock stake/overlay/height for selected participants until obligation ends.

#### 4.1.4 Payout safety (**B2**)

Settlement must not consume the round’s payout right on a failed pot transfer. Either:

- revert settlement / keep an explicit retryable payout state until success or deadline; or
- credit round-scoped pending balances and expose a separate withdraw (as sketched in SWIP-50).

Because `PostageStamp.withdraw()` pulls the **global** pot, unpaid rights must be **current-round-only** or use round escrow. Storing a stale finalized winner while calling global `withdraw()` later is unsafe.

---

### 4.2 Option A — Decouple `claim()` (this SWIP)

**When to choose:** ship a fix for **B1** / truth-poison **without** waiting for SWIP-49/50; keep today’s reveal → select → prove ordering.

Replace atomic `claim()` with ordered steps inside the claim window (payout rights expire at rollover):

| Step | Function | Persists on revert | Purpose |
|------|----------|-------------------|---------|
| 1 | `finalizeParticipation(round)` | **Yes** — non-reveal freezes | Store tentative truth/winner; loop capped at K |
| 2 | `verifyWinner(round, proofs…)` | No | Validate chunk/stamp/SOC proofs; mark `truthValidated` |
| 3 | `settleRound(round)` | Retryable | Disagreement penalties, oracle, pot — only after validated truth |

**Rules:**

- Step 1 must **not** freeze disagreeing revealers or adjust the oracle (tentative truth may be fabricated).
- Invalid `verifyWinner` calldata must not slash the winner (anyone can submit junk proofs).
- Snapshot reveal anchor, proof seed, truth, winner in `RoundState`.
- Optional: `verifyAndSettle(proofs)` convenience wrapper for steps 2–3.

**Open design:** step-1 caller incentive on empty rounds.

**Does not require:** SWIP-49 or SWIP-50.

**If Option A ships first:** Option B’s single-claim design should not reintroduce freeze-before-proof for the legacy selection order. Prefer one claim path in production.

---

### 4.3 Option B — Keep single `claim()` after SWIP-49 + SWIP-50

**When to choose:** accept waiting for the STS redesign; avoid multi-step claim UX/client changes for **B1**/truth-poison.

| Draft | Role for this SWIP |
|-------|--------------------|
| [SWIP-49](https://github.com/lat-murmeldjur/SWIPs/blob/6ef788105eaefd7055135c89f2ba14beb59722b2/SWIPs/swip-49.md) | Fixed postage scope for a target round; claim verifies postage against sampling-start state; price update after proofs |
| [SWIP-50](https://github.com/lat-murmeldjur/SWIPs/blob/617972b9f4bf009db91e456d0b5fde819057665b/SWIPs/swip-050.md) | STS-1: stamp + chunk-binding proofs **before** truth-selection weight; unfinished stage-one commits carried to the next successful claim |

**Why this can replace decoupling for B1 / attack 2:**

- Fabricated Schelling values get **no selection weight** until stamp witnesses and STS binding proofs pass → classic poison → claim-proof-fail loop is largely removed.
- Unfinished commits remain pending and can be frozen by a **later** successful claim if this round never claims → non-reveal pressure does not depend on same-round claim success alone.

**Still required from §4.1:** `MAX_COMMITS` (and a bound on unfinished carry-over), fixed-cap state, eligibility as applicable, **B2**-safe payout.

**Does not by itself solve:** unbounded N, rollover bulk-delete, or one-copy-many-overlays (SWIP-50 non-goal).

**If Option B is chosen:** do **not** also implement Option A’s three-step claim as the default path. Shared §4.1 items still apply.

---

### 4.4 Attack → mitigation map

| Attack / bug | Shared (§4.1) | Option A | Option B |
|--------------|---------------|----------|----------|
| Gas grief (1, 3) / **B3** | `MAX_COMMITS` + fixed-cap state | Same | Same (+ bound `pendingCompletion`) |
| Truth poison (2) / **B1** | — | Staging: non-reveal freezes persist when proofs fail | Proof-before-selection + unfinished carry-over |
| Penalty-free blocking while claim fails | — | Split finalize vs prove | Selection only over proof-validated entries |
| **B2** | Payout retry / pending withdraw | Via `settleRound` | Via 49/50 claim + pending payout design |
| Rollover DoS | Fixed-cap state | Same | Same |
| Fabricated-hash coalition (remaining) | Out of core package | May still need validity / timeout | STS raises bar; physical-replica issues remain out of scope |

---

## Rationale

**Shared admission first.** Depth floors and stake raise cost but cannot cap per-round work. `MAX_COMMITS` is required under **both** claim paths.

**Two claim paths, one choice.** Decoupling (Option A) fixes **B1** under the *current* select-then-prove order. SWIP-49/50 (Option B) change the order to prove-then-select, which removes most of the reason to stage `claim()` for poison/B1. Implementing both as concurrent defaults would duplicate complexity without clear gain.

**Why not Option B alone without §4.1.** STS does not bound N; gas grief and rollover DoS remain.

**Why not Option A alone forever if 49/50 ship.** Once proof-before-selection is live, staged claim is largely redundant for attack 2; keep one claim model to avoid dual client paths.

**Stake-weighted admission.** Aligns with existing truth-selection economics; proximity ranking is analyzed in ADMISSION_COMPARISON.md.

**What neither option fully solves.** An all-revealing coalition with sufficient real-looking evidence may still need a separate liveness mechanism (validity sample or timeout/fallback).

---

## Decision and roadmap

1. Implement **§4.1 shared package** (admission, fixed-cap state, eligibility, **B2** payout safety).
2. Choose **exactly one**:
   - **Option A** — specify and implement staged claim (§4.2); or
   - **Option B** — wait for SWIP-49 + SWIP-50, keep single `claim()`, ensure unfinished-list gas is capped (§4.3).
3. Re-evaluate fabricated-hash / physical-storage residual risks after the chosen path ships.
4. Fork-benchmark `MAX_COMMITS` (and Option B carry-over bound) on Gnosis before locking parameters.

---

## Backwards Compatibility

**Shared (§4.1):**

- `commit()` may gain `_depth` and admission may reject previously valid commits.
- Round state moves from unbounded arrays to fixed-capacity / generation-tagged structures.

**Option A only:**

- Atomic `claim()` → up to three claim-phase actions with new state and deadlines.
- Bee clients must call staged finalization and handle expired payout rights.

**Option B only:**

- Breaking changes are those of SWIP-49 and SWIP-50 (round phases, proof submission, postage reads, payout distribution).
- Bee clients follow the STS sequence; no SWIP-51 three-step claim API.

Deployed contracts require upgrade or redeployment in either case.

---

## Test Cases

**Shared:**

1. Sybil scaling gas on Gnosis fork at N ∈ {1, 10, 100, 500, MAX_COMMITS}.
2. Failed pot transfer does not consume payout rights.
3. Worst-case K participants do not DoS next-round commit via storage cleanup.
4. Stake-weighted admission fairness over many rounds.

**Option A:**

5. `finalizeParticipation` + failing `verifyWinner` leaves non-reveal freezes in place.
6. Empty round: `finalizeParticipation` closes without payout.

**Option B:**

7. Entry without STS proof has zero truth-selection weight.
8. Unfinished stage-one commits freeze on a later successful claim; carry-over size stays within gas budget at MAX.

Illustrative gas thresholds are not acceptance criteria until measured.

---

## Implementation

- Current contracts: [storage-incentives](https://github.com/ethersphere/storage-incentives) (`Redistribution.sol`, `Staking.sol`)
- Threat model notes: [SPAM_GRIEFING.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/SPAM_GRIEFING.md) (align with this SWIP when updating)
- Draft alternatives: [SWIP-49](https://github.com/lat-murmeldjur/SWIPs/blob/6ef788105eaefd7055135c89f2ba14beb59722b2/SWIPs/swip-49.md), [SWIP-50](https://github.com/lat-murmeldjur/SWIPs/blob/617972b9f4bf009db91e456d0b5fde819057665b/SWIPs/swip-050.md)

**Status:** draft architecture. Shared package and claim-path choice are not yet in production.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
