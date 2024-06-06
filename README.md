# SWIPs
Swarm Improvement Proposals (SWIPs) describe standards for the Swarm platform, including core protocol 
specifications, client APIs, and contract, interface and utility standards.

A browsable version of all current and draft SWIPs can be found on [GitHub](SWIPs).
<!-- TODO: This must be Swarm site eventually -->

## Contributing

This README contains a high level description of contributing a SWIP, for convenience.

 1. Review [SWIP-0](SWIPs/swip-0.md).
 2. Fork the repository by clicking "Fork" in the top right.
 3. Add your SWIP to your fork of the repository. There is a [template SWIP here](SWIPs/swip-X.md).
 4. Submit a Pull Request to Swarm's [SWIPs repository](https://github.com/ethersphere/SWIPs).

A SWIP proposal or suggested edits (or updates) may come from anyone (inside or outside the organisation) and are received in the form of a pull request to the [SWIP repository](https://github.com/ethersphere/SWIPs). Throughout the lifetime of a SWIP from proposal to final accepted, we use the PR-review infrastructure of github to comment and improve the SWIP.

THe github permissions of the repo reflect these privileges:
- Anyone can open a new PR.
- Only SWIP editors can merge a PR to master.

### Creating a new SWIP

A new SWIP can be proposed by opening a PR in the [SWIP repo](https://github.com/ethersphere/SWIPs) titled `SWIP-<XXXX>: <title>` where `XXXX` is the SWIP number left padded with zeros up to four digits (i.e., fprinted with the format string `%04d`). 
The PR is adding at least a new placeholder file for the new proposal named `XXXX.md` to be located in the `SWIPs` subdirectory of the SWIPs repo.

This placeholder file contains minimally only the the yaml header with the following fields:

```yaml
 ---
title: fairx
SWIP: XXXX
author: Viktor Tron (@zelig), Viktor Toth (@nugaon)
status: Draft
---
```

- The title must be descriptive yet concise
- SWIP is the SWIP number and must be the same as the filename
- Authors must be specified as a comma-separated list of `real name (@github_handle)`
- The status must be initially set to `Draft`. see below the section on status.

The SWIP editors can merge this initial request to signal the SWIP worthy of recording and ready for discussion.

From this moment on, the SWIP number is taken as allocated and the SWIP will permanently be part of the repo (yes even if it is deferred or rejected).
This way looking at the repo should give the number to be used when  a new SWIP proposal is submitted. 

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

* **Proposed** - a draft SWIP that has just been  created. Indicated by the author with setting a Github label.
* **Endorsed** - a draft SWIP that has been merged to master.
* **Complete** - a SWIP that has been promoted from draft status,  has no outstanding PRs and any technical changes that were requested have been addressed by the authors
* **Rejected** - a SWIP that is not being considered for adoption, implementation or further refinement. Indicated by the editors with setting a Github label  on an initial PR unless previously endorsed.



