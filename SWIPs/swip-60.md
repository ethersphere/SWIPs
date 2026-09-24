---
SWIP: 60
title: BPS singlehop — brokered broadcast pub/sub, the full singlehop protocol
author: Viktor Trón (@zelig), Viktor Tóth (@nugaon)
discussions-to: https://discord.gg/Q6BvSkCv
status: Draft
type: Standards Track
category: Networking
created: 2026-08-03
---

<!-- Full singlehop SWIP of the Broadcast Pub/Sub (BPS) family: the decomposition of the
monolithic PubSub SWIP (ethersphere/SWIPs PR #93) into work-package-sized SWIPs. Extends
the base wire of SWIP-74 (BPS-lite, PR #111) and changes nothing in it. Companion
protobuf: assets/swip-60/bps.proto (revision 9, derived from SWIP-74's block). -->

- **Business line**: real-time topic streams for dApps without storing chunks or polling —
  enough on its own for the five cohort shapes it defines: **jam** (a closed set of authors:
  collaborative remix editing, a strudel livecoding session, a multiparty game),
  **spectator-jam** (the same before an audience), **live-stream** (one author, an audience),
  **group-chat** (everyone speaks) and **implicit** (a live feed with no authority at all).
  An admin grants and revokes authors while a cohort runs, without redefining it.
- **Dev line**: implement one libp2p protocol (`pubsub/1.0.0`, messages in
  [bps.proto](assets/swip-60/bps.proto)) plus a WebSocket bridge on the Bee API; done when
  a broker, publishers and subscribers interoperate per the conformance section. Groundwork
  exists in bee [#5435](https://github.com/ethersphere/bee/pull/5435).
- **Base**: [SWIP-74 BPS-lite](https://github.com/ethersphere/SWIPs/pull/111) — one
  publisher over a feed, one broker, one hop, four frames and a claim handshake. This
  SWIP adds cohort parameters, the admin's service feed and the Bee API on top of that
  wire and never changes it: a SWIP-74 peer is a conformant peer of the live-stream
  configuration below.
- Bandwidth-incentive integration is a separate SWIP (bps-bw-incentives).
- Broker discovery integration is from a separate SWIP (bps-broker-discovery, building on
  [SWIP-59 MEX](https://github.com/ethersphere/SWIPs/pull/103)).

## Simple Summary

A real-time messaging protocol: WebSocket clients publish and subscribe to topic streams
through Bee nodes. One full node per cohort acts as **broker**, re-broadcasting each message
over direct, long-lived p2p streams to a capacity-bounded set of connected peers. Messages are
single-owner chunks, so every subscriber verifies authorship end-to-end; the broker can
withhold, never forge.

## Motivation

Swarm's event primitives (GSOC, PSS) require full-node operation; light clients can only
poll storage. [SWIP-74](https://github.com/ethersphere/SWIPs/pull/111) is the smallest
protocol that fixes this for one publisher; BPS singlehop is the smallest that fixes it for
every cohort shape, on the same wire: one broker, direct streams, authenticated messages,
an admin's control plane, an explicit capacity bound. Everything larger — multihop trees,
adaptive reorganisation, incentives, discovery — is layered on top by later SWIPs without
changing the semantics defined here.

## Specification

### The contract

Per topic-cohort:

- messages come from **publishers, and publishers only**;
- they arrive at **all subscribers**.

### Cohort genesis: the parameters

A cohort is fully described by a `CohortSpec` ([bps.proto](assets/swip-60/bps.proto)), fixed
the moment the first peer brings it to a BPS-speaking full node, and **immutable for the
cohort's lifetime**. **The spec is the cohort's identity**: every joiner carries it, cohorts
are keyed by its canonical serialisation (SWIP-74), and two specs that differ in any field
are two cohorts, even on one topic. There is no mode
enum; **modes are combinations of these parameters**.

| parameter | values | meaning |
|---|---|---|
| `topic` | 32 bytes | interpreted per `binding` |
| `binding` | `MNEMONIC` / `ANCHOR` / `SOC_ID` / `OWNER` / `FEED_TOPIC` | what the topic binds to; fixes which SOCs qualify as messages and the dedup rule |
| `admin` | eth address | the cohort's authority and a member of its publisher set — not necessarily the first to join. **Absent ⇒ implicit authorship**, and the two fields below do not apply |
| `publishers` | `ALL` or unset | set: anyone attached may author — no claim; a stream declares the address it publishes as, and every message it sends is validated against it. Unset: the admin, and whoever its roster ever names — **a cohort is multi-publisher iff its admin ever publishes a roster**, and nobody needs to know in advance |
| `closed` | bool, unset = open | set: no audience — a joiner receives nothing until its claim recovers to the admin or a rostered address, and is disconnected otherwise |
| `history` | bool | deliver matching chunks already in the local store (mechanism in bps-history; a singlehop broker MAY refuse) |

**The publisher list is deliberately not here.** It is dynamic — an admin grants and revokes
while the cohort runs — and this spec is immutable, so it cannot live in it without making
every roster change a new cohort. It is also not public in the way the rest of the spec is:
the owner of a stream, or of a co-edited file, is naturally known to its subscribers, but the
other grantees are not. The roster therefore travels as **admin-signed service messages on a
feed of its own** (below), where it changes without the cohort changing, and where a
subscriber verifies it against the admin's key rather than against the broker's word.

#### The five configurations

| configuration | `admin` | `publishers` | `closed` | who may author |
|---|---|---|---|---|
| **jam** | set | unset | true | admin + current grantees; nobody else attends |
| **spectator-jam** | set | unset | unset | admin + current grantees, before an audience |
| **live-stream** | set | unset | unset | the admin alone, before an audience — **SWIP-74's cohort**: a spectator-jam whose admin never publishes a roster |
| **group-chat** | set | `ALL` | unset | anyone attached — each peer signs its own SOCs |
| **implicit** | absent | — | unset | whoever the binding's SOC shape admits |

Live-stream and spectator-jam are one spec: nothing in it promises a single author in
advance, and nothing needs to — the audience verifies every message against the admin's
key and the roster it has seen, and a roster that never comes is a stream with one
author. `closed` does real work only where a roster decides authorship — the jam rows,
which is exactly the audience / no-audience distinction. Under `ALL` and under implicit
authorship every attached peer is already a potential author, so excluding non-publishers
excludes nobody; a spec MUST leave it unset there — a broker answers a `closed` `ALL` or
implicit spec with `REJECTED`.

**The admin is always in the publisher set**, and being a publisher obliges nobody to
publish — no peer waits on another — so a practically non-publishing **moderator** needs no
role of its own: it is simply an admin that never sends.

Binding semantics (dedup rule in parentheses):

- **`MNEMONIC`** — the topic constrains nothing: it names the cohort and no more. Any SOC
  from any owner qualifies (dedup on chunk address). This is what `ALL` needs. Authorship is
  unrestricted but never *unattributable*: every message is still SOC-signed, so a group chat
  knows exactly who said what without there being an authorised set to check it against.
- **`ANCHOR`** — topic = full SOC/GSOC address; all messages share one address (dedup on
  the wrapped CAC — the guard against unsolicited republication of old SOCs, sound only
  under an application-level requirement: payloads are distinct, i.e. the application
  includes some index in the payload). **Under explicit authorship the address check does
  not apply**: several owners cannot share one SOC address, so the topic is a rendezvous,
  legitimacy is roster membership (below), and only the wrapped-CAC dedup remains.
- **`SOC_ID`** — topic = SOC id; any owner with `PO(socAddr(id, owner), anchor) ≥ PO_MIN`
  qualifies (dedup on chunk address).
- **`OWNER`** — topic = `keccak256(owner)`; any id under the same PO constraint — MIC
  semantics (dedup on chunk address). The broker never inverts the hash: it recovers
  the owner from the SOC signature and checks `keccak256(owner) == topic`; the topic
  doubles as the PO anchor.
- **`FEED_TOPIC`** — id = `keccak256(topic ‖ index)`; feed-update streams, graffiti MIC
  (dedup on chunk address).

Under **explicit authorship** legitimacy is membership of the current roster, not proximity:
the PO constraint does not apply. Under **implicit authorship** nothing is checked against a
roster — there is none, and no admin either — and authorship is decided by **the shape of the
SOC** the binding fixes:

| binding | SOC shape | implicit publishers | who qualifies |
|---|---|---|---|
| `MNEMONIC` | any | **any** | anyone; the cohort has no authority and no roster |
| `ANCHOR` | GSOC | **one** | the holder of the shared GSOC key — one address, one identity |
| `OWNER` | MIC | **one** | the owner the topic names (`topic = keccak256(owner)`); the id varies |
| `FEED_TOPIC` | feed | **one** | the feed's owner; the id is `keccak256(topic ‖ index)` |
| `SOC_ID` | MOC | **many** | any owner that mines `PO(socAddr(id, owner), anchor) ≥ PO_MIN`; the id is fixed, the owner varies |

Where authorship is explicit and dedup is on the wrapped CAC (`ANCHOR`), the SOC id does no
protocol work: it is **unconstrained**, and publishers MAY use it as a plain sequence number.
The full sequential construction — signed as a feed update, carried as a bare index, making
missed updates detectable and recoverable — is **self-indexed feeds,
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106)**.

The proximity constraint for implicit bindings is a **protocol constant**, not a cohort
parameter: `PO_MIN = 16`. (Making it a parameter invited proto3's unset-equals-0
footgun — an omitted value silently disabling the constraint — and no use case varies
it.)

Broker **capacity is deliberately not a cohort parameter**: a cohort cannot dictate a
remote node's connection count. Each broker enforces its own per-cohort stream limit and
answers `FULL` when it is exhausted — admitting one extra stream for each legitimate
publisher that is absent, so that the audience cannot lock the admin, or a rostered
publisher, out of its own cohort (SWIP-74).

**Cohort lifetime** is broker-side in the same way, with one exception. A cohort is not
tied to whoever joined first, nor to its admin's stream: it ends by **inactivity** — the
broker reclaims a cohort on which no publisher stream has had a message accepted for its
inactivity deadline, and MAY reclaim one with no attached streams at once (SWIP-74,
*Resource bounds*) — which is unobservable beyond a fresh cohort on the next `Join`. The
exception is the **end-of-stream** service message, by which an admin ends its own cohort
deliberately and *attributably* (below), and which is what distinguishes "over" from "the
broker stopped relaying".

### The service feed: the admin's control plane

Everything the admin says about the cohort — that it exists, who may write to it, and that it
is over — travels as SOCs on a feed the admin owns:

```
owner = admin        id = keccak256("bps-service:v1" ‖ topic ‖ index)
```

| index | message | carries |
|---|---|---|
| `n` | **roster** | the full publisher set as of version `n` |
| last | **end-of-stream** | the cohort is closed by its admin |

The feed starts at index 0 with the first roster or the end of stream; a cohort whose
admin has published nothing has an empty service feed, and the admin alone may write.
Each service message carries its own index in the payload, so its id is verifiable
without an out-of-band hint. Three properties follow, and each of them is the point:

- **The spec is nobody's word, and the admin is authenticated.** Every joiner carries the
spec in its `Join`, so a broker cannot serve a peer a cohort it did not name, and a
cohort somebody else pre-creates under a wrong admin is simply a different cohort.
`admin` is a public address; its claim is a signature over a challenge only this broker
could have issued for it, and every message and every roster it publishes carries its
signature. Nothing else in the handshake needs to be trusted, because the roster arrives
the same way — signed by the admin, on a feed whose gaps are visible.

**The publisher role takes the key, every time.** A claim signs a challenge derived from a
broker secret, the cohort and the address, together with the verifier's overlay and the
publisher's cursor. A third party cannot obtain a claim (it travels on the encrypted
stream to the broker and nowhere else); one captured elsewhere recovers to some other
address here (`S` differs per broker, per restart and per cohort, and `O_B` names the
verifier); a challenge forwarded by a relay the publisher was pointed at yields a
signature over the relay's overlay, which the honest broker refuses; a claim for another
address, or with a changed cursor, does not recover to the address it names. What can be
replayed is the identity's own claim, by the node that bridged it, at this broker, until it
restarts — and that node held the identity's stream anyway. SWIP-74's *Security
considerations* has the case-by-case table.

**History is not a break.** A broker or relay that carried a cohort can deliver the admin's
signed updates to a late viewer after a reclaim; those are genuine updates in order, and
the viewer is caught up, not deceived. Freshness is the feed's business — the subscriber's
cursor per `(topic, admin)`, the timestamp key of
[SWIP-65](https://github.com/ethersphere/SWIPs/pull/106) — not the handshake's.

**The transport precondition.** The claim rests on `O_B` being the overlay the publisher's
node is actually connected to, and on the broker knowing the peer it is talking to. A BPS
node MUST verify, in the p2p handshake, that a peer's signed address record names the
connection's authenticated peer ID; a record that is merely self-consistent can be
presented by anyone who has seen it.

**Defence in depth is the real guarantee.** Even a stream that obtains the publisher role
gains nothing by it beyond what its key already signs: every message is validated on
arrival against the SOC signature, its address, and the stream's address (or, for an
implicit cohort, the binding's SOC shape). **Authorship rests on the message signature;
the handshake decides only who is carried as a publisher.**

**Audience control exists in exactly one form, and it is not confidentiality.**
`closed` keeps a joiner outside the roster silent and then disconnects it, and is
enforceable because a claim is signed over a challenge only this broker could have issued
for that address. It bounds *attendance at this broker*, nothing more. **BPS
provides no confidentiality at any layer**: the broker sees every message in plaintext, and so
does everyone it admits. Applications needing a bounded audience **encrypt payloads** — SOC
wrapping is orthogonal to payload encryption, and key distribution is the application's
business. A jam is private because it encrypts, not because it refuses spectators.

**Revocation is announced before it is enforced, and the announcement is what makes
enforcement legitimate.** Between an admin's revocation and the reduced roster reaching
subscribers, the revoked peer cannot know its status has changed: its frames are dropped and
tolerated, with no penalty and no teardown, because it is not misbehaving. Once the roster is
published the peer has been told — on the same feed as everyone else — so publishing after
that is a protocol violation and the connection is broken. A broker that disconnected first
would be punishing a peer for a rule it had not been given; a broker that never publishes the
roster leaves the violation unable to begin at all, which is an ordinary, visible withholding
fault. Announcing first also makes the revocation legible to the rest of the cohort, which
learns *why* a publisher fell silent from an admin-signed message rather than from an
unattributable disconnection.

**Resource bounds are broker policy, and all are required.** A conformant broker bounds
its per-cohort stream count (`FULL`), the number of cohorts it will create and the number
one peer connection may hold (any peer can make it allocate a cohort simply by joining),
and reclaims idle cohorts — SWIP-74's bounds, plus one extra stream per absent publisher
and its claim deadline — and, for the bindings that dedup on chunk address, bounds its
dedup window (see the horizon note above); feed publishers under explicit authorship have
a cursor instead. The bounded dedup window admits replay of an evicted message by an
already-legitimate publisher: a cohort-internal nuisance, not a break of authorship.

## Out of scope (deliberately)

Multihop relaying and referral (bps-multihop), reorganisation policies (SWATCH, SPORE —
policy SWIPs over this protocol's events and actions, no new frames), bandwidth incentives
(bps-bw-incentives), broker discovery (SWIP-59 MEX; early deployments hardcode brokers),
history delivery mechanism (bps-history), implicit-publisher event sourcing
(bps-implicit-publisher), and **confidentiality of any kind** — encrypt payloads, see
Security considerations. Dynamic publisher lists are **no longer out of scope**: grants and
revocations are the service feed's business, and neither changes the cohort.

## Conformance (definition of done)

An implementation is conformant when:

1. a broker enforces SWIP-74's bounds — streams per cohort, cohorts per broker, cohorts
   per peer connection, the inactivity deadline — plus publisher legitimacy, per-binding
   validation and dedup;
2. a subscriber re-verifies every message end-to-end — against the `CohortSpec` it
   joined with and the admin-signed roster it received — and detects (only) liveness
   faults;
3. the **five** configurations above — jam, spectator-jam, live-stream, group-chat and
   implicit — interoperate across independent implementations against the frames in
   [bps.proto](assets/swip-60/bps.proto);
4. a `FULL` refusal is issued at capacity — and nothing else is (no referral);
5. the WS bridge round-trips each worked configuration end to end — join, publish,
   receive — with all signing on the client side (the node holds no publisher keys);
6. the handshake is one `Join` carrying the full spec and the address the stream will
   publish as, creating the cohort or attaching to it, keyed by the spec's canonical
   serialisation; `Ack` is a status and, for a declared address, the challenge; a newly
   attached stream not bound to the admin receives the latest service SOC as its first
   `Message` **(?)**;
7. an absent `admin` is treated as implicit authorship — validated strictly per the
   binding's SOC shape — and a present one authenticated by its claim and by its signature
   on every service message, both of which MUST recover to it;
8. a claim is verified over `keccak256("bps-claim:v1" ‖ S ‖ O_B ‖ index)` with `S`
   derived as SWIP-74 specifies, the signer equal to the declared address, and the address
   the admin's or rostered — under `ALL` there is no claim and every message is checked
   against the declared address; a rostered claim upgrades the stream and sets its cursor,
   no reply is sent; a joiner without a claim is a spectator where the cohort is not
   `closed`, and silent until it claims where it is — the only refusal for identity in the
   protocol; the node verifies in the p2p handshake that a peer's signed address record
   names the connection's authenticated peer ID;
9. an admin grants and revokes by publishing `ROSTER` service messages; a revoked
   publisher's frames are **dropped and tolerated** until the reduced roster is published,
   and its connection is broken only if it publishes **after** that point;
10. a subscriber takes the roster from the admin's service feed, never from the broker, and
    treats an index gap in that feed as a liveness fault.

## Backwards compatibility

New protocol; no existing behaviour changes. This SWIP extends the wire of
[SWIP-74](https://github.com/ethersphere/SWIPs/pull/111) and changes nothing in it: a
SWIP-74 peer at a full broker is a conformant peer of the live-stream configuration, and a
SWIP-74 broker refuses at the handshake every spec that differs from
`{topic, FEED_TOPIC, admin}`. The one thing it cannot refuse there is a feed-topic cohort
whose admin later publishes a roster — the spec is the same — and it serves that as a live
stream: the roster and the grantees' updates are dropped as invalid, so an admin that wants
a roster needs a full broker. bps-multihop adds its control frames as messages of its own,
so it extends without a version bump —
[SWIP-61](https://github.com/ethersphere/SWIPs/pull/105) is to be re-based on the `Message`
frame, a rename of its `Publish`/`Broadcast`, and on the claim, which it forwards
rootward; self-contained frames mean a change of stream model needs no format change
either.

## References

Wire: [bps.proto](assets/swip-60/bps.proto) · base:
[SWIP-74 BPS-lite, PR #111](https://github.com/ethersphere/SWIPs/pull/111) · origin:
[PR #93](https://github.com/ethersphere/SWIPs/pull/93) "Add: pubsub" · broker discovery:
[SWIP-59 MEX, PR #103](https://github.com/ethersphere/SWIPs/pull/103) · implementation:
bee [#5435](https://github.com/ethersphere/bee/pull/5435), bee-js
[#1151](https://github.com/ethersphere/bee-js/pull/1151)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
