---
SWIP: 16
title: Swarm node implementer spec - 
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-08-02
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

### Data representations

This document uses the `ABNF` convention for defining data types, as
described in the IETF RFC 5234. [1]

#### Primitives

The basic identifiers are defined as follows[2]

| id | def |
| :--- | :---- |
| UINT64MAX | 18446744073709551615 |
| UINT32MAX | 4294967295 |
| UINT16MAX | 65535 |
| UINT8MAX | 255 |
| UINT64 | %d0-UINT64MAX |
| UINT32 | %d0-UINT32MAX |
| UINT16 | %d0-UINT16MAX |
| UINT8 | %d0-UINT8MAX |

| id | def |
| :--- | :---- |
| BOOL | BIT |

| id | def |
| :--- | :---- |
| TIMESTAMP | UINT32 |

#### Network specific types

#### Rule extension for list definitions

The construct `LIST` explicitly defines a list of elements. Elements may
be of any serializable type, and are separated by spaces:

| id | def |
| :--- | :---- |
| LIST | *(*OCTET / TIMESTAMP / UINT8 / UINT16 / UINT32 / UINT64 ) |

This identifier has implications for the serialization of data. Please
refer to the serialization appendices for details and examples of
serializations of the data types throughout this document:
[[rlp]](#rlp)

1.  Network Working Group Augmented BNF for Syntax Specifications: ABN,
    IETF, https://tools.ietf.org/rfc/rfc5234.txt, Retrieved 01.08.2019,

2.  Numeric values are (2^n-1)
