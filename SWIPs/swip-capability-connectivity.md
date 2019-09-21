NSWIP: <to be assigned>
title: Use Capability to request connectivity
author: Louis Holbrook <dev@holbrook.no> (https://holbrook.no)
discussions-to: <URL>
status: Draft
type: Networking, Interface
created: 2019-09-21
---


## Abstract

Depending on the capability settings at any given moment, each module in Swarm may have different connectivity requirements.

Since the actual interpretation of capabilities is confined to each module and opaque between modules, the connectivity driver cannot and should not be able to decide which type of connectivity particular capability settings require.

This proposal adds a method for modules to signal what connectivity they require to operate.


## Motivation

To make it possible to determine and maintain a minimum of required connectivity.

This proposal does not change the Swarm protocol.


## Specification

*TODO: Should refer to SWIP as part of node implemnter specification for connectivity cases when it is available*

Connectivity configurations for Swarm can be broken down in three concrete cases:

* **Dispatcher** - `n` peers in a far bin providing broad access
  - Send message
  - Retrieve chunk
* **Receiver** - `n` peers in neighborhood providing routing endpoint
  - Receive message
* **Saturation** - `n` peers in every bin
  - Pull syncing

In cases where the node is a consumer node and/or resources are severely constrained, it should be possible to provide an adaptive mode of operation that overrides the default peer cardinality requirements. This can be achieved by adding a flag to request a "minimal" configuration.

Thus, all relevant connectivity cases can be summarized in a table, where:

* `f` is the saturation threshold of the far bin
* `n` is the neighborhood threshold
* `i` is the saturation threshold of intermediate bins.

|far bit|nbh bit|min bit| | far peers | nbh peers | bin peers | 
|---|---|---|---|---|---|---|
| X |   |   | | `f` | 0 | 0 |
| X |   | X | |  `1` | 0 | 0 |
|   | X |   | |  0 | `n` | 0 | 
|   | X | X | |  0 | `1` | 0 | 
| X | X |   | |  `f` | `n` | `b` |
| X | X | X | | `1` | `1` | 0 |


## Backwards Compatibility

There are no compatibility issues


## Test Cases

* Connectivity correctness test for all cases and cardinalities in **Specification** above.
* `Capabilities` holds the minimal sum of 3 different capabilities representing all cases


## Implementation

The three bits outlined in the **Specification** can be introduced to each individual `Capability` in the `Capabilities` array. They can be encapsulated as a new object tentatively named `CapabilityConnectivity`:

```
CapabilityConnectivity {
	far	bool
	near	bool
	min	bool
}
```

The Capability struct then becomes:

```
Capability {
	Id	uint64
	Cap	[]bool
	connect CapabilityConnectivity
}
```

Since individual `Capability` settings are registered and modified through the encapsulating `Capabilities` object, it is possble for this component to digest the at any time required minimum of connectivity (the `OR` of all `CapabilityConnectivity` settings in all `Capability` objects). 

The result can be represented by the same struct. `Capabilities` then become:

```
Capabilites {
	Caps	[]Capability
	connect CapabilityConnectivity
}
```

### Serialization

A node can use the `depth` parameter of the `discovery` protocol to control the radius of peers suggested to it. Therefore, this connectivity request information can remain node-internal and does not need to be transmitted to peers.


### Cross-platform considerations

Although the **Code Implementation** above is described in a `golang` flavor, the `CapabilityConnectivity` struct is in reality just three bits, and can easily be replaced by `OR`ed constants.



## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
