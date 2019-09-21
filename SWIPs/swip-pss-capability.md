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

|flag|bit|description|
|:---|:--|:---|
|send|0|new messages may originate from node|
|receive|1|node processed messages that is _may_ be the recipient for|
|(unused)|2| |
|(unused)|3| |
|forward|4|node forwards messages on behalf of the network, _even if_ it may not be the intended recipient|
|partial|5|if not set, node will ignore partially addressed messages|
|empty|6|if not set, node will ignore messages with zero-length address|
|(unused)|7| |



## Backwards Compatibility

To prevent nodes' traffic deferrals being ignored, the PSS protocol version must be incremented. 


## Test Cases

TODO pending discussion and consensus on **Specification** part


## Implementation

Using combinations of these flags it is possible to express relevant use cases for behavior:

|send|recv|fwd|part|empty| |enqueue|handle|forward|
|---|---|---|---|---|---|---|---|---|
| X |   |   | - | - | | explicit send only | - | - |
| X | X |   |(X)|(X)| | explicit send only | end rcpt only [i] | - | 
|   | X |   |(X)|(X)| | - | end rcpt only [i] | - |
|   | X | X |(X)|(X)| | fwd only [i] [ii] | all [i] | all [i] |
|   |   | X |(X)|(X)| | fwd only | - | all[i] | 
| X |   | X |(X)|(X)| | all[i] | - | all[i] | 
| X | X | X |(X)|(X)| | explicit send only | all [i] | all [i] |

* notes:
  1. Will only accept partially addressed / empty addressed messages if explicitly set
  2. Send API calls will fail and return error

### Roadmap

Implementation will be done in two stages, where in the _first_ stage the partial and empty address modifiers will be inactive.


## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
