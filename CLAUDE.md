# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the **Swarm Improvement Proposals (SWIPs)** repository — a collection of design documents for the Swarm decentralized storage platform. There is no build system, tests, or application code. The repo contains only Markdown proposal documents and associated assets.

## Repository Structure

- `SWIPs/` — All accepted/endorsed SWIP documents live here as `swip-<number>.md`
- `SWIPs/assets/SWIP-X/` — Diagrams and auxiliary files for SWIP X
- `SWIPs/swip-X.md` — Template for new SWIPs
- `SWIPs/swip-0.md` — Meta SWIP defining the process and guidelines

## SWIP Document Format

Every SWIP file must start with a YAML front matter header:

```yaml
---
SWIP: <number>
title: <title, max 44 chars>
author: FirstName LastName (@GitHubHandle)
status: Draft | Last Call | Accepted | Final | Active | Abandoned | Deferred | Rejected | Superseded
type: Standards Track (Core, Networking, Interface) | Meta | Informational
created: yyyy-mm-dd
---
```

## SWIP Structure

Standard sections in order: Simple Summary, Abstract, Motivation, Specification, Rationale, Backwards Compatibility, Test Cases, Implementation, Copyright (CC0 waiver).

## Contribution Workflow

- New SWIPs: fork, add file in `SWIPs/` directory, submit PR titled `SWIP-<XXXX>: <Title>`
- Updates to existing SWIPs: PR titled `Update SWIP-XXXX: <change description>`
- Assets go in `SWIPs/assets/SWIP-XXXX/` and are referenced with relative paths
- Only SWIP editors can merge to master; merges require 2 reviewer approvals and a `ready to merge` label
- Status lifecycle: WIP → Draft → Last Call → Accepted (core only) → Final

## Git Setup

- **Origin:** `crtahlin/SWIPs` (fork) — `git@github.com:crtahlin/SWIPs.git`
- **Upstream:** `ethersphere/SWIPs` (no remote configured; add with `git remote add upstream https://github.com/ethersphere/SWIPs.git` if needed)
- **Main branch:** `master`
- **Active feature branches:** `swip-responsible-nbhood-split`, `swip-data-provenance`, `swip-increase-reserve`, `add-editor`, `crtahlin-swip-X-text`

## Key Conventions

- Filenames use lowercase: `swip-<number>.md` or `swip-<descriptive_name>.md`
- Use GitHub-flavored Markdown
- SWIP numbers are assigned by editors (usually the PR/issue number)
- PRs target `ethersphere/SWIPs` upstream
