<#
.SYNOPSIS
  One-time data setup after importing the Sales Order Agent solution.

.DESCRIPTION
  The solution carries tables, flows, screens and roles but no data. This script adds the three things a new
  environment needs:
    1. The first Published customer-matching policy (key 'default') with the standard rule values. Without a
       Published policy the customer resolver holds every order.
    2. The starter unit-of-measure aliases (read from the shipped default of the aipod_UomAliasMap variable), so
       Setup > Units of measure lists them. The same list is already in effect without this step.
    3. The Customer Match Policy Reader field security profile, assigned to the business-unit default teams so
       reviewers can read the matching evidence on each order.

  It is safe to run again: anything that already exists is left alone. Without -Apply it only reports what it would do.

.PARAMETER EnvironmentUrl
  The Dataverse URL of the target environment, for example https://contoso.crm.dynamics.com

.PARAMETER AddressBasis
  BillTo (default) or ShipTo. The customer-matching address basis for the first policy. Change it later by publishing
  a new policy version in Setup > Matching rules.

.EXAMPLE
  az login
  .\Initialize-SalesOrderAgent.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com            # report only
  .\Initialize-SalesOrderAgent.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -Apply

  Run it as a System Administrator of the target environment. Requires PowerShell 7 or later and the Azure CLI.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^https://[^/]+$')][string]$EnvironmentUrl,
    [ValidateSet('BillTo', 'ShipTo')][string]$AddressBasis = 'BillTo',
    [switch]$Apply,
    [switch]$SkipPolicy,
    [switch]$SkipUnitAliases,
    [switch]$SkipFieldSecurity
)

$ErrorActionPreference = 'Stop'
$base = "$EnvironmentUrl/api/data/v9.2"

$token = az account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv
if (-not $token) { throw 'Could not get a token. Run az login with an account that has access to the environment.' }
$headers = @{ Authorization = "Bearer $token"; Accept = 'application/json'; 'OData-MaxVersion' = '4.0'; 'OData-Version' = '4.0' }

function Invoke-Dataverse {
    param([string]$Method = 'GET', [string]$Path, $Body, [hashtable]$Extra = @{})
    $h = $headers.Clone(); foreach ($k in $Extra.Keys) { $h[$k] = $Extra[$k] }
    $p = @{ Method = $Method; Uri = "$base/$Path"; Headers = $h }
    if ($null -ne $Body) { $p.Body = ($Body | ConvertTo-Json -Depth 8); $p.ContentType = 'application/json; charset=utf-8' }
    Invoke-RestMethod @p
}

$who = Invoke-Dataverse -Path 'WhoAmI'
Write-Host "Environment: $EnvironmentUrl"
Write-Host "Mode: $(if ($Apply) { 'APPLY' } else { 'report only (add -Apply to make changes)' })"
Write-Host ''

# --------------------------------------------------------------------------------------------------------------
# 1. First Published matching policy
# --------------------------------------------------------------------------------------------------------------
if (-not $SkipPolicy) {
    Write-Host '1. Customer matching policy'
    $state = @{ Draft = 100000000; PublishRequested = 100000001; Published = 100000002; Retired = 100000003; Rejected = 100000004 }
    $existing = (Invoke-Dataverse -Path "aipod_customermatchpolicies?`$select=aipod_state,aipod_version&`$filter=aipod_policykey eq 'default'").value
    if ($existing.Count -gt 0) {
        $published = @($existing | Where-Object { $_.aipod_state -eq $state.Published })
        Write-Host "   Policy 'default' already has $($existing.Count) row(s); $($published.Count) Published. Nothing to do."
    }
    else {
        $row = [ordered]@{
            aipod_name = 'Default customer match policy'; aipod_policykey = 'default'
            aipod_addressbasis = $(if ($AddressBasis -eq 'ShipTo') { 100000001 } else { 100000000 })
            aipod_nameexactpoints = 40; aipod_namecontainspoints = 20; aipod_namecontainsminlength = 5
            aipod_emailpoints = 15; aipod_streetpoints = 10; aipod_zippoints = 20; aipod_citypoints = 10; aipod_statepoints = 5
            aipod_fallbackenabled = $false; aipod_fallbackstreetpoints = 5; aipod_fallbackzippoints = 10
            aipod_fallbackcitypoints = 5; aipod_fallbackstatepoints = 0
            aipod_threshold = 70; aipod_margin = 15
            aipod_requirename = $true; aipod_stripslashsuffix = $true; aipod_ignorelegalsuffix = $true
            aipod_changereason = 'Initial policy with the standard rule values.'
            aipod_publishrequest = $false
        }
        Write-Host "   Would create policy 'default' ($AddressBasis, threshold 70, margin 15) and publish it."
        if ($Apply) {
            $created = Invoke-Dataverse -Method POST -Path 'aipod_customermatchpolicies' -Body $row -Extra @{ Prefer = 'return=representation' }
            $id = $created.aipod_customermatchpolicyid
            Invoke-Dataverse -Method PATCH -Path "aipod_customermatchpolicies($id)" -Body @{ aipod_publishrequest = $true } -Extra @{ 'If-Match' = '*' } | Out-Null
            $deadline = (Get-Date).AddMinutes(6)
            do {
                Start-Sleep -Seconds 5
                $now = Invoke-Dataverse -Path "aipod_customermatchpolicies($id)?`$select=aipod_state,aipod_validationmessage,aipod_version"
            } while ((Get-Date) -lt $deadline -and $now.aipod_state -in @($state.Draft, $state.PublishRequested))
            if ($now.aipod_state -eq $state.Published) {
                Write-Host "   Published version $($now.aipod_version)."
            }
            else {
                throw "The policy was not published (state $($now.aipod_state)): $($now.aipod_validationmessage). Make sure the 'SOA - Publish Customer Match Policy V1' flow is On and its connections are bound, then run this script again."
            }
        }
    }
    Write-Host ''
}

