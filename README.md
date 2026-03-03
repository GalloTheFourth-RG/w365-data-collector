# Windows 365 Data Collector

> Version 1.0.0 | March 2026

Collects Windows 365 Cloud PC configuration, provisioning policies, network connections, user settings, device images, and reports from a customer's Microsoft 365 tenant via the Microsoft Graph API.

Produces a portable ZIP of JSON files that the [W365 Evidence Pack](https://github.com/yourorg/w365-evidence-pack) ingests offline for analysis and scoring.

## Quick Start

```powershell
# Install prerequisite
Install-Module Microsoft.Graph.Authentication -Scope CurrentUser

# Connect and collect
Connect-MgGraph -TenantId "your-tenant-id" -Scopes "CloudPC.Read.All","Directory.Read.All"
.\Collect-W365Data.ps1 -TenantId "your-tenant-id"
```

## Parameters

| Parameter | Required | Description |
|-----------|----------|-------------|
| `-TenantId` | Yes | Azure AD / Entra ID tenant ID |
| `-OutputPath` | No | Output directory (default: current directory) |
| `-SkipReports` | No | Skip Cloud PC reports (connection quality, recommendations) |
| `-DryRun` | No | Validate connectivity without collecting data |

## Collection Steps

| Step | Endpoint | Output File(s) |
|------|----------|-----------------|
| 1. Cloud PCs | `/deviceManagement/virtualEndpoint/cloudPCs` | `CloudPCs.json` |
| 2. Provisioning Policies | `/deviceManagement/virtualEndpoint/provisioningPolicies` | `ProvisioningPolicies.json` |
| 3. Policy Assignments | `/provisioningPolicies/{id}/assignments` | `PolicyAssignments.json` |
| 4. Azure Network Connections | `/deviceManagement/virtualEndpoint/onPremisesConnections` | `NetworkConnections.json` |
| 5. User Settings | `/deviceManagement/virtualEndpoint/userSettings` | `UserSettings.json` |
| 6. Device Images | `/deviceManagement/virtualEndpoint/deviceImages` | `DeviceImages.json` |
| 7. Gallery Images | `/deviceManagement/virtualEndpoint/galleryImages` | `GalleryImages.json` |
| 8. Audit Events | `/deviceManagement/virtualEndpoint/auditEvents` | `AuditEvents.json` |
| 9. Reports | Various `/reports/` endpoints | `Report_*.json` |

## Required Permissions

| Permission | Type | Purpose |
|------------|------|---------|
| `CloudPC.Read.All` | Delegated or Application | Read Cloud PC configurations, policies, and status |
| `Directory.Read.All` | Delegated or Application | Resolve group names for policy assignments |

## Output

A ZIP file named `W365Collection_{TenantId}_{Date}.zip` containing:
- JSON files for each collection step
- `metadata.json` with schema version, collection timestamp, and parameter state

## Important Notes

- **Read-only**: This script only reads data. It never creates, modifies, or deletes any resources.
- **Beta API**: Windows 365 endpoints under `/deviceManagement/virtualEndpoint/` are primarily available via the beta Graph API endpoint. The collector uses `https://graph.microsoft.com/beta/`.
- **Rate limiting**: The script includes exponential backoff for 429/503 responses. Intune/W365 endpoints have stricter rate limits than general Graph API.
- **No PII in transit**: Data stays local. The ZIP is handed to the consultant for offline analysis.

## Schema Version

Current: **1.0**

See [docs/SCHEMA.md](docs/SCHEMA.md) for field-level documentation.

## License

MIT - See [LICENSE](LICENSE) for details.
