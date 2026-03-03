# W365 Data Collector — Schema Reference

> Schema Version: 1.0

## Overview

The collector produces JSON files in a ZIP archive. This document describes the fields in each output file.

All endpoints use the Microsoft Graph **beta** API (`https://graph.microsoft.com/beta/deviceManagement/virtualEndpoint/...`).

---

## metadata.json

| Field | Type | Description |
|-------|------|-------------|
| `SchemaVersion` | string | Schema version (e.g. "1.0") |
| `CollectorVersion` | string | Collector script version |
| `TenantId` | string | Entra ID tenant GUID |
| `CollectedBy` | string | UPN of the collecting user |
| `CollectionDate` | string | ISO 8601 timestamp |
| `CollectionDuration` | number | Seconds elapsed |
| `DaysBack` | number | Audit event lookback days |
| `Parameters` | object | Runtime flags (SkipReports) |
| `DataSources` | object | Per-source status and record count |

---

## cloud-pcs.json

Source: `/deviceManagement/virtualEndpoint/cloudPCs`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Cloud PC GUID |
| `displayName` | string | Cloud PC display name |
| `managedDeviceName` | string | Intune managed device name |
| `managedDeviceId` | string | Intune device GUID |
| `aadDeviceId` | string | Entra device object ID |
| `userPrincipalName` | string | Assigned user UPN |
| `servicePlanId` | string | W365 service plan GUID |
| `servicePlanName` | string | Plan name (e.g. "Windows 365 Enterprise 2 vCPU 8 GB 128 GB") |
| `servicePlanType` | string | enterprise / business / frontline |
| `provisioningPolicyId` | string | Linked provisioning policy GUID |
| `provisioningPolicyName` | string | Provisioning policy display name |
| `provisioningType` | string | dedicated / shared |
| `onPremisesConnectionName` | string | Azure Network Connection name |
| `status` | string | provisioned / provisioning / failed / inGracePeriod / deprovisioning |
| `statusDetails` | object | Extended status information |
| `imageDisplayName` | string | OS image being used |
| `gracePeriodEndDateTime` | string | Grace period expiry (ISO 8601) |
| `lastModifiedDateTime` | string | Last modification timestamp |
| `lastLoginResult` | object | Last login timestamp and status |
| `lastRemoteActionResult` | object | Last remote action result |
| `osVersion` | string | Windows OS version |
| `userAccountType` | string | standardUser / administrator |
| `connectivityResult` | object | Latest connectivity check result |

---

## provisioning-policies.json

Source: `/deviceManagement/virtualEndpoint/provisioningPolicies`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Policy GUID |
| `displayName` | string | Policy display name |
| `description` | string | Policy description |
| `provisioningType` | string | dedicated / shared |
| `imageType` | string | custom / gallery |
| `imageId` | string | Selected image GUID |
| `imageDisplayName` | string | Image display name |
| `enableSingleSignOn` | boolean | SSO enabled |
| `domainJoinConfigurations` | array | Domain join settings (type, region, network) |
| `windowsSetting` | object | Windows locale/language settings |
| `cloudPcNamingTemplate` | string | Naming template for provisioned PCs |
| `gracePeriodInHours` | number | License removal grace period |
| `localAdminEnabled` | boolean | Local admin rights for users |
| `autopatch` | string | Windows Autopatch policy mode |
| `microsoftManagedDesktop` | object | MMD configuration if applicable |

---

## policy-assignments.json

Source: `/deviceManagement/virtualEndpoint/provisioningPolicies/{id}/assignments`

| Field | Type | Description |
|-------|------|-------------|
| `PolicyId` | string | Parent provisioning policy GUID |
| `PolicyName` | string | Parent policy display name |
| `Assignment` | object | Assignment object containing target group |

---

## network-connections.json

Source: `/deviceManagement/virtualEndpoint/onPremisesConnections`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | ANC GUID |
| `displayName` | string | Connection display name |
| `type` | string | azureADJoin / hybridAzureADJoin |
| `subscriptionId` | string | Azure subscription GUID |
| `subscriptionName` | string | Azure subscription display name |
| `resourceGroupName` | string | Resource group name |
| `virtualNetworkId` | string | Azure VNet resource ID |
| `virtualNetworkLocation` | string | Azure region |
| `subnetId` | string | Subnet resource ID |
| `adDomainName` | string | AD domain (hybrid join only) |
| `adDomainUsername` | string | AD join service account |
| `organizationalUnit` | string | Target OU for computer objects |
| `healthCheckStatus` | string | passed / failed / running / warning / unknown |
| `healthCheckStatusDetail` | object | Individual health check results |
| `inUse` | boolean | Whether any provisioning policy references this ANC |
| `scopeIds` | array | Scope tag IDs |

