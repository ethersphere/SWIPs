# introduction

## data representations

This document uses the `ABNF` convention for defining data types, as
described in the IETF RFC 5234. 

### primitives

The basic identifiers are defined as follows:

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

### network specific types

### rule extension for list definitions

The construct `LIST` explicitly defines a list of elements. Elements may
be of any type, and are separated by spaces. This identifier has
implications for the RLP encoding of the data, as described in
[3](#protocols).

# fundamentals

## Swarm Overlay Address

Swarm addresses all content and all nodes with 32-byte hashes. A node
address is called its Swarm Overlay Address. It is derived from the
public key of the Ethereum account used to operate the node.

To obtain the Swarm Overlay Address, hash the *uncompressed* form of the
public key, *including* its \(04\) (uncompressed) prefix, using the
KECCAK256 hashing algorithm.   

Formally we define the Swarm Overlay Address thus:

    OVERLAYADDRESS = 32*(%x00-ff)

## Swarm Address Pair

To enable peers to locate the a node on the network, the aforementioned
Swarm Overlay Address is paired with an Underlay Address. The Underlay
Address is a string representation of the node’s network location on the
underlying transport layer.

Currently the url string representation of the devp2p V4 Enode ID is
used for this value. Although this value currently serves no practical
purpose within the operations of the Swarm node, the handshake *MUST*
fail if the string cannot be parsed as a valid Enode ID. 

We here add the following definitions:

    ENODEPREFIX = "enode://"
    PUBLICKEYHEX = "04" 64HEXDIG
    HOST = IP / FQDN
    UNDERLAYADDRESS = ENODEPREFIX PUBLICKEYHEX "@" HOST ":" PORT
    ADDRESSPAIR=2#2list(OVERLAYADDRESS UNDERLAYADDRESS)

# protocols

Swarm protocols require a p2p transport protocol.

At the time of writing, the Swarm reference implementation depends on
the devp2p protocol, including its RLPX wire format and encryption
scheme.  Detailing the concepts of `devp2p` and `RLP(X)` as such is out
of scope of this document.

Data payloads will be defined in ABNF format. Reference examples to
verify the correct `RLP` encoded form of the data will also be included.

We define the following mappings from ABNF data type definitions to RLP
data types:

  - BOOL  
    is encoded as an RLP encoded integer with length of one byte

  - OCTET  
    is encoded as an RLP encoded integer with length of one byte

  - TIMESTAMP  
    is encoded as an RLP encoded variable length integer

  - %x\#\#  
    hexadecimal literals are encoded as encoded integers with length of
    one byte, corresponding to its hexadecimal (not its string) value

  - LIST  
    as defined in [1.1.3](#abnf-list-definition) will be RLP encoded as
    RLP lists.

All other data is encoded as RLP lists.

The outermost element of a serialization is always a LIST item \[1\]

## example

A message structure with only one field of `3OCTET` data will in
*reality* be `LIST(3OCTET)`. If the data is `0x666f6f` it will serialize
to `0xc4 83 66 6f 6f`, which breaks down to:

    LIST:   0xc4 (list, 4 bytes long)
    3OCTET: 0x83 (string, 3 bytes long)
    data:   0x66 0x6f 0x6f

1.  This is due to the fact that the reference implementation is written
    in golang, and the default RLP deserialization of golang structs
    treats the struct itself as a list.
