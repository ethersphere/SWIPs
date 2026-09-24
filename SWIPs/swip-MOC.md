---
SWIP: 42
title: MOC - Mined Owner Chunk - for efficient notifications
author: Bálint Újvári <@bosi95>, Viktor Tron <@zelig>   
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
status: Draft
type: <Standards Track (Core)>
created: 2025-11-04
---

# Mined Owner Chunks 

## Abstract

Mined Owner Chunks are Single Owner Chunks (SOC) with a fixed part (ID or owner) and an ephemeral part
(owner or ID) mined so that the SOC address falls into a particular target neighbouhood. This SwIP 
introduces the concept as a vehicle for robust _notifications_. The properqooo  e  ooogg g vejggggqe

## Motivation

A major deficiency of the current Swarm architecture is that already explored communication modalities that could in principle serve as notifications, have their respective drawbacks either in terms of their excessive resource needs, or lacking service guarantees:

- outbox feeds:
  - require constant polling, so they also both process- and bandwidth-inefficient
 (depending on the the polling period mainly)
- PSS, which is the trojan chunk allowing zero-leak comms:
  - requires real-time mining by the sender, per message
  - therefore it is slow and CPU inefficient (exponential in the target depth).
  - while inheretly imcentivised as well as async, 
- gSOCs are both difficult to interpret and at the same time, 
  - require recipient in the same address
  - attaches multiple nessages to the same SOC
  - address is fully specified
  - and node must be closest node to be pushed
  - therefore both leaks the identity as well as attackable
  - impossible to retrieve outside the neighbourhood

## Specification

### Concepts

- Target neighbourhood: indentified by an overlay prefix specified similar to nonce mining.
- Target neighbourhood overlay prefix: 
- Mined owner:
- Mined ID: 

### Variants 

#### Mined ID Chunk (MICs)

#### Mined Owner Chunks (MOCs)

### API

The notification service API needs to provide send API endpoint as well as a receive API endpoint which allows setting up websocket push notifications for input parameters.

#### Sender API

#### Receiver API

### Identity management

## Rationale

The rationale behind this n

### Premineble

No sending delay because the address can be premined 

### Content neutral

the same address can be associated with arbitrary content

### Encryption

like pss envelope using the mined address as the ephemeral one in el-gamal.

### Async deliverability

As MOC address is preminable, even same sender multiple messages can be distinct chunks
which automatically synchronise with pull-sync. 

#### Undermining attack 

Due to pull-sync syncing, if it is switched on, no chunk is missed by the recipient.
This is in contrast the earlier concept of GSOCs with no pull-syncing support 
needs to rely on push syncing for delivery. Since push syncing can only guarantee 
the delivery to the node closest to the address, adversaries can just mine an overlay 
that is even closer to the full gsoc address than the intended recipient; in case the delivery path of a GSOC chunk
does not touch the recipient, is able to deny and withhold the chunk.

#### non local recipient 
if the target overlay prefix published by the recipient is $d$-bit long 
($d>=D_s$, greater than the storage depth),  then every MOC message falls into 
the neighbourhood designated by target overlay (prefix). 
But if the overlay prefix ($PO(addr(MOC),oprx_R$)
matches the recipient address only $m$-bits ($m<d$), then 

1. $D_s<=m<d$ -- in this case the recipient is in the same neighbourhood, or 
1. $m<D_s$ -- recipient is not even in the same neighbourhood as the overlay prefix

The recipient can afford syncronising only the PO bins $d'>=d$ of any of the full nodes in the appropriate target NH
the neighbourhood. 

If no historical messages are expected, then pull live syncing is sufficient.

#### Syncing past messages

Since MOCs are just SOCs, receiver can receive past messages via historical pull-syncing.

#### Privacy
Importantly, this allows any neighbourhood to serve as a proxy while  recipients to be located basically anywhere in the network and still efficiently get the nessages delivered to them in their PO bin $m$. From the proxy nodes' perspective,  if $m<<D_s$, then the  fact that a node external to their neighbourhood syncs part of their reserve can easily reveal them as the recipient (even though this information is private to the parties and also deniable by $R$).

## Implementatiom notes

### bee

On the bee API level though, a simple chunk or file send will work. 
On the bee level, just a call hook is to be implemented which is installed either on the fixed ID or fixed overlays

### js tooling

### identity management

## Backard compatibility

## testing

## Copyright


