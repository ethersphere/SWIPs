---
name: adversarial-swip-review
description: Use when drafting, revising, or reviewing a Swarm Improvement Proposal (SWIP) - before opening the PR, before requesting Last Call, or when a SWIP feels "done" and you want the objections found now rather than in review. Also use when a proposal touches staking, the redistribution game, postage stamps, chunk or manifest formats, neighbourhoods, contract migration, or the bzz protocol.
---

# Adversarial SWIP Review

## Overview

Review a SWIP the way a hostile-but-competent implementer would: someone who wants to
break the mechanism, exploit its incentives, or ship a conforming client that is
incompatible with yours. The goal is a ranked list of concrete attacks and gaps, each
with a path an author can walk, not a list of impressions.

**Core principle: a finding without a concrete failure path is not a finding.** "The
incentive analysis could be stronger" is noise. "A node can join a neighbourhood one
block before the reveal phase, claim the reward with no storage cost, and leave — §4
never binds stake age to eligibility" is a finding.

**This review is run by subagents, one per attack lane, in parallel.** One agent
sweeping eight lanes gets shallower with each lane and stops early once it has found
something serious. Eight agents each own one lane, go to the bottom of it, and cannot
see each other's findings — so nobody stops early and nobody is anchored. A ninth agent
then does the judgement work of ranking and deduplicating across all of them.

## Invoking It

The user says **"review this swip"** (or `/adversarial-swip-review`). They do not name a
file, and you should not ask them to.

A SWIP is always written on its own branch, and the review always runs from that branch.
So resolve the target by diffing the working branch against trunk:

```
git diff --name-only master... -- 'SWIPs/*.md'
```

That catches the SWIP whether it is newly added or being revised. Then:

- **One file** — that is the SWIP. Say which one you are reviewing, and get on with it.
- **Several** — ask which; a branch carrying two SWIPs is unusual enough to be worth a
  question.
- **None** — the branch has no SWIP changes against trunk. Say so rather than guessing:
  the user is probably on `master`, or on the wrong branch, and a review of an unchanged
  file is not what they asked for.

Do not review the whole `SWIPs/` directory, and do not fall back to "the most recently
modified file" — the branch diff is the source of truth for what is being proposed.

## When to Use

- Before opening the PR for a new SWIP, or before setting `ready to merge`
- After a substantive revision to a Draft, to check that the fix did not open a new hole
- When reviewing someone else's SWIP and you want more than editorial comments
- When the SWIP changes economics, consensus, on-chain contracts, or wire/data formats

**Not for:** spelling, grammar, markdown, broken links, header fields, or the copyright
waiver. Those are the editors' job and a separate pass — leave them out entirely.

The line: a **missing section is a finding when its absence hides a real gap** — no
Backwards Compatibility section on a SWIP that changes a contract ABI, no Test Cases on
one that changes a data format, no Rationale on one with obvious unaddressed
alternatives. Report the gap, not the missing heading. A missing section that hides
nothing is editorial; say nothing about it.

## Process

You are the orchestrator. You do steps 0, 1, 2 and 6; subagents do 3, 4 and 5.

### 0. Establish the baseline — what does this change compare against?

**A SWIP is a diff against a running system. Review it against that system, not against
your memory of it.** Findings built on recalled protocol behaviour are the main way this
review produces confident nonsense: the attack path is airtight and the premise is two
years stale. Do this before anything else.

Clone the ground truth fresh:

```
sh <skill dir>/scripts/fetch-sources.sh <scratch dir>
```

That shallow-clones `ethersphere/bee` (the Go client) and
`ethersphere/storage-incentives` (the Solidity contracts) at the current tip of trunk
and prints the path, branch, sha and date of each. It takes a few seconds.

**Do not review against a checkout you found on the machine.** A developer box commonly
holds several clones of the same repo at different ages, in directories not named after
it, some dirty or mid-rebase — picking the wrong one silently is the same failure as
using memory, minus the warning. Clone it yourself so you know exactly what you read,
and record the sha in the report so the review is reproducible.

