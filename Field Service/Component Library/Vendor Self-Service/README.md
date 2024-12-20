# Vendor Self-Service

## Overview
The Vendor Self-Service solution enables organizations using Dynamics 365 Field Service to efficiently manage external vendors and contractors. This solution automates the process of setting up vendor resources, managing their characteristics, and handling their access to the system.

## Architecture

### Components
1. **Dynamics 365 Solution**
   - Custom entities for vendor management in a lightweight model-driven app
   - Plugins for automated resource setup and real-time syncing of Field Service configurations and characteristics
   - Power Automate flows for vendor lifecycle management via Azure Function calls

2. **Azure Functions**
   - InviteVendorResource
   - AssignUserLicense
   - RemoveUserLicense
   - AddToEntraIDGroup

## Setup Steps

### Azure Functions
1. Provison an Azure Function App (or leverage an existing one)
2. Deploy Azure Functions to Function App
3. Ensure ClientId, ClientSecret, and TenantId environment variables are populated with a service principal that has rights to send Azure B2B invites, create users, add users to Entra security groups, and apply/remove M365 licenses
4. Ensure Functions are turned on and available to be invoked from Power Automate flows in your tenant

### Dynamics 365 Solution
1. Download the solution ZIP file from the repository
2. Import the solution (unmanaged) into your environment
3. Set environment variables on solution import with your 4 Azure Function URIs, the License SKU Id (the GUID of the license to apply to vendor resources, typically Field Service Contractor, GUID can be obtained from the M365 portal or Entra portal) and Entra Security Group Id (the GUID of the security group providing D365 privilages via security roles)
4. Publish all customizations

## Usage

### Setting up a new vendor administrator
### Provisioning new vendor resources
### Syncing changes from vendor resources to backend bookable resources
### Deprovisioning and reprovisioning existing vendor resources

## Disclaimer

This solution and code are provided as-is. This is not first-party Microsoft product or code, and should not be treated as such. Always test in a non-production environment. This solution is intended to be adjustable and extendable by end customers.
