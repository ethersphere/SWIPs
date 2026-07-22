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

Sybil stakers can inflate `Redistribution` commit count so honest `claim()` becomes too expensive or fails proofs, blocking round payout without penalty. This SWIP lists those attacks, documents current contract bugs, and proposes bounded admission plus staged claim finalization.

## Abstract

`Redistribution` runs commit → reveal → claim to pay storers and update the price oracle ([SWIP-21](./swip-21.md)). `currentCommits` is unbounded; claim work scales O(N). On Gnosis (~17M block gas), ~100 sybils can exceed wallet caps and ~660 can approach the block limit.

Penalties computed in `winnerSelection()` roll back when proof verification fails; failed pot withdrawal still consumes the round. Depth floors raise cost but do not cap N.

**Proposed fix:** (1) stake-weighted bounded admission, (2) participation finalization that persists non-reveal penalties before proofs, (3) proof-gated disagreement penalties, oracle update, and payout. Fabricated-hash coalitions still need reveal-time validity or a timeout/fallback (out of scope for the core package).

## Motivation

`claim()` liveness is a protocol requirement: stalled rounds stop rewards and price discovery. No real Bee storage is required to commit or reveal; chunk proofs are checked only at claim.

Production deploys on Gnosis Chain (chainId 100), not Ethereum L1.

---

## Specification

### 1. Background

#### Attacker model

- **Sybil farm:** many staked addresses, one commit per overlay per round (`AlreadyCommitted`), one reveal per commit (`AlreadyRevealed`).
- **Entry cost per sybil:** `MIN_STAKE * 2^height` (10 BZZ at height 0), two-round stake wait, commit/reveal gas. `manageStake()` resets the wait.
- **Commit vs reveal:** `commit()` has no proximity check; `reveal()` requires proximity. Cheapest path: `depth == height` (proximity always passes, lowest `stakeDensity`).
- **`claim()`:** permissionless — any caller with valid proofs pays gas; pot goes to `winner.owner`.

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

Commit-phase attacker cost is O(N²) (uniqueness scans) — partial deterrent, not protection for the single `claim()` tx.

~100 sybils ≈ 1,000 BZZ locked at height 0; ~660 ≈ 6,600 BZZ. If every claim is blocked, no freeze applies (rollback bug). Figures are engineering estimates; benchmark on a Gnosis fork before setting `MAX_COMMITS`.

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
| **B1** | Penalties inside same tx as proofs | Proof failure reverts all `freezeDeposit()` and `currentClaimRound` — blocking nodes stay unpenalized |
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

### 4. Proposed mitigations

Three layers — admission bounds work; staging fixes **B1** and **B2**; eligibility raises sybil cost.

```
bounded online admission (MAX_COMMITS)
        +
finalizeParticipation — persist non-reveal penalties
        +
verifyWinner → settleRound — proofs before subjective penalties, oracle, payout
```

#### 4.1 Staged claim finalization

Replace atomic `claim()` with ordered steps (same claim window; payout rights expire at rollover):

| Step | Function | Persists on revert | Purpose |
|------|----------|-------------------|---------|
| 1 | `finalizeParticipation(round)` | **Yes** — non-reveal freezes | Store tentative truth/winner; cap loop at K commits |
| 2 | `verifyWinner(round, proofs…)` | No | Validate chunk/stamp/SOC proofs; mark `truthValidated` |
| 3 | `settleRound(round)` | Retryable | Disagreement penalties, oracle, pot withdraw — only after **B2**-safe success |

**Rules:**

- Step 1 must **not** freeze disagreeing revealers or adjust the oracle (tentative truth may be fabricated).
- Invalid `verifyWinner` calldata must not slash the winner (anyone can submit bad proofs).
- `PostageStamp.withdraw()` pulls the global pot — use current-round-only payout rights or round escrow (PostageStamp change).
- Snapshot reveal anchor, proof seed, truth, winner in `RoundState`; no bulk-delete unbounded arrays — use fixed-cap / generation-tagged storage.

**Open design:** step-1 caller incentive on empty rounds; optional `verifyAndSettle(proofs)` wrapper for steps 2–3.

#### 4.2 Bounded admission (`MAX_COMMITS`)

- Hard cap on selected commits bounds all O(N) loops and freeze calls.
- **Not FCFS** — sybils would race to fill slots. Use stake-weighted online selection:

```text
weight = objectivelyLockedEffectiveStake(owner)
entropy = H(domain, round, fixedRoundSeed, overlay)
priority = auditedWeightedPriority(entropy, weight)
```