Record the shas the script prints. If cloning fails (no network), say so to the user
before running the review rather than quietly falling back to a local copy.

Then answer three questions from that source and write the answers down:

1. **Is it already implemented?** Grep the contracts and the client for the SWIP's new
   names — a field, a function, a parameter. A SWIP can be Draft on paper and merged in
   code. If it is implemented, the review changes character: you are reviewing a spec
   against its own implementation, and every divergence between them is a finding in
   its own right.
2. **What is the mechanism it modifies, as currently written?** Read the actual function.
   Quote it with a `file:line`. This is the baseline every lane reasons from.
3. **Which of the SWIP's claims about today are false?** An author who misdescribes the
   status quo has usually designed against the misdescription.

Write a **baseline brief**: for each mechanism the SWIP touches, the current behaviour
with a `file:line` citation. Keep it short and factual. It goes into every lane prompt
alongside the claim set. Where you could not establish something, say
`UNVERIFIED: <what>` — never leave a gap for an agent to fill from memory.

If no ground truth is reachable at all, say so to the user before running the review and
mark the whole report as unverified against implementation. A review that cannot see the
baseline is still worth running for internal contradictions and spec ambiguity — it is
not worth running for "an attacker can do X", because you cannot tell whether the
current code already stops X.

### 1. Read the SWIP and extract the claim set

Read the whole SWIP yourself. You are about to hand it to eight agents and you cannot
brief them on a document you have not read. Write down:

- **What it changes** — the delta against today's Swarm, not the whole system
- **Load-bearing claims** — every sentence the design would collapse without
  ("honest nodes are the majority", "storers cannot predict the anchor",
  "the migration is atomic")
- **Actors** — who can act on this: node operators, stakers, uploaders, downloaders,
  contract owners, the deployer, an outside observer
- **What each actor gains by cheating** — in BZZ, in bandwidth, in information

This claim set goes verbatim into every lane agent's prompt. It is the only shared
context they have, so it must stand on its own.

### 2. Decide which lanes to run

`references/swarm-attack-surface.md` defines eight lanes. Run **every lane that could
apply** — a lane agent that finds nothing costs one agent and buys a cleared line in
the report. Drop a lane only when it is unarguable (Lane 2, on-chain, on a SWIP that
touches no contract). Record why, and report it as `not applicable` at the end.

### 3. Dispatch one agent per lane, in parallel, on the strongest model

Send **all lane agents in a single message** so they run concurrently, each with
`model: "opus"` — this review is the kind of adversarial reasoning worth the strongest
model available; do not let lane agents run on a cheaper default. Give each agent the
prompt below, filled in. Do not vary it between lanes beyond the lane number and name.

Pick a scratch directory first (your scratchpad, if you have one) and give every agent a
path in it. **Each lane agent writes its own report to that file and returns only its
verdict line.** Eight full reports are tens of thousands of tokens; routing them through
you costs that twice and buys nothing, since the synthesis agent reads the files.

