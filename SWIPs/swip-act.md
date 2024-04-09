---
SWIP: <to be assigned>
title: Access Control Trie (ACT)
author: András Arányi <andras.aranyi@solarpunk.buzz> (@aranyia)
discussions-to: <URL> should be on> https://swarmresear.ch/?
status: Draft
type: Standards Track
category: Core OR Interface
created: 2024-04-04
---

<!--You can leave these HTML comments in your merged SWIP and delete the visible duplicate text guides, they will not appear and may be helpful to refer to if you edit it again. This is the suggested template for new SWIPs. Note that a SWIP number will be assigned by an editor. When opening a pull request to submit your SWIP, please use an abbreviated title in the filename, `SWIP-draft_title_abbrev.md`. The title should be 44 characters or less.-->

# Access Control Trie (ACT)

## Simple Summary

Within decentralized public data storage systems like Swarm, where data resides across multiple nodes, ensuring
confidentiality, integrity, and availability becomes paramount. The Access Control Trie (ACT) is a data structure that
stores access control information for Swarm nodes. It is used to
determine whether a node has permission to access a particular resource.

## Abstract

The proposal discusses the importance of access control and encryption in a distributed public data storage system like
Swarm. It highlights the inadequacy of server-based access control and the need for encryption to ensure
confidentiality. The proposal describes how encryption works at the chunk level, with the only difference between
accessing private and public data being the presence of a decryption/encryption key.

The proposal also explains the process to obtain the full reference to the encrypted content, which involves root access
and granted access. Root access does not require special privileges, while granted access requires both root access and
access credentials.

For managing access by multiple parties, an additional layer is introduced to obtain the access key from the session
key. This is implemented as an access control trie (ACT) in Swarm manifest format. The paths in the ACT correspond to
the lookup keys and manifest entries containing the ciphertext of the encrypted access keys as metadata attribute
values.

The proposal also discusses the concept of access hierarchy, allowing for a tree-like hierarchy of roles, possibly
reflecting an organisational structure. As long as role changes are “promotions”, i.e., they result in increased
privileges, modifying a single ACT entry for each role change is sufficient.

In summary, the proposal provides a comprehensive overview of how access control and encryption are managed in a
distributed public data storage system. It emphasizes the importance of these mechanisms in ensuring data
confidentiality and managing access rights.

## Motivation

### Confidentiality

In a distributed system confidentiality is an at utmost importance. Traditional server-based access
control is deemed inadequate for ensuring confidentiality. Instead, the system uses encryption to ensure that data
remains accessible only to specific authorized parties. This is especially important in a decentralized architecture
where any node could potentially store data.

### Managing Access

This is a robust and simple API for managing access control. This is traditionally handled through centralized
gatekeeping, which is subject to frequent and disastrous security breaches. In contrast, this system allows users to
manage others’ access to restricted content, such as private shared content and authorization for members to access
specific areas of a web application.

### Selective Access to Multiple Parties

The system provides a mechanism for granting selective access to multiple parties.
This is achieved through an additional layer of encryption on references and a lookup table mapping each grantee’s
lookup key to their encrypted access key. This allows for updating the content without changing access credentials.

### Access Hierarchy

The system supports a tree-like hierarchy of roles, possibly reflecting an organizational structure. This is achieved by
deriving access keys from a root key using a derivation path. This allows for “promotions”, i.e., increased privileges,
with minimal changes to the access control trie (ACT).

### Efficiency and Privacy

The access control scheme offers several desirable properties. Checking and looking up one’s own access is logarithmic
in the size of the ACT. The size of the ACT merely provides an upper bound on the number of grantees, without disclosing
any information beyond this upper bound about the set of grantees to third parties.
These motivations highlight the need for a robust, flexible, and efficient access control system in a distributed public
data storage environment. The system described in the document aims to provide such a solution, ensuring
confidentiality, ease of access management, and privacy.

## Specification

The detailed specification can be studied in the 4.2 section, "Access control"
of [The Book of Swarm](https://www.ethswarm.org/the-book-of-swarm-2.pdf).

## Rationale

The rationale of using Access Control in Swarm is primarily to be able to manage the confidentiality of content and
control access to restricted content in a decentralized network.

In Swarm, nodes share chunks of data with each other and are incentivized to serve them to anyone who requests them.
This makes it impossible for nodes to control access to the data. To maintain confidentiality, the data is encrypted.
Only those with the decryption key can access the data, ensuring it remains accessible only to specific authorized
parties.

Furthermore, access control in Swarm would allow for different levels of privileges for accessing the content by
multiple parties sharing the same root access. This approach allows for updating the content without changing access
credentials. The access control scheme offers several desirable properties such as checking and looking up one's own
access is logarithmic in the size of the Access Control Trie (ACT), and granting access to an additional key requires
extending the ACT by a single entry, which is logarithmic in the size of the ACT.

It will pave the way a tree-like hierarchy of roles, possibly reflecting an organizational structure. As long as role
changes are "promotions", i.e., they result in increased privileges, modifying a single ACT entry for each role change
is sufficient.

## Backwards Compatibility

As ACT is a new feature, it will not affect any existing features, and this was ensured during the implementation and
testing phases. It is designed to be backward compatible with existing Swarm node mechanics.

## Test Cases

### Context

Content is created as a 'channel' or feed, which can be accessed by publishers and viewers. Access Control Trees (ACTs)
can be defined for content, controlling who can view it. Publishers can modify ACTs and the grantee list across multiple
nodes. When a viewer loses access, they are no longer present in the ACT's grantee list.

### Use Cases

1. Publishing New Content Without Additional Grantees
    - 1/a. Reading and Editing an Existing ACT
2. Granting Access to New Viewers
    - 2/a. Adding Additional Viewers to Existing Grantees
    - 2/b. Removing Viewers from Grantee List Without Content Change
    - 2/c. Removing Viewers from Grantee List with Content Update
3. Viewer Requesting Access to Content
4. Viewer Access Revoked Without Content Change
    - 4/a. Viewer Access Revoked with Content Update

Testing will be conducted on the Ethereum Sepolia testnet, utilizing a number of nodes running on the network with
released Bee versions, including some nodes with the ACT feature enabled.

## Implementation

The implementation was broken down to a number of components:

- Dynamic Access Controller
- Grantee Manager
- History
- Access Logic
- Session (Diffie-Hellman moments)

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).