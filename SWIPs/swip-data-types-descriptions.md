---
SWIP: <to be assigned>
title: Type definitions for protocol messages
author: Louis Holbrook @nolash <dev@holbrook.no>
status: Draft
type: General
created: 2019-08-02
---

## Abstract

This SWIP defines pseudo data types for use in Swarm protocol specifications, and their serialization to RLP.

## Motivation

To describe protocols in our specifications, we are in need of a strongly defined way of describing data types and their serializations to RLP. RLP is the relevant format in this case, as it is the serialization format currently being used in devp2p, and Swarm is currently based on devp2p.

RLP does not have "types" as such, just self-describing data units whose length is serially interpreted. Hence it is for example not possible to define a number value range merely in terms of RLP constructs.

## Specification

This document uses the `ABNF` convention for defining data types, as
described in the IETF RFC 5234. [@IETF:ABNF]

### primitives

The basic identifiers are defined as follows:

``` {numbers="none"}
UINT64MAX   = 18446744073709551615
UINT32MAX   = 4294967295
UINT16MAX   = 65535
UINT8MAX    = 255
UINT64      = %d0-UINT64MAX
UINT32      = %d0-UINT32MAX
UINT16      = %d0-UINT16MAX
UINT8       = %d0-UINT8MAX

BOOL        = BIT

TIMESTAMP   = UINT32
```

### rule extension for list definitions {#abnf-list-definition}

The construct `LIST` explicitly defines a list of elements. Elements may
be of any type, and are separated by spaces. This identifier has
implications for the RLP encoding of the data, as described in [3].

### general types

We define the following mappings from ABNF data type definitions to RLP
data types:

|type|description|
|:---|:---|
|BOOL|is encoded as an RLP encoded integer with length of one byte|
|OCTET|is encoded as an RLP encoded integer with length of one byte|
|TIMESTAMP|is encoded as an RLP encoded variable length integer|
|\%x\#\#|hexadecimal literals are encoded as encoded integers with length of one byte, corresponding to its hexadecimal (not its string) value|
|LIST|as defined in [1.1.3] will be RLP encoded as RLP lists|

All other data is encoded as RLP lists.

The outermost element of a serialization is always a LIST item [^1]

### example

A message structure with only one field of `3OCTET` data will in
*reality* be `LIST(3OCTET)`. If the data is `0x666f6f` it will serialize
to `0xc4 83 66 6f 6f`, which breaks down to:

```
LIST:   0xc4 (list, 4 bytes long)
3OCTET: 0x83 (string, 3 bytes long)
data:   0x66 0x6f 0x6f
```

## Backwards Compatibility

There are no compatibility issues.

## Test Cases

There are no relevant test cases.

## Implementation

Any future SWIP defining Swarm protocols.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
