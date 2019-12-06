---
SWIP: <To be assigned>
title: Swarm node implementer spec - 
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-10-16
---

## Abstract

This SWIP is a part of a general specification of a Swarm node. The SWIP system is used for convenience only.

## Motivation

Enable other implementations of the swarm node.

## Backwards Compatibility

N/A

## Test Cases

N/A

## Implementation

N/A

## Copyright

Copyright and related rights waived via CC0

## Specification

### Base Hash

Swarm uses `KECCAK` with the `SHA3_256` parameter preset as its `Base
Hash` algorithm. `KECCAK256` has a digest size of 32 bytes.
