---
SWIP: <to be assigned>
title: PSS capabilities
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Core
created: 2019-09-21
---

## Abstract

Description of which capability settings that apply in PSS, and how they affect the module's behavior.

## Motivation

The capability settings of PSS need to be documented.

To meet use cases where PSS even can be used as the sole active component of Swarm (even without chunk data), it is important that the operation of PSS is as adaptive and flexible as possible.

## Specification

The PSS `CapabilityID` is set to `1` by convention. **No implementations of Swarm should use this `CapabilityID` for any other purpose.**

The capability array length is set to 8 bits.

PSS capabilities are expressed with combinations of the following flags:

|flag|abbr|bit|description|
|:---|:--|:--|:---|
|send|send|0|new messages may originate from node|
|receive|recv|1|node processed messages that is _may_ be the recipient for|
|(unused)| |2| |
|(unused)| |3| |
|forward| |4|node forwards messages on behalf of the network, _even if_ it may not be the intended recipient|
|partial|part|5|if not set, node will ignore partially addressed messages|
|empty|empt|6|if not set, node will ignore messages with zero-length address|
|(unused)| |7| |

The consequences of the flags settings should both be enforced by the node for its own internal processing, as well as on behalf of peers honoring their wishes for traffic limitations.

### Security considerations

The `send` flag is provided in the event that a private instance of a Swarm network would need to differantiate between nodes that originate traffic or merely just forward.

Identifying a node as a relayer only, is a **privacy risk** as it directly undermines the send obfuscation properties the network provides and clients (may) rely on. Therefore **send flag must always be set in public Swarm networks**. Any peer in a public network with **send** flag set to off **nust be dropped**.


## Backwards Compatibility

To prevent nodes' traffic deferrals being ignored, the PSS protocol version must be incremented. 


## Test Cases

TODO pending discussion and consensus on **Specification** part


## Implementation

Using combinations of these flags it is possible to express relevant use cases for behavior.

|send|recv|fwd|part|empty| |enqueue|handle|forward|
|---|---|---|---|---|---|---|---|---|
| X |   |   | - | - | | explicit send only | - | - |
| X | X |   |(X)|(X)| | explicit send only | end rcpt only [i] | - | 
|   | X |   |(X)|(X)| | - | end rcpt only [i] | - |
|   | X | X |(X)|(X)| | fwd only [i] [ii] | all [i] | all [i] |
|   |   | X |(X)|(X)| | fwd only | - | all [i] | 
| X |   | X |(X)|(X)| | all [i] | - | all [i] | 
| X | X | X |(X)|(X)| | all [i] | all [i] | all [i] |

* notes:
  1. Will only accept partially addressed / empty addressed messages if explicitly set
  2. Send API calls will fail and return error

*TODO: Refer to SWIP for pss specification when it is available*

### Practical implications for internal operations

The flags affect the node's internal behavior as such:

* **send**: Will not originate messages
* **recv**: Will not evaluate registered topic handlers
* **fwd**: Will enqueue messages not originating from node
* **part**: Affects any incoming and outgoing message
* **empty**: Affects any incoming and outgoing message

### Practical implications for peer operations

* **send**: No effect (must always be set in public network)
* **recv**: Send if peer _may_ be recipient
* **fwd**: If _not_ set and message _should_ be forwarded, must continue forwarding to at least one peer with this flag set
* **part**: Do not forward partially addressed messages to peer.
* **empty**: Do not forward messages with empty address to peer.


### Roadmap

Implementation of the capability combinations will be done in two stages:

* send, receive, forward
* part, empty


## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
