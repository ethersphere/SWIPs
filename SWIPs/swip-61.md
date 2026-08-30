---
SWIP: 61
title: BPS multihop — FCFS multicast tree
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-08-04
requires: 60
---

- **Business line**: audiences beyond one node's capacity — live streaming and event
  fan-out scaled by recruiting subscribers as relays, so a cohort's capacity grows with
  its audience instead of being fixed by the broker's stream limit — and streams that
  survive relay churn without interruption.
- **Dev line**: fill three reserved `Broadcast` control-plane fields of
  [bps.proto](assets/swip-61/bps.proto) (`Reparent`, `Probe`, `Candidates`), extend `Ack` with
  attachment candidates, forward `Publish` rootward, and implement three behaviours —
  subtree probing, dual-parent maintenance, make-before-break reparenting; done when a
  cohort scales past a single node's capacity in **both** directions, masks a single relay
  failure with no delivery gap, and unmodified SWIP-60 clients attach as leaves.
- DISC: the first time proper **forwarding by consumers** (subscribers as
  relays) is implemented; a wire-protocol change (reserved frames become normative),
  no storage or Bee-API change.
- Bandwidth-incentive integration is a separate SWIP (bps-bw-incentives).

## Simple Summary

SWIP-60 bounds a topic's audience by one broker's per-topic capacity. This SWIP removes
the ceiling: a full node answering a `Subscribe` **probes its own subtree over the
streams it already has** and returns the two shallowest free attachment points — and
the joiner attaches to **both**. Every node thus keeps two parents (typically sister
nodes): both feed it, duplicates are absorbed by SWIP-60's dedup rule, and the loss of
any single relay or link is masked, not suffered — the subtree below never notices,
while the affected node self-heals by re-running the join. A subscriber that accepts a
child thereby becomes a **relay**; the tree grows first-come-first-served, with no
control traffic while nobody is joining. End-to-end authentication is unchanged: a
relay can withhold, never forge — and with two feeds to compare, withholding shows.

## Motivation

One principle carries over from SWIP-60 and does all the work here: **forwarders are
subscribers**. A forwarder is simply a subscriber that fans out messages to subscribers
of its own; singlehop is the depth = 1 variant of the same structure, and the broker
remains the root in every configuration. Scaling to large audiences is then not a new
protocol but the removal of one restriction — the singlehop rule "at capacity, refuse
with `FULL` and nothing else" is replaced by referral to where capacity is. Placement
quality is explicitly **not** the join protocol's problem: FCFS means the first free
slot found wins. What multihop must not compromise is the contract itself: messages
arrive at **all subscribers** — a live stream that drops messages on relay churn is
broken, so churn tolerance is built into the topology, not patched on.

## Specification

### The seam from SWIP-60

Everything in SWIP-60 stands — cohort genesis (`CohortSpec` untouched), bindings and
dedup rules, publisher legitimacy, the admin's service feed, the `Hello`/`Ack`
establishment, self-contained SOC frames, end-to-end verification — with **two**
amendments:

**1. The capacity rule.** A relaying node at capacity answering a `Subscribe` MUST NOT
bare-refuse; it probes its subtree and answers `Ack(FULL)` **with the two shallowest
attachment points found** (new `candidates` field, number 6 — 3–5 are SWIP-60's service
SOCs). A SWIP-60-only client ignores the unknown field and reads a plain refusal.