```
You are reviewing a Swarm Improvement Proposal adversarially. You own exactly one
attack lane. Other agents own the others — do not review outside your lane, and do
not water down your lane to cover ground you assume they missed.

SWIP: <absolute path>
Your lane: Lane <N> — <name>, defined in <absolute path to references/swarm-attack-surface.md>
Write your report to: <absolute path>/lane<N>.md

Read the SWIP in full, then read your lane's section of the attack-surface reference
and work every bullet in it. Ignore the other lanes' sections.

The claim set the orchestrator extracted:
<paste claim set verbatim>

The baseline — how the system behaves TODAY, established from the implementation:
<paste baseline brief verbatim, with its file:line citations and any UNVERIFIED lines>

Reason from that baseline, not from your own recollection of how Swarm works. Where the
baseline is marked UNVERIFIED, or is silent on something you need, you may still reason
from general knowledge — but every such step goes in your ASSUMPTIONS ledger below, and
a finding that rests on one is capped at High, never Critical.

Your question at every bullet: what is the most profitable deviation available to an
actor here, and does the SWIP's text stop it?

Rules:
- A finding without a concrete failure path is not a finding. Steps an attacker or a
  diverging implementer actually takes, or drop it.
- Steelman first: find the sentence that is supposed to prevent the attack. If it
  exists and holds, discard. If it exists but is ambiguous, that ambiguity IS the
  finding.
- Quote the SWIP sentence you attack, cited by heading name — SWIPs are not numbered.
- The citation covers the claim you attack, not the background you reason from. The
  seam between new and existing behaviour is where live networks break, so attacking
  it is required — but take the existing half from the baseline brief and cite it by
  file:line, not from memory. Anything you take from memory instead goes in ASSUMPTIONS.
- Quoted third-party material inside the SWIP is in scope when it carries normative
  weight — an author's replies to a reviewer's objection are spec text if the design
  depends on them. The objection being quoted is not.
- Text incorporated by reference from outside the repo (a book, a paper, another
  project's spec) is not in scope to attack. The delegation itself is the finding.
  Raise it once; do not go read the external document.
- Never report spelling, grammar, markdown, links, or header fields.
- Do not rank your findings against other lanes' — you cannot see them. Assign
  severity per the table below on its own merits.

Severity — use these definitions verbatim:
- Critical: an actor profits at the network's expense, the network cannot reach
  agreement, or a confidentiality, integrity, or access-control property the SWIP
  claims does not hold.
- High: incentives drift the wrong way over time, two clients diverge on a value that
  matters, or rollout breaks live nodes.
- Medium: a reasonable implementer has to guess on something load-bearing, or the
  mechanism degrades under conditions the SWIP does not exclude, but the damage is
  bounded and recoverable.
- Low: underspecified, and guessing wrong is cheap to fix after the fact.

An unbounded, unvalidated, or overflow-prone on-chain parameter is Critical whenever
some value of it lets an actor bypass a check or inflate a reward.

Output exactly these three parts:

1. FINDINGS — each one:
   - a one-line claim, in whichever form fits:
     actor -> action -> gain  (exploit)
     ambiguity -> what two implementers do differently -> what breaks  (interop)
     claim -> what actually happens -> who is misled  (unmet promise)
   - the heading it attacks, plus the sentence quoted verbatim
   - the concrete path, as steps
   - severity, per the definitions above
   - what would close it: one sentence, not a redesign
2. ASSUMPTIONS — every piece of current-system behaviour you relied on that the
   baseline brief did NOT give you, one line each, naming the findings that depend on
   it. Write `none` if you worked entirely from the baseline. Be ruthless here: an
   assumption you forget to list is a finding that cannot be checked, and the synthesis
   agent will drop it rather than trust it.
3. UNFALSIFIABLE CLAIMS — load-bearing assertions in your lane with no argument,
   model, or citation behind them. An item that is both an unfalsifiable claim and an
   exploitable gap belongs in FINDINGS only, with the missing justification named in
   its closing line.
4. LANE VERDICT — one line: `findings: <count>` or `cleared` or `not applicable`,
   plus a clause of explanation. If you saw a weakness but could not build a failure
   path, say `cleared` and describe what you saw, so someone can take it further.

Write all four parts in full to your report file, headed `# Lane <N> — <name>`.
Then reply with your LANE VERDICT line and nothing else — do not repeat the report
in your final message.
```

### 4. Dispatch a grounding agent to check every assumption against the code

Collect the ASSUMPTIONS ledgers from all lane reports. Send **one** agent (`model:
"opus"`) to test them against the implementation. This is the step that stops the review
shipping confident nonsense, and it is cheap — one agent against a list.

```
Eight adversarial reviewers examined a SWIP. Each listed the current-system behaviour
it relied on but could not verify. Your job is to check those assumptions against the
real implementation and report which hold.

