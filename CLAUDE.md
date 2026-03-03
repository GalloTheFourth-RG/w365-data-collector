# CLAUDE.md — Windows 365 Data Collector

## Project Overview

This is a **public** repo containing a PowerShell data collection script for Windows 365 (Cloud PC) environments. Customers run this to collect configuration, provisioning, network, and Cloud PC data via the Microsoft Graph beta API. It exports a portable ZIP of JSON files that the [W365 Evidence Pack](../w365-evidence-pack) ingests offline for analysis.

The owner (Richie) is an AVD/EUC consultant. He is new to Git/DevOps — keep commands simple and explain what they do.

## Related Repositories

- **w365-evidence-pack** (private, at `C:\repos\w365-evidence-pack`) — ingests the ZIP offline, produces HTML dashboard + CSV exports
- **shared-assessment-framework** (private, at `C:\repos\shared-assessment-framework`) — shared CSS/JS, PII helpers, build template
- **enhanced-avd-evidence-pack** (private, at `C:\repos\enhanced-avd-evidence-pack`) — sister product for AVD assessment
- **intune-evidence-pack** (private, at `C:\repos\intune-evidence-pack`) — sister product for Intune assessment

## Architecture

Single script (`Collect-W365Data.ps1`) that:
1. Authenticates via `Microsoft.Graph.Authentication` module
2. Collects data from 8 Graph API categories under `/deviceManagement/virtualEndpoint/`
3. Saves JSON files to a temp directory
4. Compresses into a portable ZIP with metadata

### Collection Steps

| Step | Endpoint | Output |
|------|----------|--------|
| 1 | `/cloudPCs` | Cloud PC inventory (status, sizing, provisioning type) |
| 2 | `/provisioningPolicies` + `/{id}/assignments` | Policies and group assignments |
| 3 | `/onPremisesConnections` | Azure Network Connections + health checks |
| 4 | `/deviceImages` + `/galleryImages` | Custom and gallery OS images |
| 5 | `/userSettings` + `/{id}/assignments` | User settings and group assignments |
| 6 | `/servicePlans` | License/sizing plan information |
| 7 | `/auditEvents` | Audit trail (configurable lookback) |
| 8 | `/reports/*` | Connection quality, history, recommendations |

## Key Technical Details

### Graph API
- **All endpoints use beta**: `https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/...`
- **Permissions**: `CloudPC.Read.All`, `Directory.Read.All`
- **$expand doesn't work for assignments** — must make individual calls per policy/setting
- **Rate limiting**: W365/Intune endpoints have stricter throttle limits than general Graph API. Script uses exponential backoff (2s, 4s, 8s, 16s, 32s) with Retry-After header support.
- **Rate limits cascade** across endpoints in the same category — throttling on `/cloudPCs` may affect `/provisioningPolicies`

### Coding Patterns
- `Set-StrictMode -Version Latest` — all variables must be initialized
- `Invoke-GraphPagedRequest` — handles pagination via `@odata.nextLink` with retry logic
- `Invoke-GraphSingleRequest` — single request with retry, handles 404 gracefully (endpoint not available)
- **Read-only**: Script never creates, modifies, or deletes any resources
- **PS 5.1 compatible**: Avoid Unicode chars in double-quoted strings, use `[OK]`/`[WARN]` instead of checkmarks

### Schema
- `metadata.json` includes schema version, collector version, tenant info, parameter state, and per-source status/counts
- Schema version: `1.0`
- See `docs/SCHEMA.md` for full field documentation

## Common Tasks

### Adding a new collection step
1. Add a new section in `Collect-W365Data.ps1` following the existing pattern
2. Use `Invoke-GraphPagedRequest` for list endpoints, `Invoke-GraphSingleRequest` for single-object endpoints
3. Store in `$collected["new-key"]`
4. Update `docs/SCHEMA.md` with field documentation
5. Update README.md collection steps table

### Version bumping
Update `$script:ScriptVersion` and `$script:SchemaVersion` at the top of `Collect-W365Data.ps1`, and README.md.

## Important Context

- This script is given to customers — keep it simple, well-commented, and read-only
- Customers may have limited Graph API permissions — handle 403/404 gracefully
- ANC (Azure Network Connection) name matching is case-sensitive in the API
- Some tenants may not have W365 licenses — the DryRun mode tests for this
- The script should work on both PowerShell 5.1 and 7+
