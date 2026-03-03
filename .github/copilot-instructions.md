# Copilot Instructions — Windows 365 Data Collector

## Quick Context for Copilot

This is a **PowerShell-based Windows 365 (Cloud PC) data collection tool** that customers run against their Microsoft 365 tenant. It collects configuration, provisioning, network, and Cloud PC data via the Microsoft Graph beta API and exports a portable ZIP of JSON files.

**Two-repo architecture:**
- **w365-data-collector** (public, this repo) — Customer-facing. Collects data from Graph API. Exports JSON ZIP with schema versioning.
- **w365-evidence-pack** (private) — Ingests the collection ZIP offline. Performs all analysis, scoring, and reporting. Owner's IP.

**Single-file script**: `Collect-W365Data.ps1` (~370 lines). No build system — runs directly.

---

## Architecture

1. **Authentication** — `Microsoft.Graph.Authentication` module, `Connect-MgGraph` with `CloudPC.Read.All`, `Directory.Read.All`
2. **Step 1: Cloud PCs** — `/deviceManagement/virtualEndpoint/cloudPCs` (inventory, status, sizing)
3. **Step 2: Provisioning Policies** — `/provisioningPolicies` + per-policy `/assignments` (can't use $expand)
4. **Step 3: Network Connections** — `/onPremisesConnections` + health check details
5. **Step 4: Device Images** — `/deviceImages` (custom) + `/galleryImages`
6. **Step 5: User Settings** — `/userSettings` + per-setting `/assignments`
7. **Step 6: Service Plans** — `/servicePlans` (license sizing info)
8. **Step 7: Audit Events** — `/auditEvents` (configurable lookback period)
9. **Step 8: Reports** — Connection quality, history, right-sizing recommendations (optional via `-SkipReports`)
10. **Package** — Save JSON files + `metadata.json` → compress to ZIP

---

## Critical Coding Patterns

### Strict Mode
`Set-StrictMode -Version Latest` — all variables must be initialized, property access on `$null` throws.

### Graph API (Beta)
- **All W365 endpoints use beta**: `https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/...`
- **$expand doesn't work for assignments** — separate calls per policy/setting required
- **ANC names are case-sensitive** in the API
- **Rate limiting is stricter** than general Graph API — use exponential backoff
- **Rate limits cascade** across endpoints in the same Intune/W365 category
- 404 responses mean "endpoint not available for this tenant" — handle gracefully, don't crash

### Rate Limiting
`Invoke-GraphPagedRequest` and `Invoke-GraphSingleRequest` both implement:
- Exponential backoff: 2s, 4s, 8s, 16s, 32s for 429/503 responses
- `Retry-After` header support
- Max retry count (5 for paged, 3 for single)
- Separate handling for 404 (skip, don't retry)

### PowerShell 5.1 Compatibility
- No Unicode chars (checkmarks, em-dashes) in double-quoted strings — use `[OK]`, `[WARN]`, `[WAIT]`
- No `??` (null-coalescing) or `?.` (null-conditional) operators
- Use `if ($null -ne $x)` not `if ($x)` for explicit null checks

### Output
- Each collection step stores data in `$collected["key-name"]`
- All data serialized with `ConvertTo-Json -Depth 15`
- `metadata.json` records: SchemaVersion, CollectorVersion, TenantId, CollectedBy, CollectionDate, Duration, Parameters, per-DataSource status/count
- ZIP naming: `W365Collection_{TenantIdPrefix}_{DateTime}.zip`

---

## Common Tasks

### Adding a new collection endpoint
1. Add a new step section following the existing pattern (Write-Host step header, Invoke-GraphPagedRequest, store in $collected)
2. Handle the endpoint possibly not existing (404) or being permission-denied (403)
3. Update `docs/SCHEMA.md` with field documentation
4. Update README.md collection steps table

### Important constraints
- **Read-only**: Never create, modify, or delete any resources
- **Customer-facing**: Keep output clear and professional
- **Graceful failures**: Missing permissions or unavailable endpoints should warn, not crash
- **DryRun**: Must validate connectivity and permissions without collecting data