SWIP: <absolute path>
Implementation: <paths to the client and contract repos>
Baseline brief the reviewers were given:
<paste baseline brief>

Assumptions to check, with the findings that depend on each:
<paste every ASSUMPTIONS ledger, labelled by lane>

For each assumption: find the code that settles it. Report one of
  CONFIRMED — <file:line and the line itself>
  FALSE — <file:line and what the code actually does>
  PARTLY — <what holds, what does not, file:line>
  NOT FOUND — <where you looked; say this rather than guessing>

Read the actual function, not just its name — a name that matches proves nothing about
behaviour. Where the SWIP is already implemented, also report any place the code and
the SWIP text disagree, whether or not a reviewer asked: those divergences are findings
the lanes could not see.

Judge only what the code says. Do not defend the SWIP, do not re-review it, and do not
rule on whether a finding is serious — that is the synthesis agent's job. Report all
results in full in your final message and write them to <path>/grounding.md.
```

### 5. Dispatch one synthesis agent over all lane reports

When every lane agent has returned, send **one** agent (also `model: "opus"`) the paths
to every lane report. Its prompt:

```
Nine-lane adversarial review of a SWIP. Eight agents each reviewed one attack lane in
isolation; none could see the others. You produce the single report the author reads.

SWIP: <absolute path>
Claim set: <paste claim set verbatim>

Lane reports — read all of these files first:
<list every lane report path>

Grounding results — which assumptions survived contact with the implementation:
<path>/grounding.md

Read the SWIP yourself before judging the reports — you are the only agent that sees
both the whole document and all the findings, and lane agents working in isolation
sometimes attack a clause another section already answers.

Do this:
1. VERIFY. For each finding, check the quote against the SWIP and check the path
   actually follows. Drop findings whose quote is wrong, whose path breaks, or that
   another section of the SWIP already prevents — say which you dropped and why.
   Then apply the grounding results, which outrank every lane agent's reasoning:
   - an assumption came back FALSE -> drop every finding resting on it, and say so
   - PARTLY or NOT FOUND -> keep the finding but cap it at High and mark it
     `unverified: <the assumption>` so the author knows what to check first
   - CONFIRMED -> the finding stands on its cited baseline
   A finding the implementation already prevents is not a finding. Say which ones the
   code already handles — that is useful news for the author, delivered in one line,
   not a finding.
2. MERGE. The same root cause surfaces in several lanes under different names. Merge
   those into one finding, keeping the sharpest attack path and listing which lanes
   found it — a root cause that surfaced in three lanes is more serious than any one
   report of it made it look, and merging must not lose that.
3. RE-RANK. Lane agents assigned severity blind to each other. Re-rank across the
   whole set using the same definitions they were given. Raise a finding when other
   lanes' findings compound it; lower one that a lane over-called.
4. CUT. Anything that lands below Medium after re-ranking does not go in the main
   report.

Output exactly these five parts:
1. VERDICT — one line: is this ready for the next status, and the single biggest
   reason why not.
2. FINDINGS — Medium severity and above, ranked most severe first, renumbered F1..Fn.
   Keep each lane agent's structure: one-line claim, quoted heading and sentence,
   concrete path, severity, one-sentence fix. Add the lanes that found it.
3. UNFALSIFIABLE CLAIMS — merged across lanes, deduplicated.
4. BELOW THE LINE — every Low finding as a single line each. No detail. The author
   should be able to scan and ignore them.
5. LANE COVERAGE — one line per lane, `Lane N — Name`, carrying exactly one verdict:
   `findings F#, F#` / `cleared` / `not applicable`, plus a clause of explanation.
   A lane you never ran is not `cleared`.