Keep best K by priority; O(log K) eviction per commit. Emit admission/eviction events. Set K only after fork benchmarks at N = MAX with margin.

See [ADMISSION_COMPARISON.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/ADMISSION_COMPARISON.md) for stake-weighted vs proximity-ranked admission.

#### 4.3 Eligibility rules (supporting — do not cap N alone)

1. `commit(obfuscatedHash, round, depth)` — store `declaredDepth`; reveal must match.
2. Commit requires proximity, `depth > height`, depth floor — see [MINIMUM_DEPTH_OPTIONS.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/MINIMUM_DEPTH_OPTIONS.md).
3. Validate `potentialStake >= MIN_STAKE * 2^newHeight` on every height change.
4. Lock stake/overlay/height for selected participants until obligation ends.
5. **Separate decision (attack 2):** reveal-time validity sample or timeout/fallback for fabricated-hash coalitions.

#### 4.4 Attack → mitigation map

| Attack | Primary fix | Also helps |
|--------|-------------|------------|
| Gas grief (1, 3) | `MAX_COMMITS` + staged loops | O(N²) commit cost (existing) |
| Truth poison (2) | Staging: non-reveal freezes persist even when proofs fail | Eligibility rules |
| Penalty-free blocking (2) | Split proof validation from `finalizeParticipation` | — |
| Fabricated-hash coalition (2) | **Not solved by core package** | Rule 4.3.5 validity / fallback |
| Rollover DoS | Fixed-cap state, no bulk delete | `MAX_COMMITS` |

---

## Rationale

**Why bounded admission, not only economic filters.** Depth floors, proximity, and minimum stake raise cost but cannot cap per-round work. `MAX_COMMITS` with stake-weighted selection bounds gas and reduces FCFS slot racing.

**Why staged finalization.** Objective facts (did not reveal) can be finalized before storage proofs. Subjective facts (disagreement, oracle, payout) require validated truth. Fixes **B1** without letting a false tentative truth penalize honest revealers.

**Why stake-weighted admission.** Aligns with existing truth-selection economics; proximity ranking is analyzed separately in ADMISSION_COMPARISON.md.

**Why current-round-only payout rights.** Global `withdraw()` must not let a stale winner drain a pot enlarged by later rounds. Expiring unpaid rights at rollover is lighter than PostageStamp escrow.

**What the core package does not solve.** A coalition that all reveals the same fabricated hash and wins truth still needs cryptographic reveal validity or an audited timeout/fallback — a separate liveness decision.

---

## Backwards Compatibility

Breaking changes:

- `commit()` gains `_depth`; admission may reject previously valid commits.
- Atomic `claim()` → up to three claim-phase actions with new state and deadlines.
- Unbounded arrays → fixed-capacity, generation-tagged structures.

Bee clients and indexers must track admission/eviction, call staged finalization, and handle expired payout rights. Deployed contracts require upgrade or redeployment.

---

## Test Cases

Before setting `MAX_COMMITS`:

1. Sybil scaling gas on Gnosis fork: staged steps at N ∈ {1, 10, 100, 500, MAX}.
2. `finalizeParticipation` + failing `verifyWinner` leaves non-reveal freezes in place.
3. Empty round: `finalizeParticipation` closes without payout.
4. `PostageStamp.withdraw()` failure does not consume payout rights.
5. Stake-weighted admission fairness over many rounds.
6. Worst-case K participants do not DoS next-round commit via storage cleanup.

Illustrative gas thresholds are not acceptance criteria until measured.

---

## Implementation

Reference: [storage-incentives](https://github.com/ethersphere/storage-incentives) (`fix/minimal_depth_resolve` branch)

- [`Redistribution.sol`](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/src/Redistribution.sol)
- [`Staking.sol`](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/src/Staking.sol)
- [SPAM_GRIEFING.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/SPAM_GRIEFING.md)
- [MINIMUM_DEPTH_OPTIONS.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/MINIMUM_DEPTH_OPTIONS.md)

**Status:** proposed architecture; not in production.

## Roadmap

1. Gnosis fork benchmarks → `MAX_COMMITS`
2. Exact weighted admission algorithm and `RoundState` layout
3. Staged finalization + Bee client update
4. Empty-round step-1 incentives
5. Fabricated-hash validity or timeout/fallback
6. Depth floor governance ([MINIMUM_DEPTH_OPTIONS.md](https://github.com/ethersphere/storage-incentives/blob/fix/minimal_depth_resolve/docs/MINIMUM_DEPTH_OPTIONS.md))

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
