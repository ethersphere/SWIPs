---
SWIP: <to be assigned>
title: Swarm-Based Data Provenance Framework
author: Črt Ahlin (@crtahlin)
discussions-to: https://discord.com/channels/799027393297514537/1239813439136993280
status: Draft
type: Informational
created: 2025-03-13
updated: 2026-01-14
---

## Simple Summary

This SWIP proposes Swarm as a decentralized storage layer for provenance metadata and data. Provenance, the documented history of a dataset's origin and transformations, is increasingly important for regulatory compliance, ethical AI, and data accountability. The framework provides:

- **CLI Toolkit**: Command-line utilities for uploading, downloading, and managing provenance files with Swarm reference hashes
- **Gateway Service**: RESTful API layer for simplified Swarm access without local node requirements
- **MCP Server**: Model Context Protocol integration enabling AI agents to interact with Swarm provenance storage

The framework does not enforce specific provenance standards but ensures compatibility by decoupling metadata (structured JSON) from the actual provenance data (stored as arbitrary files). Developers and enterprises retain full control over their data format and privacy measures.

## Abstract

Provenance systems require immutable, scalable storage to track data lineage effectively. This SWIP leverages Swarm's decentralized network to:

- **Store Provenance Data**: Users upload files in any format (e.g., W3C PROV-JSONLD, DaTA spec, or custom schemas)
- **Manage Metadata**: A JSON wrapper includes:
  - `content_hash` (SHA-256 for matching provenance data across different systems)
  - `provenance_standard` (optional field for self-declared standards)
  - `data` (Base64-encoded provenance data)
  - `stamp_id` (for TTL tracking and renewal)
- **Ensure Flexibility**: No Swarm-level validation of provenance formats—compatibility is achieved by design

A prototype toolkit (developed under the DataFund Fellowship) provides multiple access patterns: command-line interface for developers, REST API gateway for application integration, and MCP server for AI agent workflows. Privacy and encryption remain optional, allowing users to comply with regulations like GDPR independently.

## Motivation

Data provenance is critical for ethical AI development, regulatory compliance, and ensuring trust in data-driven systems. Existing provenance solutions often face challenges in terms of vendor lock-in, scalability, and privacy. Centralized systems create dependencies and potential single points of failure. Public blockchains, while immutable, can be costly for large-scale data storage and may not adequately address privacy concerns.

Swarm offers a compelling alternative by acting as a trustless, decentralized storage network:

- **Trusted 3rd Party**: Swarm's decentralized architecture serves as a neutral platform for recording provenance, eliminating single points of control.
- **Cost Considerations**: While centralized cloud storage may offer lower costs for simple storage, Swarm provides a more cost-competitive option compared to blockchain-based solutions.
- **Interoperability**: The toolkit is designed to accommodate various provenance standards (e.g., DaTA, W3C PROV) without enforcing a specific format, allowing users to adopt the standard that best suits their needs.

This proposal aims to align with the Data Spaces Support Centre blueprint for a Technical Building Block covering Provenance & Traceability. By enabling easy uploading, downloading, and management of provenance files, the toolkit empowers users to meet emerging regulatory requirements, such as those outlined in the EU AI Act, and to establish trust and accountability in data-driven systems.

### AI Agent Integration Rationale

The emergence of Large Language Models (LLMs) and AI agents as primary interfaces for data operations necessitates native integration points. The Model Context Protocol (MCP), introduced by Anthropic in late 2024, has rapidly gained adoption as a standard for tool integration with AI systems. Providing an MCP server enables:

- **Autonomous Provenance Management**: AI agents can independently record provenance for data they process or generate
- **Workflow Integration**: Provenance recording becomes part of existing AI-assisted workflows without manual intervention
- **Ecosystem Compatibility**: Integration with Claude, GPT-based systems, and other MCP-compatible AI frameworks

This addition reflects market evolution toward agentic AI systems requiring programmatic access to decentralized infrastructure.

## Specification

### 1. Provenance Record Structure

The provenance record is stored as a single JSON file containing both metadata and the actual provenance data:

```json
{
  "content_hash": "sha256:9f86d...a9e",
  "provenance_standard": "DaTA v1.0.0",
  "encryption": "none",
  "data": "<base64-encoded-content>",
  "stamp_id": "0xfe2f...c3a1"
}
```

**Key Fields**:
- `content_hash`: SHA-256 hash of the raw provenance data (before Base64 encoding) for integrity verification
- `provenance_standard`: Declares the standard used (e.g., DaTA, W3C PROV, or custom)
- `encryption`: Optional field to indicate encryption method (default: `"none"`)
- `data`: Base64-encoded provenance data (actual content in any format)
- `stamp_id`: Swarm postage stamp identifier used for TTL management

