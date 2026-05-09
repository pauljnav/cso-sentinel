### PROJECT_CONTEXT.md
## 1. Executive Summary
**Project Name:** CSO Sentinel
**Objective:** A self-configuring data client for the Ireland CSO PxStat API.
**Core Innovation:** Uses **GitHub Actions** and **PowerShell Core (pwsh)** as a meta-programming engine to audit the CSO API, generate JSON Schemas/OpenAPI specs, and commit them to the repository to drive the application's configuration.
## 2. Technical Stack & Architecture
 * **Language:** PowerShell Core (pwsh) 7.x
 * **Automation:** GitHub Actions (Ubuntu-latest runner)
 * **Data Format:** JSON-stat 2.0 (Upstream) → JSON Schema / OpenAPI 3.0 (Internal)
 * **State Management:** config.yml (Manual input) and assets/inventory.json (Generated state)
### Decision Log
| ID | Decision | Justification |
|---|---|---|
| **D-01** | **Config-Driven** | Manifest-based approach allows adding datasets without modifying core logic. |
| **D-02** | **Artifact Persistence** | Generated assets are committed to Git to provide a versioned history of government data structures. |
| **D-03** | **Sampling Strategy** | Queries use metadata-only or restricted observations to avoid 429 rate limiting. |
| **D-04** | **Adapter Pattern** | The app logic consumes generated schemas, decoupling it from the raw upstream JSON-stat format. |
| **D-05** | **PowerShell Core** | Chosen for superior native JSON object handling and seamless integration with GitHub runners without pip overhead. |
## 3. Implementation Roadmap
### Phase 1: The Inspector (MVP)
**Task:** PowerShell script to validate connectivity.
 * Parse config.yml using Get-Content and ConvertFrom-Yaml (or JSON equivalent).
 * Execute Invoke-RestMethod to the CSO RESTful API.
 * Validate 200 OK status and log metadata (Table ID, Last Modified).
### Phase 2: The Generator
**Task:** Transform raw metadata into developer-ready assets.
 * Analyze the $response.dimension object.
 * Generate a **JSON Schema** that maps expected categories and variables.
 * Update a central openapi.yml by injecting paths for each Table ID.
 * **Output Path:** /assets/schemas/{id}.json
### Phase 3: GitHub Action Integration
**Task:** Automate the sync lifecycle.
 * Workflow: .github/workflows/sync-cso.yml.
 * Trigger: Weekly cron and workflow_dispatch.
 * **Pattern:** Checkout → Run pwsh ./scripts/Sync-Cso.ps1 → Auto-commit changes back to main.
## 4. Operational Instructions for LLM / Copilot
 1. **Object-Oriented Pipes:** Leverage PowerShell’s pipeline. Treat JSON as objects, not strings.
 2. **Idempotency:** The script must not create a Git diff if the CSO data structure has not changed. Compare hashes or timestamps before overwriting.
 3. **Error Resilience:** If Invoke-RestMethod fails for one ID, catch the error, log it, and proceed to the next item in the manifest.
 4. **Formatting:** Ensure all generated JSON is "pretty-printed" for readable Git diffs.
## 5. Git & PR Strategy
 * **Direct Commit:** Small metadata updates can be committed directly to main by the Action.
 * **Breaking Changes:** If the script detects a change in existing dimensions (e.g., a column was removed), it should log a high-priority warning in the Action output.


## 6. Test-Driven Development (TDD) Protocol
To maintain the integrity of our generated assets, all PowerShell logic must follow a "Test-First" approach using **Pester** (the PowerShell testing framework).
### The TDD Cycle
 1. **Red:** Write a Pester test in /tests/Sync.Tests.ps1 that defines an expected output (e.g., "The generated JSON Schema must contain a 'dimensions' key").
 2. **Green:** Write the minimum PowerShell code in the script to make that test pass.
 3. **Refactor:** Clean up the code while ensuring the test suite remains green.
### Key Testing Areas
 * **Schema Validation:** Tests must verify that the generator correctly maps CSO "Variables" to JSON Schema "Properties."
 * **Mocking:** Use Context and Mock in Pester to simulate CSO API responses. This allows testing Phase 2 (Generation) without hitting the live network.
 * **Idempotency Checks:** A test must confirm that running the script twice on the same data results in zero file changes.
### Pre-Commit Validation
The GitHub Action will run the Pester suite *before* the generation phase. If tests fail, the sync is aborted to prevent corrupting the repository's metadata assets.
```powershell
# Example Pester Goal
Describe "CSO Schema Generator" {
    It "Should produce a valid JSON file" {
        $path = "./assets/schemas/HPM05.json"
        $path | Should -Exist
        (Get-Content $path | ConvertFrom-Json) | Should -Not -BeNull
    }
}

```
### Decision Log Update
| ID | Decision | Justification |
|---|---|---|
| **D-06** | **Pester Framework** | Standardizes TDD in PowerShell. Ensures that "Self-Generated" code is validated before being committed to the repo. |
### Operational Instructions for LLM / Copilot
 * **Prioritize Tests:** When asked to create a new feature (e.g., a new mapping logic), always generate the Pester test file first.
 * **Mock API Responses:** Use static JSON samples in the tests/fixtures folder to ensure consistent, offline-capable testing environments.



*This document is the authoritative context for CSO Sentinel development. Refer to it for all architectural and logic queries.*
