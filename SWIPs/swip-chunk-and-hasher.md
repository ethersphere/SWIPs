---
SWIP: <To be assigned>
title: Swarm node implementer spec - Chunk and hasher
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
status: Draft
type: Track Specs
created: 2019-09-14
---

## Abstract

This SWIP is a part of a general specification of a Swarm node. The SWIP system is used for convenience only.

## Motivation

Enable other implementations of the swarm node.

## Specification

Data stored in Swarm consists of `Chunks`.

### Chunk Size

The size of a chunk is the digest size of the `Base Hash` multiplied by
an arbitary exponential of 2. Currently the size is defined as 4096
bytes

### Chunk Reference

The Chunk storage in Swarm is *content addressed*. This means that the
identifier of each individual `Chunk` in the store is a function of the
content itself.

This identifier always contains the address of the `Chunk`. This address
is a `Swarm Overlay Address`, which means that *nodes* and *content*
have comparable identifiers.
[sec:distance-and-proximity](https://github.com/nolash/SWIPs/blob/kademlia-basics/SWIPs/swip-23-kademlia.md#distance-and-proximity).

Retrieval and interpretation of a `Chunk` from the store *may* require
more information than merely its identifier in the store. The entity
encaspulating this information is called the `Chunk Reference`.

In its simplest form, the `Chunk Reference` is the same as the address
of the `Chunk`.

### BMT Hash

The hashing method used to obtain the address of a `Chunk` is called the
`Binary Merkle Tree Hash`, or `BMT Hash` for short.

Building this tree enables cryptographic proofs down to “wordsize” data
units with logarithmic overhead. This “wordsize” is referred to as the
`Segment Size`.

The `Segment Size` is the same as the digest size of the `Base Hash`
used to construct the tree. This means the `Segment Size` is 32 bytes.

Note that one feature aligning data segments with their `BMT Hashes` is
that one single segment may in fact *either* contain verbatim data *or*
an address pointing to a `Chunk`.

#### Calculating the BMT Hash

Obtaining the `BMT Hash` of a `Chunk` involves the following steps:

1.  If the content is shorter than the `Chunk Size` (4096 bytes), it is
    padded with zeros up to `Chunk Size`

2.  Calculate the `Base Hash` of *pairs* of `Segment Size` ((2 * 32))
    units of data and concatenate the results

3.  Repeat previous step on the result until the result is `Segment
    Size` bytes long

4.  Calculate the data size represented by the unpadded data as a 64-bit
    little-endian integer value

5.  Prepend the data size integer to the hash of the data and calculate
    the `Base Hash` of the data

### Swarm Hash

If the size of the data to be hashed is greater than the size of one
`Chunk`, a multi-branched Merkle Tree of `Chunk References` is
constructed to represent it.

The topmost hash of this tree is called the `Swarm Hash`. It is possible
to access all relevant `Chunk References` for a particular *data blob*
that has been added to Swarm through the `Swarm Hash`. [1]

The number of branches the tree contains is calculated from the `Chunk
Size` divided by the `Segment Size`, which currently amounts to 128. A
group of 128 `Chunks` is referred to as a `Batch`.

It follows that one single `Chunk` of `BMT Hashes` may represent up to
128 individual `Chunks`. These in turn, of course, may be a chunk of
hashes referring to more chunks, and so on. The size of data recursively
represented by a `Chunk Reference` is called the `Chunk Span`.

#### Intermediate Chunks

A `Chunk` containing `Chunk References` is referred to as an
`Intermediate Chunk`. When calculating the `BMT Hash` of an
`Intermediate Chunk`, the data size integer used in the last step of the
calculation must be the *actual length* of the data recursively
represented by the `References`.

This table gives an overview of data sizes a `Chunk Span` can represent,
depending on the level of recursion.

| Level    | Span in chunks      | Span in bytes             | (--human) |
| :------- | :------------------ | :------------------------ | :---------- |
| 0 (data) | 1                   | 4,096                     | (4KB)       |
| 1        | 128                 | 524,288                   | (500KB)     |
| 2        | 16,384              | 67,108,864                | (67MB)      |
| 3        | 2,097,152           | 8,589,934,592             | (8.5GB)     |
| 4        | 268,435,456         | 1,099,511,627,776         | (1.1TB)     |
| 5        | 34,359,738,368      | 140,737,488,355,328       | (140TB)     |
| 6        | 4,398,046,511,104   | 18,014,398,509,481,984    | (18PB)      |
| 7        | 562,949,953,421,312 | 2,305,843,009,213,693,952 | (2.3EB)     |

Some Chunk Span data size boundaries

#### Calculating the Swarm Hash

To calculate the Swarm Hash the following method is used:

1.  Determine the `Chunk Reference` of each `Chunk` into an
    *intermediate result* [2]

2.  If the (log_{128}) of the number of `Chunks` minus one is an even
    number, the last `Chunk Reference` should be stored and not included
    in the following step

3.  Otherwise, if the (log_{128}) of the number of `Chunks` is an even
    number, remove the stored `Chunk Reference` and concatenate it to
    the *intermediate result*

4.  If the data size of the `Chunk References` of the `Chunks`
    (including the stored `Chunk Reference` is greater than `Segment
    Size`, group all the `Chunk References` in the *intermediate result*
    and repeat from step 1 with this as the data

Note that the `Swarm Hash` of data up to a single chunk in total size is
identical to its `BMT Hash`.

### Encrypted Chunk References

Currently, the only other defined `Chunk Reference` is used with an
intra-node convenience crypto scheme.

Here all references are double the `Segment Size`. The first `Segment
Size` bytes is a key to decrypt the latter `Segment Size` bytes into an
actual valid address that can be retrieved from the store.

The symmetric key provided by the caller when adding the content is used
as the seed to derive all decryption keys for the `Intermediate Chunks`
[0.4.1](#sec:intermediate-chunks). It is also used as the encryption key
for the `Swarm Hash` [sec:swarm-hash](https://github.com/nolash/SWIPs/blob/hashing/SWIPs/swip-chunk-and-hasher.md#swarmhash).

1.  This is the normal entry point for data retrieval queries. This is
    as close as one gets to the notion of a “file” in Swarm

2.  Remember, use the actual size of represented data

## Backwards Compatibility

N/A

## Test Cases

N/A

## Implementation

N/A

## Copyright

Copyright and related rights waived via CC0

## Specification

