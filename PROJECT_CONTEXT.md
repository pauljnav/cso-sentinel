
# Project Context: CSO Sentinel

## 1. Executive Summary
**Project Name:** CSO Sentinel  
**Objective:** A self-configuring data client for the [Ireland CSO PxStat API](https://data.cso.ie/).  
**Core Innovation:** Uses **GitHub Actions** and **PowerShell Core (pwsh)** as a meta-programming engine to audit the CSO API, generate JSON Schemas/OpenAPI specs, and commit them back to the repository to drive the application's configuration.

---

## 2. Technical Stack & Architecture
* **Language:** PowerShell Core (`pwsh`) 7.x
* **Automation:** GitHub Actions (Ubuntu-latest runner)
* **Testing:** Pester 5.x (TDD Framework)
* **Data Format:** JSON-stat 2.0 (Upstream) → JSON Schema / OpenAPI 3.0 (Internal)
* **State Management:** `config.yml` (Manual input) and `assets/inventory.json` (Generated state)

---

## 3. Directory Structure
```text
.
├── .github/workflows/
│   └── sync-cso.yml         # GitHub Action definition
├── assets/
│   ├── schemas/             # Generated JSON Schemas per Table ID
│   ├── openapi.yml          # Consolidated OpenAPI Specification
│   └── inventory.json       # Metadata & health status of tracked tables
├── scripts/
│   ├── Sync-Cso.ps1         # Main execution logic
│   ├── Get-CsoMetadata.ps1  # API interaction module
│   └── Build-Schema.ps1     # Transformation logic
├── tests/
│   ├── Sync.Tests.ps1       # Pester integration tests
│   └── fixtures/            # Mock CSO JSON responses for offline testing
├── config.yml               # Input: List of Table IDs to track
└── PROJECT_CONTEXT.md       # This document

4. Detailed Decision Log
| ID | Decision | Justification |
|---|---|---|
| D-01 | Config-Driven | Manifest-based approach allows adding datasets without modifying core logic. |
| D-02 | Artifact Persistence | Generated assets are committed to Git to provide a versioned history of government data. |
| D-03 | Sampling Strategy | Queries use metadata-only or restricted observations to avoid 429 rate limiting. |
| D-04 | Adapter Pattern | Main app consumes generated assets, decoupling it from raw JSON-stat complexity. |
| D-05 | PowerShell Core | Superior native JSON object handling and seamless integration with GitHub runners. |
| D-06 | Pester Framework | Standardizes TDD; prevents committing corrupt schemas to the repository. |
| D-07 | Shadow-Mode Updates | When a schema changes, the script updates inventory.json with a version bump. |
5. Implementation Roadmap
Phase 1: The Inspector (MVP)
 * Parse config.yml.
 * Execute Invoke-RestMethod to validate CSO endpoint availability.
 * Log "Last-Modified" headers to determine if a sync is required.
Phase 2: The Generator (TDD Focused)
 * Test: Define expected JSON Schema structure for a standard CSO response.
 * Code: Map $response.dimension keys (Variables/Classifications) to JSON Schema properties.
 * Code: Inject the Table ID as a new path in the openapi.yml file.
Phase 3: GitHub Action Automation
 * Trigger: Weekly cron and workflow_dispatch.
 * Permissions: contents: write required for the runner to push updates.
 * Safety: The workflow must fail if Pester tests do not pass.
6. Test-Driven Development (TDD) Protocol
To maintain the integrity of our generated assets, all PowerShell logic must follow a "Test-First" approach using Pester.
The TDD Cycle
 * Red: Write a Pester test in /tests/Sync.Tests.ps1 defining expected output (e.g., "The generated JSON Schema must contain a 'dimensions' key").
 * Green: Write the minimum PowerShell code in the script to make that test pass.
 * Refactor: Clean up code while keeping the test suite green.
Key Testing Areas
 * Schema Validation: Verify generator maps CSO "Variables" to JSON Schema "Properties".
 * Mocking: Use Context and Mock in Pester to simulate CSO API responses for offline testing.
 * Idempotency Checks: Confirm that running the script twice on unchanged data results in zero file diffs.
7. Operational Instructions for LLM / Copilot
 * Object Handling: Use [PSCustomObject] for all internal data structures to ensure clean JSON conversion.
 * Idempotency: Before writing to disk, compare the new content hash with the existing file hash. Do not overwrite if identical.
 * Error Handling: Wrap API calls in try/catch. If an endpoint fails, mark it active: false in inventory.json but do not break the overall build.
 * TDD Requirement: For every new function in scripts/, provide a corresponding it block in tests/.
8. Definition of Done (Production Ready)
 * [ ] Sync-Cso.ps1 runs end-to-end without manual intervention.
 * [ ] assets/schemas/ contains valid JSON Schema files for all IDs in config.yml.
 * [ ] openapi.yml can be imported into Swagger/Postman without errors.
 * [ ] GitHub Action commits changes back to main with message: build: auto-update cso metadata [skip ci].
 * [ ] Pester test coverage exceeds 80% of script logic.

<ElicitationsGroup message="Would you like to build the initial configuration or workflow file next?">
  <Elicitation label="Draft the initial config.yml with sample CSO tables" query="Draft an initial config.yml with sample Irish CSO PxStat table IDs like housing, population, and employment."/>
  <Elicitation label="Draft the GitHub Action workflow YAML file" query="Draft the .github/workflows/sync-cso.yml GitHub Action file for executing pwsh and committing updates."/>
</ElicitationsGroup>