This structure ensures self-contained provenance records while maintaining compatibility with any standard. The `data` field can store provenance information in formats like JSON, XML, or binary.

### 2. Architecture

The framework consists of three components in a layered architecture. The Gateway Service is the central component that connects to Swarm, while the CLI Toolkit and MCP Server are clients that communicate through the Gateway:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              CLIENT LAYER                                   │
│  ┌───────────────────────────────┐    ┌───────────────────────────────────┐ │
│  │        CLI Toolkit            │    │     MCP Server (AI Agents)        │ │
│  │                               │    │                                   │ │
│  │  swarm-prov-upload            │    │  Model Context Protocol           │ │
│  │  (command-line interface)     │    │  tool handlers for LLMs           │ │
│  └───────────────┬───────────────┘    └─────────────────┬─────────────────┘ │
└──────────────────┼──────────────────────────────────────┼───────────────────┘
                   │              HTTP/REST               │
                   └──────────────────┬───────────────────┘
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           GATEWAY LAYER                                     │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                    Gateway Service (REST API)                       │    │
│  │                                                                     │    │
│  │  FastAPI application providing:                                     │    │
│  │  • /api/v1/stamps/* - Stamp management                              │    │
│  │  • /api/v1/data/* - Data upload/download                            │    │
│  │  • /api/v1/wallet - Wallet information                              │    │
│  │  • Duration-based stamps, size presets, utilization tracking        │    │
│  └──────────────────────────────────┬──────────────────────────────────┘    │
└─────────────────────────────────────┼───────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SWARM NETWORK LAYER                               │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                         Bee Node                                    │    │
│  │  • /bzz endpoint (data upload/download)                             │    │
│  │  • /stamps endpoint (postage stamp management)                      │    │
│  │  • /batches endpoint (batch information)                            │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Note**: The CLI Toolkit also supports a `--backend local` mode for direct Bee node communication, bypassing the Gateway. This is intended for development and self-hosted deployments.

#### 2.1 CLI Toolkit

Python command-line interface providing access to provenance operations. By default, the CLI communicates with Swarm through the Gateway Service:

**Commands**:
- `upload`: Upload provenance data to Swarm with metadata wrapping
- `download`: Retrieve and verify provenance data
- `stamps list`: List available postage stamps
- `stamps info <id>`: Get stamp details including TTL
- `stamps extend <id>`: Extend stamp validity
- `health`: Check backend connectivity
- `wallet`: Display wallet information (gateway mode)
- `chequebook`: Display chequebook balance (gateway mode)

**Backend Modes**:
- `--backend gateway` (default): Uses hosted gateway service, no local node required
- `--backend local`: Direct communication with local Bee node

**Stamp Configuration**:
- `--duration <hours>`: Specify stamp validity in hours (minimum 24)
- `--size <preset>`: Use size preset (small, medium, large)
- `--stamp-id <id>`: Use existing stamp (skip purchase)

#### 2.2 Gateway Service

FastAPI-based REST API providing HTTP access to Swarm functionality:

**Stamp Management Endpoints**:
- `POST /api/v1/stamps/`: Purchase new stamp with duration or size preset
- `GET /api/v1/stamps/`: List all stamps with utilization data
- `GET /api/v1/stamps/{id}`: Get stamp details
- `GET /api/v1/stamps/{id}/check`: Health check for upload readiness
- `PATCH /api/v1/stamps/{id}/extend`: Extend stamp validity

**Data Operation Endpoints**:
- `POST /api/v1/data/?stamp_id={id}`: Upload single file
- `POST /api/v1/data/manifest?stamp_id={id}`: Upload TAR archive as collection
- `GET /api/v1/data/{reference}`: Download raw data
- `GET /api/v1/data/{reference}/json`: Download with metadata wrapper

**Wallet Endpoints**:
- `GET /api/v1/wallet`: Wallet address and BZZ balance
- `GET /api/v1/chequebook`: Chequebook address and available balance

**Advanced Features**:
- Duration-based stamp purchasing (hours instead of raw PLUR amounts)
- Size presets for simplified capacity planning
- Stamp utilization tracking with warning thresholds
- Deferred upload mode for asynchronous network sync
- Configurable erasure coding (redundancy levels 0-4)
- W3C Server-Timing headers for performance profiling

#### 2.3 MCP Server

Model Context Protocol server enabling AI agent integration. The MCP Server communicates with Swarm exclusively through the Gateway Service:

**Available Tools**:
- `purchase_stamp`: Create new postage stamp
- `get_stamp_status`: Retrieve stamp information
- `list_stamps`: List all available stamps
- `extend_stamp`: Add funds to existing stamp
- `upload_data`: Upload data to Swarm
- `download_data`: Download data by reference
- `health_check`: Check gateway connectivity

**Configuration**:
- `SWARM_GATEWAY_URL`: Gateway endpoint (default: public gateway)
- `DEFAULT_STAMP_AMOUNT`: Default stamp amount in wei
- `DEFAULT_STAMP_DEPTH`: Default stamp depth

**Integration Points**:
- Claude Desktop via `claude_desktop_config.json`
- Any MCP-compatible AI framework
- Custom agent implementations

### 3. CLI Toolkit Features

The CLI Toolkit provides the core provenance operations. The MCP Server exposes a subset of these operations to AI agents.

#### 3.1 Upload Workflow

1. User prepares provenance data in any format (e.g., DaTA spec, W3C PROV)
2. CLI generates SHA-256 hash of raw data, encodes it to Base64
3. CLI wraps data into JSON metadata structure
4. If no existing stamp provided:
   - Calculate required stamp size based on JSON file size
   - Purchase stamp with user-specified duration or default (25 hours)
   - Wait for stamp propagation (30-90 seconds)
5. Upload JSON file to Swarm via Gateway
6. Return Swarm reference hash (64-character hex string)

*Note: Acquiring funds (e.g., xBZZ for stamp purchase) is out of scope for this toolkit.*

#### 3.2 Download Workflow

1. CLI fetches JSON from Swarm using reference hash
2. Parse and validate JSON structure
3. Decode Base64 `data` field
4. Verify integrity via SHA-256 `content_hash` comparison
5. Save original data and metadata to output directory

#### 3.3 Stamp Management

- **Check TTL**: Query remaining storage validity using stamp_id
- **Top-Up**: Extend storage validity by adding funds to existing stamp
- **Utilization Monitoring**: Track stamp usage percentage (0-100%)
- **Health Check**: Verify stamp readiness before upload operations

### 4. Privacy Controls

- **Optional Encryption**: Users may encrypt raw provenance data before Base64 encoding. The `encryption` field declares the method (e.g., `aes-256-gcm`), but key management is left to the user.
- **No AI Screening**: Privacy checks (e.g., PII detection) are deferred to future enhancements or third-party services.

### 5. Error Handling

The framework provides structured error responses with actionable guidance:

**Stamp Errors**:
- `NOT_FOUND`: Stamp doesn't exist on connected node
- `NOT_LOCAL`: Stamp exists but not owned by this node
- `NOT_USABLE`: Stamp not yet propagated (wait 30-90 seconds)
- `EXPIRED`: Stamp TTL has reached 0
- `FULL`: Stamp at 100% utilization

**Upload Errors**:
- Insufficient funds with required/available/shortfall amounts
- Invalid redundancy level specification
- Content size exceeds stamp capacity

## Rationale

The design of this SWIP centers on providing a flexible and future-proof solution for storing provenance data on Swarm.

### Single JSON Structure

The decision to use a single JSON file structure simplifies both management and retrieval processes, enabling easy integration with existing provenance standards without enforcing a specific one. This approach acknowledges that while standards like the Data & Trust Alliance (DaTA) specification and the W3C PROV standard exist, the market is still evolving.

### Multi-Access Architecture

The three-component architecture (CLI, Gateway, MCP) emerged from implementation experience:

1. **CLI Toolkit**: Essential for developer workflows, CI/CD integration, and scripted operations
2. **Gateway Service**: Production deployments require simplified access without local Bee node infrastructure. The gateway abstracts Swarm complexity and provides duration-based stamp management instead of raw PLUR calculations.
3. **MCP Server**: AI agent integration became a clear market requirement during development. The rapid adoption of MCP as a standard for AI tool integration (late 2024) made this addition strategically important.

### Duration-Based Stamps

Users think in terms of storage duration (hours, days), not PLUR amounts or technical depth parameters. The gateway translates human-readable duration requests into appropriate stamp configurations based on current network pricing.

### Collection/Manifest Uploads

Batch provenance operations (e.g., recording transformations across multiple files) benefit significantly from TAR archive uploads, which provide substantial performance improvements compared to individual file uploads.

### Erasure Coding Options

Different use cases have different durability requirements. The framework exposes Swarm's erasure coding levels (0-4) to allow users to balance storage cost against data durability:
- Level 0: No redundancy (maximum storage efficiency)
- Level 2: Default (5% chunk loss tolerance)
- Level 4: Paranoid (50% chunk loss tolerance)

### Swarm as Trusted Third Party for Provenance

The [DSSC Blueprint](https://dssc.eu/space/BVE/357075283/Provenance+&+Traceability) defines Provenance & Traceability as a technical building block for European Data Spaces. The blueprint emphasizes that data spaces with regulated data require observable data sharing processes—for legal compliance (proving data was processed only by authorized entities) and for business reasons (marketplace and billing through a trusted third party). Key functionalities include transaction observability for compliance verification and origin verification for license compatibility when aggregating datasets.

The following diagram, adapted from the DSSC Blueprint, illustrates how Swarm fulfills the role of trusted third party for P&T data:

![Image](assets/swip-x-provenance/Provenance-diagram1.svg "Swarm as trusted third party storage - diagram.")

Both Consumer and Provider connect to the Swarm Network, which stores P&T data as a Value Added Service (VAS) Provider. Swarm's decentralized architecture, immutable storage, and content-addressed references provide the technical foundation for transaction observability and origin verification without relying on centralized infrastructure.

## Backwards Compatibility

This proposal does not introduce changes to Swarm's core functionality or protocols. It leverages existing capabilities such as immutable storage and reference hashes, ensuring full compatibility with current implementations.

The framework operates on top of existing Swarm infrastructure and adheres to established file storage and retrieval methods. All existing Swarm tools (like the Bee CLI and Dashboard) remain fully compatible.

## Test Cases

### 1. Provenance File Upload and Retrieval

- **Scenario**: User uploads a JSON file containing provenance metadata and data
- **Expected Result**: File stored on Swarm, reference hash returned, file retrievable and content_hash verified

### 2. TTL Check and Storage Extension

- **Scenario**: User checks remaining TTL for stored provenance file
- **Expected Result**: Toolkit returns remaining TTL, user can extend storage by topping up stamp

### 3. Gateway Stamp Purchase

- **Scenario**: User requests stamp with 48-hour duration via gateway
- **Expected Result**: Gateway calculates required PLUR amount, purchases stamp, returns stamp_id

### 4. MCP Agent Upload

- **Scenario**: AI agent uses `upload_data` tool to store provenance record
- **Expected Result**: Data uploaded, reference returned, agent can later retrieve via `download_data`

### 5. Stamp Utilization Warning

- **Scenario**: Stamp reaches 80% utilization
- **Expected Result**: Gateway returns `utilizationStatus: "warning"` with actionable message

### 6. Integrity Verification Failure

- **Scenario**: Downloaded data has `content_hash` mismatch (data corrupted or tampered)
- **Expected Result**: CLI reports integrity failure and rejects the data

## Implementation

The framework is implemented under the DataFund Fellowship as three open-source components:

### CLI Toolkit (`datafund/swarm_provenance_CLI`)

- **Language**: Python 3.8+
- **CLI Framework**: Typer with Rich output
- **Data Validation**: Pydantic v2
- **HTTP Client**: Requests

### Gateway Service (`datafund/swarm_connect`)

- **Language**: Python 3.8+
- **Framework**: FastAPI with Uvicorn
- **Documentation**: Auto-generated OpenAPI at `/docs`
- **Deployment**: Docker container or standalone. Public instance at `provenance-gateway.datafund.io`

### MCP Server (`datafund/swarm_provenance_mcp`)

- **Language**: Python 3.8+
- **Protocol**: Model Context Protocol (mcp>=1.0.0)
- **Gateway Client**: HTTP client for swarm_connect communication
- **Integration**: Claude Desktop or programmatic instantiation for custom agents

### Future Considerations

- Support for additional provenance standards and encryption methods
- Complex provenance chain management with linked records
- Integration with external attestation and notarization services
- On-chain anchoring for timestamp proofs (smart contract integration)
- AI agents for automated data validation and interpretation

## Security Considerations

- **No Private Key Management**: The framework does not handle private keys. Users manage their own wallet security.
- **Gateway Trust**: When using the hosted gateway, users trust the gateway operator for stamp purchases. Self-hosted gateway deployment eliminates this trust requirement.
- **Content Encryption**: Sensitive provenance data should be encrypted before upload. The framework provides the `encryption` metadata field but does not implement encryption.

## Copyright

Copyright and related rights waived via [CC0](https://creativecommons.org/publicdomain/zero/1.0/).
