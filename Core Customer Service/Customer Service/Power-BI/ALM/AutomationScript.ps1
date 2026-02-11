// =====================================================================
// Copyright (c) Microsoft Corporation. All rights reserved. 
//
//
//  THIS CODE AND INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY
//  KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE
//  IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS FOR A
//  PARTICULAR PURPOSE.
// =====================================================================
function Get-PBIAccessToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $TenantId,
        [Parameter(Mandatory=$true)]
        $PBIAppId,
        [Parameter(Mandatory=$true)]
        $PBIClientSecret
    )

    $authority = "https://login.microsoftonline.com/$TenantId/oauth2/token"
    $resource = "https://analysis.windows.net/powerbi/api"
    $body = @{
        "grant_type" = "client_credentials"
        "client_id" = $PBIAppId
        "client_secret" = $PBIClientSecret
        "resource" = $resource
    }
    Write-Host "Retreiving PBI Access Token"
    $tokenResponse = Invoke-RestMethod -Method Post -Uri $authority -Body $body
    
    return $tokenResponse.access_token
}
function Get-DVAccessToken{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $tenantId,
        [Parameter(Mandatory=$true)]
        $clientId,
        [Parameter(Mandatory=$true)]
        $clientSecret,
        [Parameter(Mandatory=$true)]
        $dataVerseURL
    )
    $oAuthTokenEndpoint = "https://login.microsoftonline.com/$tenantId/oauth2/v2.0/token"

    # OAuth Body Access Token Request
    $authBody = @{
        client_id = $clientId;
        client_secret = $ClientSecret;    
        scope = "$($dataVerseURL)/.default"    
        grant_type = 'client_credentials'
    }

    # Parameters for OAuth Access Token Request
    $authParams = @{
        URI = $oAuthTokenEndpoint
        Method = 'POST'
        ContentType = 'application/x-www-form-urlencoded'
        Body = $authBody
    }
    Write-Host "Retreiving CRM Access Token"
    # Get Access Token
    $authResponseObject = Invoke-RestMethod @authParams -ErrorAction Stop
    return $authResponseObject
}
function Get-DVWorkspaceId {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $dvAuthResponseObject,
        [Parameter(Mandatory=$true)]
        $dataVerseURL,
        [Parameter(Mandatory=$true)]
        $featureId
    )

    $getDataRequestUri = 'msdyn_dataanalyticsworkspaces?$top=5&$select=msdyn_workspaceid,msdyn_name&$filter=(msdyn_workspacetype eq 192350001 and _msdyn_datainsightsandanalyticsfeatureid_value eq '''+$featureId+''')'
    # Set up web API call parameters, including a header for the access token
    $getApiCallParams = @{
        URI = "$($dataVerseURL)/api/data/v9.1/$($getDataRequestUri)"
        Headers = @{
            "Authorization" = "$($dvAuthResponseObject.token_type) $($dvAuthResponseObject.access_token)"
            "Accept" = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
        }
        Method = 'GET'
    }
    Write-Host "Retreiving Dataverse DCCP Workspace Id"
    # Call API to Get Response
    $getApiResponseObject = Invoke-RestMethod @getApiCallParams -ErrorAction Stop

    return $getApiResponseObject.value[0].msdyn_workspaceid
}
function Get-DVDCCPReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $dvAuthResponseObject,
        [Parameter(Mandatory=$true)]
        $workspaceId,
        [Parameter(Mandatory=$true)]
        $dataVerseURL,
         [Parameter(Mandatory=$true)]
        $featureId
    )
    Write-Host "Retreiving DV DCCP Reports"
    $getDataRequestUri = 'msdyn_dataanalyticsreports?$select=msdyn_dataanalyticsreportid,msdyn_name,msdyn_workspaceid&$filter=(msdyn_workspaceid ne '''+$workspaceId+''' and _msdyn_datainsightsandanalyticsfeatureid_value eq '''+$featureId+''')'
      # Set up web API call parameters, including a header for the access token
      $getApiCallParams = @{
          URI = "$($dataVerseURL)/api/data/v9.1/$($getDataRequestUri)"
          Headers = @{
              "Authorization" = "$($dvAuthResponseObject.token_type) $($dvAuthResponseObject.access_token)"
              "Accept" = "application/json"
              "OData-MaxVersion" = "4.0"
              "OData-Version" = "4.0"
          }
          Method = 'GET'
      }
      $getApiResponseObject = Invoke-RestMethod @getApiCallParams -ErrorAction Stop
      # Output
      $dvReports = $getApiResponseObject.value
    return $dvReports    
}

function Get-PBIReports {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $accessToken,
        [Parameter(Mandatory=$true)]
        $workspaceId
    )
    Write-Host "Retreiving PBI Workspace Reports"
    $headers = @{
        "Authorization" = "Bearer $accessToken"
          'Content-Type' = 'application/json'
      }
    $uri = "https://api.powerbi.com/v1.0/myorg/groups/$workspaceId/reports"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    $pbiReports = $response.value
    return $pbiReports
    
}

function Update-DVReportReferences
{
      [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        $pbiAccessToken,
        [Parameter(Mandatory=$true)]
        $dvAuthResponseObject,
        [Parameter(Mandatory=$true)]
        $workspaceId,
        [Parameter(Mandatory=$true)]
        $dataVerseURL,
        [Parameter(Mandatory=$true)]
        $featureId
    )
    
    $pbiReports = Get-PBIReports -accessToken $pbiAccessToken -workspaceId $workspaceId
    Write-Host $pbiReports.Count
    $dvReports = Get-DVDCCPReports -dvAuthResponseObject $dvAuthResponseObject -workspaceId $workspaceId -dataVerseURL $dataVerseURL -featureId $featureId
    Write-Host $dvReports.Count
    Write-Host "Updating DCCP report references"
    foreach ($item in $dvReports)
      {
          $report = $pbiReports | Where-Object {$_.name -eq $item.msdyn_name}
          if($report -ne $null)
          {
              Write-Host "Updating report reference for $($item.msdyn_name) with PBI $($report.id)"
              $dvReportId = $item.msdyn_dataanalyticsreportid
              $patchRequestUri = "msdyn_dataanalyticsreports($($dvReportId))"+'?$select=msdyn_workspaceid,msdyn_dataanalyticsreportid'
              $updateBody  = @{
                  'msdyn_workspaceid' = ''+$workspaceId+''
                  'msdyn_reportid' = ''+$report.id+''
              } | ConvertTo-Json
              # Set up web API call parameters, including a header for the access token
              $patchApiCallParams = @{
                  URI = "$($dataVerseURL)/api/data/v9.1/$($patchRequestUri)"
                  Headers = @{
                      "Authorization" = "$($dvAuthResponseObject.token_type) $($dvAuthResponseObject.access_token)"
                      "Accept" = "application/json"
                      "OData-MaxVersion" = "4.0"
                      "OData-Version" = "4.0"
                      "Content-Type" = "application/json; charset=utf-8"
                      "Prefer" = "return=representation"  # in order to return data
                      "If-Match" = "*" 
                  }
                  Method = 'PATCH'
                  Body = $updateBody
              }
              
              $patchApiResponseObject = Invoke-RestMethod @patchApiCallParams -ErrorAction Stop   
          }
          else
          {
              Write-Host "Corresponding PBI report not found in PBI workspace with name $($item.msdyn_name)"
          }
      }
}

###Sample Usage########
#$PBIAppId = '<<Client ID which has access to Power BI workspace>>' 
#$TenantId = '<<Tenant Id of the DV/PBI organization>>'    
#$PBIClientSecret = "<<Secret of application user PBI>>" 
#$AppId = '<<Dataverse App id>>' 
#$ClientSecret = '<<DV client Secret>>' 
#$PowerPlatformEnvironmentUrl = "<<DV URL>>" 
#$PBIAccessToken = Get-PBIAccessToken -TenantId $TenantId -PBIAppId $PBIAppId -PBIClientSecret $PBIClientSecret
#$CRMAccessToken = Get-DVAccessToken -tenantId $TenantId -dataVerseURL $PowerPlatformEnvironmentUrl -clientId $AppId -clientSecret $ClientSecret
#$featureId = 'f2266eb4-226f-4cf1-b422-89c5f48b40cb'
#$workspaceId = Get-DVWorkspaceId -dvAuthResponseObject $CRMAccessToken -dataVerseURL $PowerPlatformEnvironmentUrl -featureId  featureId
#Update-DVReportReferences -pbiAccessToken $PBIAccessToken -dvAuthResponseObject $CRMAccessToken -workspaceId $workspaceId -dataVerseURL $PowerPlatformEnvironmentUrl -featureId featureId
