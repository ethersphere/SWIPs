bzz
===

The bzz protocol consists of a single message type; handshake.

The bzz handshake is the first message to be exchanged between peers
after the p2p transport protocol has been successfully negotiated. After
the handshake each peer should remember the following data about the
other:

-   Swarm Overlay Address of the peer

-   Whether the peer is a *light* or *full* node

message
-------

The handshake message consists of four data fields:

``` {numbers="none"}
version     = UINT64
Network ID  = UINT64
Address data    = ADDRESSPAIR
Light Node      = BOOL
```

The `AddressPair` consists of two strings, RLP-encoded as a single
string in two parts.

The first part is the 32 byte Swarm Overlay Address.

The second part is data of arbitrary length, and is meant to represent
the identity of the node on the p2p protocol transport layer.

protocol
--------

Upon connection, the *peer who initiated the connection* sends a
handshake message to the other. If a more than one handshake is received
from the same peer, the connection *MUST* be dropped.

The peers *MUST* have the same `Version` and `Network ID`. If one or
both of the fields don't match, the connection *MUST* be dropped.

The `Light Node` field is a boolean value, indicating whether the node
is operating as a Light Node or not.

example
-------

Consider a handshake message with the following arbitary values:

``` {numbers="none"}
Version               42
Network ID            622
Address Data pt. 1    134c2fdea53719022366b383bae4ae2e23f74d734a4f40170970b2910da851ee     
Address Data pr. 2    enode://0459783d8f54b3e684d2a6928e4d94a0c32570eb14fbecac9d07955c0a91e
                      b3b5edce5ef23cff94250fb5591456d2d3f576315db146421d5e885675978fa59dff5
Lightnode             1
```

The RLP encoding of this message will be:

``` {numbers="none"}
00000000  f8 b4 2a 82 02 6e f8 ad  a0 13 4c 2f de a5 37 19  |..*..n....L/..7.|
00000010  02 23 66 b3 83 ba e4 ae  2e 23 f7 4d 73 4a 4f 40  |.#f......#.MsJO@|
00000020  17 09 70 b2 91 0d a8 51  ee b8 8a 65 6e 6f 64 65  |..p....Q...enode|
00000030  3a 2f 2f 30 34 35 39 37  38 33 64 38 66 35 34 62  |://0459783d8f54b|
00000040  33 65 36 38 34 64 32 61  36 39 32 38 65 34 64 39  |3e684d2a6928e4d9|
00000050  34 61 30 63 33 32 35 37  30 65 62 31 34 66 62 65  |4a0c32570eb14fbe|
00000060  63 61 63 39 64 30 37 39  35 35 63 30 61 39 31 65  |cac9d07955c0a91e|
00000070  62 33 62 35 65 64 63 65  35 65 66 32 33 63 66 66  |b3b5edce5ef23cff|
00000080  39 34 32 35 30 66 62 35  35 39 31 34 35 36 64 32  |94250fb5591456d2|
00000090  64 33 66 35 37 36 33 31  35 64 62 31 34 36 34 32  |d3f576315db14642|
000000a0  31 64 35 65 38 38 35 36  37 35 39 37 38 66 61 35  |1d5e885675978fa5|
000000b0  39 64 66 66 35 01                                 |9dff5.|
000000b6
```