**2. Publishing is no longer confined to the root.** SWIP-60's publishers attach directly
to the broker, but that is a consequence of depth = 1 rather than an invariant: `Publish`
now travels **rootward**, forwarded hop by hop to the broker, which validates, dedups and
broadcasts it back down. Multihop therefore restructures **both** directions, not the
audience side only — which is what an everyone-publishes cohort (SWIP-60's `ALL`, and any
`GRANTED` cohort larger than one node's capacity) needs in order to exist at all.

`Open` still goes to the broker, because opening a cohort *is* contacting the root. Its
admin is thereafter an ordinary publisher and may sit at any depth like any other.

There is **no depth bound**: the tree grows as deep as joins take it, and depth is
self-limiting because it is priced — see the Rationale.

**What a relay owes a joiner.** SWIP-60's `Ack` carries the echoed `CohortSpec`, the
admin-signed genesis SOC and the latest service SOC with its index. A relay answering a
`Subscribe` MUST pass on all three, unchanged — it holds them from its own join, and
keeps the service SOC current from the broadcasts it already receives. **Depth must cost a
subscriber nothing in what it can verify**: a leaf ten hops out checks the cohort and the
roster against the admin's key exactly as the broker's own child does, so the extra
intermediaries add withholding points and no forging points. A relay that serves a stale
service SOC is withholding, which its subscriber detects as an index gap.

Cohorts with `spectators: false` are unchanged in kind: any node answering a `Subscribe`
applies the same roster check, and it can, because it holds the roster.

### Roles

- **Broker** — as in SWIP-60: root of the tree, target of `Open`, default entry point for
  joins, and the point at which every `Publish` is validated and deduped, wherever it
  originated. It is no longer the *attachment* point for publishers.
- **Relay** — a subscriber with children: re-broadcasts every SOC frame down its own
  direct streams, forwards its children's `Publish` frames up its own, answers `Subscribe`
  like any parent (passing on the `CohortSpec` and the two service SOCs it holds), and
  forwards and aggregates probes. There is no promotion step: **accepting your first child is what becoming a
  relay means.** Relay capability is latent in every subscriber — the `Ack`-echoed
  `CohortSpec` from its own join is exactly what it echoes to children of its own. Any
  full-node subscriber is relay-eligible; NAT'd and light-client relays are reachable
  if the transport can dial them (see NAT'd relays below), not required — a node unable
  or unwilling to relay simply has capacity 0 and refuses.
- **Leaf** — a subscriber with no children; the SWIP-60 subscriber role verbatim. A
  SWIP-60 client is a conformant leaf (single-parented — it forgoes the resilience,
  not the stream).

### Join: probe and attach (FCFS)

A joiner sends `Subscribe(topic)` to the broker (or any cohort node it already knows).
A node with a free slot accepts on the spot: `Ack(OK, CohortSpec)`. A full relaying
node **searches its own subtree before answering** — over the streams it already has:

1. **Probe down.** The full node sends `Probe{depth}` to its children, `depth` being
   the receiver's depth (root's children = 1). A full child forwards the probe to its
   own children, incrementing `depth`; a child with a free slot replies instead of
   forwarding; a capacity-0 child replies empty (or not at all — see below).
2. **Filter up.** A node with a free slot answers `Candidates` naming itself
   `{addr, depth}`. A forwarding node collects its children's replies within a bounded
   wait (parameter), keeps the **two smallest-depth** candidates, and passes
   them up.
3. **Answer.** The originating node answers the joiner `Ack(FULL, candidates)` — the
   two shallowest attachment points of its subtree. No candidates ⇒ bare `Ack(FULL)`:
   the probe came back empty, the subtree genuinely cannot host the joiner.
4. **Attach — to both.** The joiner `Subscribe`s at **both candidates**: the two
   resulting streams are its two parents (see Resilience). A candidate lost to a race
   is replaced by re-`Subscribe`ing at the origin. **A join is ideally a two-step
   process** — one round to learn where, one to attach — regardless of tree size.

The probe wave stops at the first non-full node on every path: nothing below a free
slot is ever searched. Depth travels **in the probe itself**, incremented hop by hop —
no node knows or stores its own position, so there is nothing to go stale when the tree
is reorganised. And there is no standing state anywhere: an idle cohort is perfectly
silent, state is gathered on demand and discarded. A node MAY reuse candidates from a
just-completed probe for immediately subsequent joins instead of re-probing.

Preferring shallow slots is deliberate: min-depth filtering fills the tree
breadth-first, keeping delivery paths short — and it agrees with the incentive gradient
(upstream pricing is depth-scaled), so the protocol default and the economics point the
same way. It is still FCFS, not optimality: candidates race, replies are best-effort
within the wait bound, and the first slot won wins.

### Publishing from depth

A publisher no longer needs a stream to the broker. `Publish` rides the same (peer, topic)
stream as everything else, in the **opposite direction** to `Broadcast`: a node accepts a
`Publish` from a child and forwards it to its own parent, hop by hop, until it reaches the
root. The broker validates it against the `CohortSpec` and the current roster, applies the
binding's dedup rule, and broadcasts it back down — so it returns to the publisher along
with everyone else, and a publisher's own message reaching it is its delivery receipt.

- **Where validation happens.** Authoritatively at the broker, which is the single point
  every publish passes through and therefore the only place dedup is well defined. Any
  relay MAY drop a `Publish` it can already tell is invalid — it holds the `CohortSpec` and
  the roster, so it can check the signature, the binding and the authorship — and SHOULD,
  since carrying a doomed frame up d hops wastes every one of them. This is an
  optimisation, never a substitute: a relay that forwards everything is conformant, and
  one that drops a *valid* frame is withholding.
- **Publish up both parents.** A node with two parents sends each `Publish` up both. The
  dedup rule absorbs the double at the first node that sees both — usually the sisters'
  shared parent — and the redundancy buys upstream exactly what the two feeds buy
  downstream: **a single relay cannot silently swallow a publish.** Where a subscriber has
  chosen to be single-parented (see below), its publishes inherit that choice's exposure.
- **Depth is priced, not bounded.** Upstream pricing (bps-bw-incentives) is depth-scaled,
  so a publisher d hops out pays for d hops. A publisher that cares about its own latency
  or cost buys a shallower attachment; nothing in the protocol needs to stop it.

The contract is unchanged in substance — messages come from publishers only and arrive at
all subscribers — but its enforcement point is now explicit: **authorship is decided at the
root, and verified again by every subscriber.** Relays in between are conveniences, and a
dishonest one can delay a message or drop it, never author one.

**Revocation across a tree.** SWIP-60's two-phase revocation is unchanged in rule and
lands one hop out: the roster update is an ordinary broadcast, so it reaches every node,
and the revoked publisher's **parents** are where enforcement happens — they are the nodes
accepting its `Publish` frames. Before the update reaches them they drop those frames and
tolerate them, exactly as a singlehop broker would; after it arrives, a further publish is
a protocol violation and the parent breaks the stream. The revokee learns of its own
revocation from the same broadcast, at the same time, which is what makes the second phase
fair at any depth.

### Resilience: two parents

Churn-related misses are not tolerated: the contract says messages arrive at all
subscribers, and a live stream cannot pause for tree repair. So redundancy is
structural:

- **Every node maintains two parents** — the probe's two candidates; by min-depth
  filtering these sit at (near-)equal depth, typically **sister nodes**. The two
  parents MUST be distinct; while the cohort is too small to offer two (e.g. the
  broker's first children), a node stays single-parented and upgrades when it can.
- **Both parents feed.** Each parent treats the node as an ordinary child and streams
  every frame; frames are self-contained SOCs and the binding's dedup rule (SWIP-60)
  suppresses the duplicate — this is the make-before-break overlap made permanent.
- **Single failure masks.** If a relay or a link fails, every child of the failed node
  keeps receiving through its other parent, so **the subtree below notices nothing**;
  masking is recursive — each level's redundancy protects the level below.
- **Self-healing is the join protocol re-run.** The half-orphaned node acquires a
  replacement second parent by `Subscribe`ing at its surviving parent (accepted
  directly, or answered with fresh candidates via probe). No dedicated repair
  machinery.
- **Withholding becomes visible.** With two independent feeds, a parent whose stream
  persistently lags its sister's is caught by comparison; the node drops it and
  replaces it the same way — demotion, not detection heroics.

The price is stated, not hidden: each subscription consumes two tree slots and every
message crosses every level twice, roughly doubling bandwidth. Resilience is bought,
and per-hop pricing (bps-bw-incentives) is what will price it; an active/standby
variant (second parent connected but mute until asked) trades the gap-free guarantee
for half the traffic and is deliberately **not** specified here.

On cohorts running **self-indexed feeds
([SWIP-65](https://github.com/ethersphere/SWIPs/pull/106))** a delivery gap is
detectable at the next frame and recoverable from storage, so a second parent is **not
required** — for a subscriber content with recovery latency it is pure extra cost, and
forgoing it is a per-subscriber choice: single-parented nodes are already well-formed
(SWIP-60 leaves), and a single-parented relay endangers only itself — its children
hold their own second parents. Dual parenting remains the costlier-but-faster product
for gap-intolerant subscribers (the live edge). Conformance items 5–6 read
accordingly.

### Reparenting (`Reparent`) — make-before-break

`Reparent{to}` is the parent→child instruction to move: the child `Subscribe`s to the
new parent, waits for `Ack(OK)` confirming the stream is live, and **only then** drops
the old stream. During the overlap the dedup rule absorbs doubles, as everywhere.

Two cases:

- **graceful leave** — a departing relay `Reparent`s each child toward **its own parents**
  before closing; the child's flow continues on its other parent throughout the move. Its
  parents are the right target because they are known-live, known-compatible and at the
  departing node's own depth minus one, so the subtree gets shallower rather than deeper;
  handing children to one another would deepen the tree and has no answer for the first
  child;
- **churn repair** — is the *absence* case: BPS has no keepalive, so a parent's death
  surfaces as a transport-level stream reset or connection loss; no `Reparent` arrives,
  the surviving parent carries the stream, and the node re-runs the join for a
  replacement.

Only a *simultaneous* loss of both parents opens a delivery gap; that is then a
liveness fault like any other — repaired by rejoin from the broker, with no recovery of
the gap itself (a resumed subscriber is in the same position as a fresh one).

### NAT'd relays

Reaching a NAT'd relay is the transport's business, not this protocol's: libp2p circuit
relay + DCUtR hole punching (the DCUtR work item, bee
[#5355](https://github.com/ethersphere/bee/issues/5355)). BPS carries no signalling for
it — the only tree-relevant observation is that a NAT'd child's **parent is its natural
circuit relay**, so a candidate a probe returns can be handed out under an address the
transport knows how to dial.

### Information flow (probe and attach)

```mermaid
sequenceDiagram
    autonumber
    participant J as joiner
    participant B as broker (root, full)
    participant C as child C (full)
    participant X as grandchild X (free slot)
    participant Y as grandchild Y (free slot)

    J->>B: Subscribe(topic)
    Note over B: at capacity — probe the subtree<br/>over existing streams
    B->>C: Probe{depth: 1}
    C->>X: Probe{depth: 2}
    C->>Y: Probe{depth: 2}
    X-->>C: Candidates[{X, 2}]
    Y-->>C: Candidates[{Y, 2}]
    C-->>B: Candidates[{X, 2}, {Y, 2}] (min-2 filtered)
    B-->>J: Ack(FULL, candidates: [{X, 2}, {Y, 2}])
    par attach to both
        J->>X: Subscribe(topic)
        X-->>J: Ack(OK, CohortSpec)
    and
        J->>Y: Subscribe(topic)
        Y-->>J: Ack(OK, CohortSpec)
    end
    Note over J,Y: two parents, sister nodes —<br/>either may fail unnoticed
```

### Process: a subscriber's lifecycle

```mermaid
flowchart TD
    S["Subscribe at broker or<br/>any known cohort node"] --> Q{"free slot?"}
    Q -- "yes" --> A["Ack(OK, CohortSpec)<br/>attached"]
    Q -- "no — relaying node" --> P["probe subtree<br/>over existing streams"]
    Q -- "no — capacity 0" --> F["bare FULL"]
    P --> C{"candidates<br/>found?"}
    C -- "two" --> D["attach to both:<br/>two parents, sisters"]
    C -- "none" --> F
    A --> L
    D --> L["LIVE: both parents feed,<br/>dedup absorbs doubles"]
    L -- "one parent fails<br/>or withholds" --> M["survivor carries the stream —<br/>subtree below notices nothing"]
    M --> R["re-run join at survivor:<br/>replacement second parent"]
    R --> L
    L -- "both parents fail" --> G["liveness fault"]
    G -- "rejoin from broker" --> S
```

### Wire protocol

Amendments to [bps.proto](assets/swip-61/bps.proto) — three reserved `Broadcast` control-plane fields
become normative, the rest stay reserved; control frames ride the `Broadcast` envelope
in **both directions** on a (peer, topic) stream (`Candidates` flows child→parent);
frame type and direction disambiguate. On submission the amended file goes to
`assets/swip-61/`. `CohortSpec` is untouched:

```proto
message Ack {
  Status     status  = 1;
  CohortSpec cohort  = 2; // set iff status == OK
  Soc        genesis = 3; // SWIP-60: service feed index 0
  Soc        service = 4; // SWIP-60: latest service SOC
  uint64     index   = 5; // SWIP-60: its feed index
  repeated Candidate candidates = 6; // set iff FULL at a relaying node: the two
                                     // shallowest attachment points the probe found.
                                     // Field 6, not 3 — 3–5 are SWIP-60's service SOCs
}

// unchanged from SWIP-60, but no longer publisher -> broker: a node forwards a
// child's Publish to its own parent(s) until it reaches the root
message Publish {
  Soc soc = 1;
}

message Broadcast {
  oneof frame {
    Soc        soc      = 1; // as SWIP-60
    Reparent   reparent = 2; // parent -> child
    Probe      probe    = 3; // parent -> child: find free slots below
    Candidates found    = 4; // child -> parent: probe reply, min-2 filtered
    // 5–15 remain reserved
  }
}

// parent -> child: re-point, make-before-break
message Reparent {
  bytes to = 1; // overlay address of the new parent
}

// depth of the receiver, incremented at each forwarding hop —
// no node stores its own position
message Probe {
  uint32 depth = 1;
}

// at most two, smallest depth first
message Candidates {
  repeated Candidate candidates = 1;
}

message Candidate {
  bytes  addr  = 1; // overlay address of a node with a free slot
  uint32 depth = 2; // its depth at probe time
}
```

## Rationale

**Why no standing capacity state — beacons, slot counts, subtree summaries?** Because
any standing summary must be kept fresh on every edge forever and is stale by
construction. The probe gathers exactly the state one join needs, at the moment of
needing it, and discards it; an idle cohort is perfectly silent — the same philosophy
that keeps keepalives and capacity advertisement out of BPS altogether (SWIP-60).

**Why does the tree search, and not the joiner?** Cost asymmetry. A probe hop rides a
stream that already exists — one frame each way; a joiner's probe is a fresh dial to a
stranger — connection setup, handshake, possibly NAT traversal. Letting the tree run
the search over its own edges and handing the joiner two ready candidates turns a chain
of expensive dials into a wave of cheap frames plus two dials.

**Why two live parents rather than a standby?** Because the failure this design must
mask is precisely the one a standby cannot: messages sent during the window between a
parent dying and anyone noticing. There is no keepalive to notice with — liveness is
the transport's job, and transport-level detection has latency. Two always-on feeds
close that window structurally, cost 2×, and come with a side effect no standby offers:
withholding is caught by comparing the feeds.

**Why no depth bound?** Because depth already has a price, and now on both sides. Per-hop
pricing (bps-bw-incentives) is depth-scaled upstream, so joiners are economically steered
toward the root and deep chains cost their occupants; with `Publish` travelling rootward
the same gradient bills a *publisher* for its depth, which is the case where the incentive
bites hardest. A protocol-level `max_depth` would duplicate that signal with a blunter
instrument, and give the tree a notion of "full" it does not otherwise need.

An earlier draft anchored this argument on the closed cohort — the one shape that had to
stay at depth 1 because its publishers attached directly to the root. That anchor is gone
twice over: `closed` no longer exists in SWIP-60, and publishers no longer attach to the
root. **No configuration requires depth 1.** The argument stands on the price alone, which
is where it belonged.

**Why is a publish validated at the root rather than at the edge?** Because dedup needs a
single vantage point. The binding's dedup rule is a statement about what a cohort has
already seen, and only the broker sees everything; a relay applying it locally would
suppress a message some sibling subtree never received. Signature and authorship checks, by
contrast, are local and stateless, so relays may and should run those early — dropping a
frame that could never be accepted costs nothing and saves d hops. The split is the usual
one: **stateless checks anywhere, stateful ones where the state is.**

**Why do relays get nothing here?** They do — later. Metered per-hop pricing is
bps-bw-incentives' business; this SWIP keeps the edges it will price. Until then,
relaying is the same volunteer economics as singlehop brokering.

**Why is withholding still tolerable with more intermediaries?** Unchanged from
SWIP-60 in principle — authentication is structural (SOC signature against the topic
binding, verified against the `Ack`-echoed `CohortSpec` at any depth), so adding relays
adds withholding points but no forging points — and strengthened in practice: a
withholding parent is exposed by its sister's feed and replaced by the ordinary
self-healing path.

## Out of scope (deliberately)

Paying for forwarded messages (bps-bw-incentives); message history — delivery of
messages from before the subscription (bps-history); broker discovery (SWIP-59 MEX);
NAT traversal — circuit relay and hole punching are transport business (the DCUtR item);
and the admin's control plane itself — grants, revocations and end-of-stream are SWIP-60's
service feed, and reach every depth as ordinary broadcasts, so this SWIP adds nothing to
them.

## Conformance (definition of done)

An implementation is conformant when:

1. a relaying node at capacity answers `Subscribe` with `Ack(FULL, candidates)` — the
   two smallest-depth attachment points its probe returned; bare `FULL` only on an
   empty probe, or from a node that cannot or will not relay;
2. a probe wave terminates: nodes with a free slot reply and do not forward, and
   forwarding nodes answer within the wait bound with the min-2-by-depth filter of what
   arrived;
3. an accept carries the echoed `CohortSpec` **and** the genesis and latest service SOCs
   with the service index, unchanged, from whatever depth it is issued — a subscriber ten
   hops out verifies the cohort and the roster against the admin exactly as the broker's
   own child does;
4. absent races, a join completes in two steps: one probe round, one (dual) attach;
5. a node offered two distinct parents maintains both — except on self-indexed cohorts
   ([SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)), where the second parent
   is optional per subscriber and items 5–6 bind only nodes that maintain one;
   duplicate deliveries never surface past the binding's dedup rule;
6. the failure of any single relay or link causes no delivery gap anywhere below it;
   the half-orphaned children re-acquire a second parent via the ordinary join;
7. every reparent is make-before-break;
8. an unmodified SWIP-60 client attaches as a leaf anywhere in the tree and cannot
   distinguish its parent from a singlehop broker;
9. a subscriber at any depth re-verifies every message end-to-end; loss of both
   parents is a liveness fault repaired by rejoin;
10. a `Publish` from any depth reaches the root, is validated and deduped there, and is
    broadcast back down to the whole cohort including its own publisher; a node with two
    parents publishes up both, and the dedup rule absorbs the double;
11. a relay MAY drop a `Publish` that fails a stateless check (signature, binding,
    authorship) but MUST NOT apply the binding's dedup rule locally, and one that forwards
    everything is conformant;
12. a revoked publisher's frames are dropped and tolerated by its parents until the
    reduced roster reaches them, and the stream is broken only on a publish after that.

## Backwards compatibility

Same stream name `pubsub/1.0.0`, no version bump: `Reparent`, `Probe` and `Candidates`
fill `Broadcast` oneof fields reserved by SWIP-60, and the single new `Ack` field
is invisible to old implementations — an old client ignores `Ack.candidates` and reads
a plain `FULL`. A SWIP-60 leaf that receives a `Probe` ignores the unknown frame and
never replies — exactly the empty answer the bounded wait absorbs, which is why old
leaves are compatible by construction (single-parented, without the resilience).
`CohortSpec` is untouched, and `Ack.candidates` takes field 6 so that SWIP-60's service
SOCs keep 3–5. SWIP-60's conformance item 4 ("`FULL` — and nothing else") is superseded for
nodes implementing this SWIP, as is its statement that a publisher is attached to the
broker — true at depth 1, and a consequence of it rather than a rule.

## References

[SWIP-60](https://github.com/ethersphere/SWIPs/pull/104) / PR
[#104](https://github.com/ethersphere/SWIPs/pull/104) · wire: [bps.proto](assets/swip-61/bps.proto) ·
origin: [PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" ·
implementation groundwork: bee [#5435](https://github.com/ethersphere/bee/pull/5435) ·
DCUtR: [bee#5355](https://github.com/ethersphere/bee/issues/5355)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
