 <div align="center">
<h1 align="center">SWIPs</h1>
<p align="center">
    <a href="https://discord.com/channels/799027393297514537/1239813439136993280">
        <img src="https://img.shields.io/badge/Community%20Channel%20for%20SWIPs-white?logo=discord">
    </a>
</p>
<h3 align="center">Swarm Improvement Proposal repository.</h3>
</div>

<div align="center">
<br />
</div>

<details open="open">
<summary>Table of Contents</summary>

- [About](#about)
- [Contributing](#contributing)
  - [Creating a new SWIP](#creating-a-new-swip)s
  - [Updating a SWIP](#updating-a-swip)
  - [Format and Structure](#format-and-structure)
- [Curating SWIPs](#curating-swips)
  - [SWIP Status Terms](#swip-status-terms)

</details>

# About

Swarm Improvement Proposals (SWIPs) describe standards for the Swarm platform, including core protocol specifications, client APIs, and standards for contracts, interfaces, and utilities.

A browsable version of all current and draft SWIPs can be found on [GitHub](SWIPs).

## Contributing

This README provides a high-level description of the process for contributing a SWIP.

1. Review [SWIP-0](SWIPs/swip-0.md).
2. Fork the repository by clicking "Fork" in the top right.
3. Add your SWIP to your fork of the repository. A template SWIP can be found [here](SWIPs/swip-X.md).
4. Submit a Pull Request (PR) to the Swarm [SWIPs repository](https://github.com/ethersphere/SWIPs/pulls).

A SWIP proposal or suggested edits may come from anyone, both inside and outside the organization, as a pull request to the [SWIP repository](https://github.com/ethersphere/SWIPs). From proposal to acceptance, we use GitHub’s PR review infrastructure to comment on and improve SWIPs.

The repository permissions are structured as follows:

- **Anyone** can open a new PR.
- **Only SWIP editors** can merge a PR to the main branch.

### Creating a New SWIP

A new SWIP can be proposed by opening a [PR](https://github.com/ethersphere/SWIPs/pulls).

#### Preferred Title Format:

`SWIP-<XXXX>: <Title>` where `XXXX` is a unique identifier given by the author, formatted as a four-digit number (e.g., `0001`). Once the PR is ready to be merged as a draft, a SWIP editor will assign the next available number.

The PR should include a placeholder file for the new proposal named `XXXX.md` in the `SWIPs` directory.

This placeholder file must include the following YAML header with these fields:

```yaml
---
title: Neighbourhood hopping
SWIP: XXXX
author: Viktor Tron (@zelig), Viktor Toth (@nugaon)
status: Draft
---
```

- The title must be descriptive yet concise
- SWIP is the SWIP number and must be the same as the filename
- Authors must be specified as a comma-separated list of `real name (@github_handle)`
- The status must be initially set to `Draft`. See below the section on status.

The SWIP editors can merge this initial request to signal the SWIP worthy of recording and ready for discussion.

From this moment on, the SWIP number is taken as allocated and the SWIP will permanently be part of the repo (yes even if it is deferred or rejected).
This way looking at the repo should give the number to be used when a new SWIP proposal is submitted.

Submitters of SWIPs are recommended to use a mnemonic feature branch name.

### Updating a SWIP

A suggested edit to a SWIP can be proposed by opening a PR in the [SWIP repo](https://github.com/ethersphere/SWIPs) with a PR title in the following format: `Update SWIP-XXXX: Title of the suggested change`.

When a PR is already open for the SWIP improvments must be submitted as PRs against this feature branch. Organising reviews to these and merging them is delegated to the submitter (names in the `authors` header).

Once a phase of a SWIPs is complete, authors will indicate this by setting the `ready to merge` label on the open PR. editors can merge the PR to master. see also section about curating SWIPs below.

### Format and structure

SWIPs use [Github flavoured markdown]() as the format. When it comes to structure of the proposal, we are fairly liberal. We recommend that SWIPs have sections:

- yaml header
- abstract
- motivation
- specification
- testing
- roadmap

Assets (diagrams, illustrations, attached logs, etc) should be places under the `SWIPs/assets/XXXX/` subdirectory and referenced from the SWIP file with relative path like `.../assets/XXXX/pic.jpg`

## Curating SWIPs

Only SWIP editors have the right to merge to master. They are supposed to do so after 2 approvals by reviewers and a ready to merge label set by the author. There is no automatic status change as a result of merges.
PRs containing stale, abandoned as well as rejected SWIPs are closed with a comment.
If a SWIP is originally endorsed but later definitely discontinued or rejected, the SWIP editors may choose to remove their entry.

### SWIP Status Terms

Status of the SWIPs can be indicated with github labels.

- **Proposed** - a draft SWIP that has just been created. Indicated by the author with setting a Github label.
- **Endorsed** - a draft SWIP that has been merged to master.
- **Complete** - a SWIP that has been promoted from draft status, has no outstanding PRs and any technical changes that were requested have been addressed by the authors.
- **Rejected** - a SWIP that is not being considered for adoption, implementation or further refinement. Indicated by the editors with setting a Github label on an initial PR unless previously endorsed.