Never inflate severity to look thorough, and never merge two genuinely different
attacks because they touch the same section. If everything that survived is Medium,
say so in the verdict.
```

### 6. Deliver

Clean up the cloned sources:

```
sh <skill dir>/scripts/fetch-sources.sh --clean <scratch dir>
```

Then give the author the synthesis agent's report. Do not re-summarise it or add your own
findings on top — you read the SWIP for briefing, not to review it, and a second
opinion appended to a ten-agent review just muddies the ranking. Say which lanes ran,
how many findings were dropped in verification, and — this one matters most — what the
baseline was checked against and what came back UNVERIFIED, so the author knows which
findings rest on read code and which rest on a reviewer's assumption.

**If the Agent tool is unavailable**, run the lanes yourself, sequentially, using the
lane prompt as your own instructions for each — then do the grounding and synthesis
passes. It is worse: you will be anchored by earlier lanes and will tire. Do all eight
anyway, and do not skip grounding — it is the step that keeps the review honest.

## Severity Calibration

This table is the only definition of severity. It goes verbatim into every agent prompt.

| Severity | Test |
|---|---|
| Critical | An actor profits at the network's expense, the network cannot reach agreement, or a confidentiality, integrity, or access-control property the SWIP claims does not hold |
| High | Incentives drift the wrong way over time, two clients diverge on a value that matters, or rollout breaks live nodes |
| Medium | A reasonable implementer has to guess on something load-bearing, or the mechanism degrades under conditions the SWIP does not exclude — bounded and recoverable |
| Low | Underspecified, and guessing wrong is cheap to fix after the fact |

The author's report carries **Medium and above** in full; Low findings get one line
each below the line. Inflating severity to look thorough destroys the review's value.

## Common Mistakes

| Mistake | Fix |
|---|---|
| Running one agent over all eight lanes | Depth collapses after the first serious find. One agent, one lane, in parallel |
| Letting lane agents run on the default model | Pass the strongest model explicitly on every dispatch |
| Dispatching lanes one at a time | All lane agents go in a single message, or they run serially for no reason |
| Briefing agents without reading the SWIP | The claim set is the only context they share; a vague one wastes eight agents |
| Pasting lane reports together as the report | Unverified, unmerged, unranked. The synthesis pass is where the review becomes usable |
| Routing eight full reports through your own context | Lane agents write files; you pass paths. You never need to hold the reports |
| Adding your own findings to the synthesis | You reviewed nothing; you briefed. Deliver what the review found |
| Restating the spec back to the author | Every paragraph must contain an attack, a gap, or a question |
| Attacking requirements the SWIP never made | Quote the sentence, or drop the finding |
| Assuming rational-honest actors | Assume every actor maximises their own payoff, including the contract deployer |
| Reviewing the SWIP against your memory of the protocol | Clone the client and contracts and read them; memory is two years stale |
| Grounding against a checkout you found on the machine | It may be stale, dirty, or one of four. Clone trunk yourself and record the sha |
| Leaving the clones behind | Clean them up in step 6; they are scratch, not a workspace |
| Skipping the baseline because the SWIP has a Context section | That section is the author's claim about today — one of the things you are checking |
| Treating an unimplemented SWIP and an already-merged one the same | Grep for the new names first; if it is built, spec-vs-code divergence is the review |
| Proposing a full redesign | One sentence on what would close it; the author owns the fix |
| Only attacking the new mechanism | Attack the seam between new and existing behaviour — that is where live networks break |

## Red Flags in a SWIP

Any of these means dig harder, not move on:

- "trivially", "obviously", "it is clear that" in front of a load-bearing claim
- A Backwards Compatibility section that says "none" while a format or contract changes
- A parameter with no derivation ("we set the minimum stake to X BZZ")
- Rewards or penalties with no stated bound, or bounds that depend on network size
- Migration described in prose with no described state at each step
- Test Cases empty or "to be added" on a proposal that changes data or message formats
- Rationale that lists no alternative that was rejected
- A Specification section that delegates the mechanism to an external document