---

## anc-health.json

Derived from: Network connections health check detail

| Field | Type | Description |
|-------|------|-------------|
| `ConnectionId` | string | ANC GUID |
| `ConnectionName` | string | ANC display name |
| `HealthStatus` | string | Overall status |
| `StatusDetail` | object | Individual check results (DNS, domain join, endpoint connectivity, etc.) |
| `InUse` | boolean | Whether the ANC is in use |

---

## device-images.json

Source: `/deviceManagement/virtualEndpoint/deviceImages`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Image GUID |
| `displayName` | string | Image display name |
| `version` | string | Image version string |
| `operatingSystem` | string | OS type (e.g. "Windows 11") |
| `osBuildNumber` | string | OS build number |
| `osStatus` | string | supported / deprecated / warning |
| `status` | string | ready / failed / pending |
| `sourceImageResourceId` | string | Source managed image resource ID |
| `lastModifiedDateTime` | string | Last update timestamp |

---

## gallery-images.json

Source: `/deviceManagement/virtualEndpoint/galleryImages`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Gallery image GUID |
| `displayName` | string | Image display name |
| `offerDisplayName` | string | Marketplace offer name |
| `publisher` | string | Publisher name |
| `sizeInGB` | number | Image size in GB |
| `status` | string | supported / deprecated |
| `startDate` | string | Support start date |
| `endDate` | string | Support end date |
| `recommendedSku` | string | Recommended VM SKU |

---

## user-settings.json

Source: `/deviceManagement/virtualEndpoint/userSettings`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Setting GUID |
| `displayName` | string | Setting display name |
| `localAdminEnabled` | boolean | Local admin rights |
| `resetEnabled` | boolean | Self-service reset allowed |
| `restorePointSetting` | object | Restore point frequency and user control settings |
| `selfServiceEnabled` | boolean | Self-service actions available |
| `lastModifiedDateTime` | string | Last update timestamp |

---

## user-setting-assignments.json

Source: `/deviceManagement/virtualEndpoint/userSettings/{id}/assignments`

| Field | Type | Description |
|-------|------|-------------|
| `SettingId` | string | Parent user setting GUID |
| `SettingName` | string | Parent setting display name |
| `Assignment` | object | Assignment target group |

---

## service-plans.json

Source: `/deviceManagement/virtualEndpoint/servicePlans`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Service plan GUID |
| `displayName` | string | Plan display name |
| `type` | string | enterprise / business / frontline |
| `vCpuCount` | number | Virtual CPU count |
| `ramInGB` | number | RAM in GB |
| `storageInGB` | number | Storage in GB |
| `userProfileInGB` | number | User profile storage |
| `supportedSolution` | string | cloudPcForEnterprise / devBox |

---

## audit-events.json

Source: `/deviceManagement/virtualEndpoint/auditEvents`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Event GUID |
| `displayName` | string | Event description |
| `activity` | string | Action performed |
| `activityDateTime` | string | ISO 8601 timestamp |
| `activityType` | string | Type of activity |
| `actor` | object | Who performed the action (user, app, etc.) |
| `category` | string | Event category |
| `componentName` | string | Affected component |
| `activityResult` | string | success / failure |
| `resources` | array | Affected resources |

---

## connection-quality.json (optional, SkipReports to exclude)

Source: `/deviceManagement/virtualEndpoint/reports/getRealTimeRemoteConnectionStatus`

Cloud PC connection quality metrics. Fields vary by report version.

---

## connection-history.json (optional, SkipReports to exclude)

Source: `/deviceManagement/virtualEndpoint/reports/getRemoteConnectionHistoricalReports`

| Field | Type | Description |
|-------|------|-------------|
| `CloudPcId` | string | Cloud PC GUID |
| `ManagedDeviceName` | string | Device name |
| `UserPrincipalName` | string | User UPN |
| `RoundTripTimeInMs` | number | Network round trip time |
| `AvailableBandwidthInMBps` | number | Available bandwidth |
| `SignInDateTime` | string | Session start |
| `SignOutDateTime` | string | Session end |
| `RemoteSignInTimeInSec` | number | Sign-in duration |
| `CloudPcFailurePercentage` | number | Connection failure rate |