# --------------------------------------------------------------------------------------------------------------
# 2. Starter unit aliases
# --------------------------------------------------------------------------------------------------------------
if (-not $SkipUnitAliases) {
    Write-Host '2. Unit-of-measure aliases'
    $definition = (Invoke-Dataverse -Path "environmentvariabledefinitions?`$select=defaultvalue&`$filter=schemaname eq 'aipod_UomAliasMap'").value
    if ($definition.Count -ne 1 -or -not $definition[0].defaultvalue) { throw "Environment variable aipod_UomAliasMap was not found. Import the solution first." }
    $starter = $definition[0].defaultvalue | ConvertFrom-Json -AsHashtable
    $classOf = @{ ea = 'Count'; dz = 'Count'; pr = 'Count'; Set = 'Count'; Kit = 'Count'; Case = 'Packaging'; Box = 'Packaging'; Pack = 'Packaging'
                  Roll = 'Packaging'; Lb = 'Weight'; Oz = 'Weight'; Ft = 'Length'; Yd = 'Length'; Mtr = 'Length'; Gal = 'Volume'; Ltr = 'Volume' }
    $classValue = @{ Count = 100000000; Packaging = 100000001; Weight = 100000002; Length = 100000003; Volume = 100000004; Other = 100000005 }
    $have = @{}
    foreach ($r in (Invoke-Dataverse -Path 'aipod_unitaliases?$select=aipod_alias&$top=5000').value) { $have[$r.aipod_alias.ToLowerInvariant()] = $true }
    $missing = @($starter.Keys | Sort-Object | Where-Object { -not $have.ContainsKey($_.ToLowerInvariant()) })
    Write-Host "   $($starter.Count) starter aliases; $($have.Count) already in the table; $($missing.Count) to add."
    if ($Apply -and $missing.Count -gt 0) {
        foreach ($alias in $missing) {
            $unit = $starter[$alias]
            $class = if ($classOf.ContainsKey($unit)) { $classOf[$unit] } else { 'Other' }
            Invoke-Dataverse -Method POST -Path 'aipod_unitaliases' -Body ([ordered]@{
                    aipod_alias = $alias; aipod_normalizedunit = $unit; aipod_active = $true
                    aipod_unitclass = $classValue[$class]; aipod_changereason = 'Starter list'; aipod_publishstatus = 100000000
                }) | Out-Null
        }
        Write-Host "   Added $($missing.Count) aliases. With the 'SOA - Publish Unit Alias Map' flow On, each row shows Published within a minute or two; the same list is already in effect."
    }
    Write-Host ''
}

# --------------------------------------------------------------------------------------------------------------
# 3. Reader field security profile for the default teams
# --------------------------------------------------------------------------------------------------------------
if (-not $SkipFieldSecurity) {
    Write-Host '3. Field security (Customer Match Policy Reader)'
    $profiles = (Invoke-Dataverse -Path "fieldsecurityprofiles?`$select=fieldsecurityprofileid&`$filter=name eq 'Customer Match Policy Reader'").value
    if ($profiles.Count -ne 1) { throw "Field security profile 'Customer Match Policy Reader' was not found. Import the solution first." }
    $profileId = $profiles[0].fieldsecurityprofileid
    $assigned = @{}
    foreach ($t in (Invoke-Dataverse -Path "fieldsecurityprofiles($profileId)/teamprofiles_association?`$select=teamid").value) { $assigned[$t.teamid] = $true }
    $teams = (Invoke-Dataverse -Path 'teams?$select=teamid,name&$filter=isdefault eq true').value
    $todo = @($teams | Where-Object { -not $assigned.ContainsKey($_.teamid) })
    Write-Host "   $($teams.Count) business-unit default team(s); $($todo.Count) to assign."
    if ($Apply) {
        foreach ($t in $todo) {
            Invoke-Dataverse -Method POST -Path "teams($($t.teamid))/teamprofiles_association/`$ref" -Body @{ '@odata.id' = "$base/fieldsecurityprofiles($profileId)" } | Out-Null
        }
        if ($todo.Count) { Write-Host "   Assigned." }
    }
    Write-Host ''
}

Write-Host $(if ($Apply) { 'Done.' } else { 'Report only. Run again with -Apply to make the changes.' })
