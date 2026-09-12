# Swarm Attack Surface — review lanes

Work these lanes in order. For each, the question is always: *what is the most
profitable deviation available to an actor here, and does the SWIP's text stop it?*

Not every lane applies to every SWIP. Decide explicitly and say which you cleared.

---

## Lane 1 — Incentives and game theory

The lane that kills most Swarm proposals. Swarm pays nodes to store and serve data; any
change to who gets paid, how much, or when, changes what a rational operator does.

- **Free-riding**: can an actor collect the reward without doing the work? Can they
  claim to store a chunk they discard, serve from another node's cache, or pass a
  proof they did not compute?
- **Sybil**: does the payoff grow with identity count? Splitting one node into N is
  cheap unless stake or work is the binding constraint. Check that the constraint is
  *per unit of stake*, not per identity.
- **Timing games**: can an actor join immediately before a reward event and leave after?
  Is eligibility bound to elapsed time, stake age, or only to a snapshot?
- **Griefing**: what does it cost to make an honest node lose money? If griefing is
  cheaper than the loss inflicted, it will happen.
- **Collusion**: does a coordinating minority in one neighbourhood gain more than the
  same nodes acting independently? Neighbourhoods are small — a "51% attack" is local.
- **Selective service**: can a node profit by storing everything but serving only when
  observed? Distinguish *proof of storage* from *proof of service*.
- **Parameter sensitivity**: for each constant, what happens at 0.1x and 10x? Which
  parameters can the network's own growth push out of their safe range?
- **Payoff at the edges**: does the mechanism still favour honesty at very low network
  size, very high churn, or when BZZ price moves an order of magnitude?

## Lane 2 — On-chain and contract surface

Swarm's staking and redistribution live in contracts on Gnosis Chain.

- **Front-running / MEV**: is any transaction profitable to observe and pre-empt?
  Commit-reveal that reveals in one transaction is not commit-reveal.
- **Randomness**: where does the anchor or seed come from? Can a proposer, miner, or
  participant bias or predict it? Can they abort and retry cheaply?
- **Upgrade and ownership**: who can change parameters or pause? What can that role
  steal or freeze? Is it a multisig, and is that stated?
- **Gas and griefing on-chain**: unbounded loops over participants or neighbourhoods,
  storage growth with no pruning, transactions that get more expensive as adoption grows.
- **Rounding and precision**: integer division in reward splits — who gets the dust,
  and can a participant engineer the remainder in their favour?
- **Reentrancy and external calls**: any token transfer or callback before state is
  settled.
- **Migration**: is there a block or window where the old and new contracts are both
  live? Can value be claimed twice across that seam, or stranded?

## Lane 3 — Network and protocol

- **Eclipse and routing**: can an adversary control a target's view of the network, or
  of one neighbourhood? Kademlia neighbourhoods are the unit to attack, not the whole net.
- **Neighbourhood targeting**: can an actor choose which neighbourhood to land in by
  grinding an overlay address? What does landing in a chosen neighbourhood buy them?
- **DoS and amplification**: does a cheap request cause expensive work? Is there a
  request that makes a node do unbounded retrieval, storage, or signature verification?
- **Churn and partial deployment**: what does the network do while only some nodes have
  upgraded? A protocol that requires simultaneous adoption needs to say so.
- **Message-level**: unauthenticated messages, replayable messages, missing nonce or
  epoch, no size bound on a field, no timeout stated.
- **Bandwidth accounting**: does the change let one peer consume another's bandwidth
  without paying for it in the accounting protocol?

## Lane 4 — Data, crypto, and formats

- **Chunk and manifest formats**: fixed-size assumptions, span encoding, BMT hashing —
  does the change preserve them, and if not, is the break stated?
- **Key management**: where do keys live, who can rotate, what happens on compromise,
  is there forward secrecy where the SWIP implies it?
- **Encryption claims**: is the claimed property confidentiality, access control, or
  deniability? Access control is not confidentiality against a party who once had access
  — revocation of already-distributed material is generally impossible; check the SWIP
  does not claim otherwise.
- **Metadata leakage**: what does an observer learn from sizes, timings, access
  patterns, or the shape of a trie, even when contents are encrypted?
- **Determinism**: given the same input, does every implementation produce the same
  bytes and the same hash? Any map iteration, floating point, or locale in the spec is a
  bug.
- **Replay across contexts**: is a signature or proof bound to the chain id, contract
  address, epoch, and purpose?

## Lane 5 — Specification completeness

- Every field: type, width, byte order, and valid range stated?
- Every operation: what happens on failure, timeout, and malformed input?
- Every list: is there a maximum length?
- Zero, one, and maximum: is behaviour defined at each?
- Ties: two equal values, two equal distances — who wins, deterministically?
- MUST / SHOULD / MAY used deliberately, or is normative strength left to the reader?
- Are pseudocode, formulas, and prose consistent with each other?

## Lane 6 — Backwards compatibility and rollout

- What breaks for nodes that do not upgrade? For existing stored data? For existing
  stamps, batches, or stakes?
- Is there a flag day, a version negotiation, or a grace period — and is it specified
  or merely mentioned?
- Can the change be rolled back after deployment? If not, say so explicitly.
- Do existing SWIPs, API endpoints, or client tooling contradict this one? Check
  `requires`/`replaces` headers actually match the dependencies in the text.

## Lane 7 — Operational reality

- Who has to do something for this to work: node operators, gateway runners, the
  foundation, app developers? Will they?
- Does it increase hardware, bandwidth, or attention cost for a node operator, and is
  that cost compensated?
- Is failure observable? If the mechanism silently degrades, how would anyone find out?
- What is the monitoring or metric that says this is working in production?

## Lane 8 — Scope and framing

- Is this one proposal or three? SWIP-0: "the more focused the SWIP, the more successful".
- Does the Motivation describe a problem that exists, with evidence, or a hypothetical?
- Is there a cheaper change that gets most of the benefit? If the Rationale rejects no
  alternative, the design space was never searched.
