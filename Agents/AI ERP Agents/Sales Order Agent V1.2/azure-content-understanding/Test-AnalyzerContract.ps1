<#
.SYNOPSIS
    Asserts the deployed Content Understanding analyzer matches the contract the
    downstream flow and ERP load depend on.

.DESCRIPTION
    Checks the analyzer AS DEPLOYED, not the local JSON file, because the two
    can drift. Verifies the full field set and - critically - the field TYPES.

    The typed fields are not an optimisation. There is no number parsing
    anywhere on the Content Understanding path: the flow's Select is named
    Normalize_items but only coalesces to valueString. If these fields revert
    to string, prices like "USD2999.00" reach Dataverse unparsed.

.EXAMPLE
    .\Test-AnalyzerContract.ps1 -Endpoint https://contoso.services.ai.azure.com
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Endpoint,

    [string]$AnalyzerId = 'sales_order_extraction_v2_0_7',

    [string]$ApiVersion = '2025-11-01',

    [string]$SampleDocument,

    [ValidateSet('extract', 'generate')]
    [string]$ExpectedLineNumberMethod = 'generate',

    [string]$ExpectedCompletionModel = 'gpt-4.1',

    # Canonical item fields the intake flow derives itself; the analyzer must NOT extract them.
    [string[]]$DerivedItemFields = @('productcoderaw'),

    # Header fields an older analyzer does not have, e.g. 'shiptocustomeraddress' for v2.0.6 and earlier.
    [string[]]$AbsentHeaderFields = @()
)

$ErrorActionPreference = 'Stop'
$Endpoint = $Endpoint.TrimEnd('/')

$script:Pass = 0
$script:Fail = 0

function Assert-That {
    param([string]$Name, [bool]$Condition, [string]$Detail)
    if ($Condition) {
        $script:Pass++
        Write-Host ("  PASS  {0}" -f $Name) -ForegroundColor Green
    }
    else {
        $script:Fail++
        Write-Host ("  FAIL  {0}" -f $Name) -ForegroundColor Red
        if ($Detail) { Write-Host ("        {0}" -f $Detail) -ForegroundColor Red }
    }
}

$EXPECTED_HEADER = @{
    documenttype                = 'string'
    deliverycustomername        = 'string'
    deliverycustomeremail       = 'string'
    billtocustomername          = 'string'
    shiptocustomername          = 'string'
    shiptocustomeraddress       = 'string'
    buyersemail                 = 'string'
    purchasingagent             = 'string'
    deliverycustomerphonenumber = 'string'
    deliverycustomeraddress     = 'string'
    deliverycustomernumber      = 'string'
    customerpurchaseordernumber = 'string'
    deliverydate                = 'date'
    suppliername                = 'string'
    supplieraddress             = 'string'
    suppliercontact             = 'string'
    supplieremail               = 'string'
    supplierphonenumber         = 'string'
    items                       = 'array'
}

$EXPECTED_ITEM = @{
    linenumber           = 'string'
    productcode          = 'string'
    productname          = 'string'
    productdescription   = 'string'
    productunitofmeasure = 'string'
    productquantity      = 'number'
    productprice         = 'number'
    productlinetotal     = 'number'
    extractedvendoritem  = 'string'
    baselineproductcode  = 'string'
    productcodesource    = 'string'
    productcoderule      = 'string'
    productcoderaw       = 'string'
}

$token = az account get-access-token --resource 'https://cognitiveservices.azure.com' `
    --query accessToken -o tsv 2>$null | Select-Object -Last 1
if (-not $token -or $token -notmatch '^ey') { throw "Run 'az login' first." }
$token = $token.Trim()
$headers = @{ Authorization = "Bearer $token" }

Write-Host "`nAnalyzer contract test" -ForegroundColor Cyan
Write-Host ("=" * 60)
Write-Host "  endpoint   : $Endpoint"
Write-Host "  analyzerId : $AnalyzerId`n"

try {
    $analyzer = Invoke-RestMethod -Uri "$Endpoint/contentunderstanding/analyzers/$AnalyzerId`?api-version=$ApiVersion" `
        -Headers $headers -TimeoutSec 120
}
catch {
    Assert-That 'analyzer is retrievable' $false "$($_.Exception.Message)"
    Write-Host "`nRESULT: FAIL - analyzer not reachable" -ForegroundColor Red
    exit 1
}

Assert-That 'analyzer is retrievable with an Entra token (no API key)' $true
Assert-That "status is 'ready'" ($analyzer.status -eq 'ready') "actual: $($analyzer.status)"
Assert-That "completion model is '$ExpectedCompletionModel'" `
    ($analyzer.models.completion -eq $ExpectedCompletionModel) `
    "actual: $($analyzer.models.completion)"

$fields = $analyzer.fieldSchema.fields
$headerNames = $fields.PSObject.Properties.Name

foreach ($absent in $AbsentHeaderFields) {
    if (-not $EXPECTED_HEADER.ContainsKey($absent)) { throw "Unknown header field: $absent" }
    Assert-That "header.$absent is absent (older analyzer)" (-not $fields.$absent) 'field unexpectedly present'
    $EXPECTED_HEADER.Remove($absent)
}

Assert-That "header field count is $($EXPECTED_HEADER.Count)" `
    ($headerNames.Count -eq $EXPECTED_HEADER.Count) "actual: $($headerNames.Count)"

foreach ($name in $EXPECTED_HEADER.Keys | Sort-Object) {
    $actual = $fields.$name
    if (-not $actual) {
        Assert-That "header.$name present" $false 'missing'
        continue
    }
    $expectedType = $EXPECTED_HEADER[$name]
    Assert-That "header.$name is '$expectedType'" `
        ($actual.type -eq $expectedType) "actual: $($actual.type)"
    Assert-That "header.$name method is 'extract'" `
        ($actual.method -eq 'extract') "actual: $($actual.method)"
}

$itemProps = $fields.items.items.properties
if (-not $itemProps) {
    Assert-That 'items array has an object schema' $false 'missing items.items.properties'
}
else {
    foreach ($derived in $DerivedItemFields) {
        if (-not $EXPECTED_ITEM.ContainsKey($derived)) { throw "Unknown derived item field: $derived" }
        Assert-That "item.$derived is NOT extracted (derived by the intake flow)" `
            (-not $itemProps.$derived) 'analyzer still extracts a flow-derived field'
        $EXPECTED_ITEM.Remove($derived)
    }
    $itemNames = $itemProps.PSObject.Properties.Name
    Assert-That "item field count is $($EXPECTED_ITEM.Count)" `
        ($itemNames.Count -eq $EXPECTED_ITEM.Count) "actual: $($itemNames.Count)"

    foreach ($name in $EXPECTED_ITEM.Keys | Sort-Object) {
        $actual = $itemProps.$name
        if (-not $actual) {
            Assert-That "item.$name present" $false 'missing'
            continue
        }
        $expectedType = $EXPECTED_ITEM[$name]
        Assert-That "item.$name is '$expectedType'" `
            ($actual.type -eq $expectedType) "actual: $($actual.type)"
        $expectedMethod = if ($name -eq 'linenumber') {
            $ExpectedLineNumberMethod
        }
        else {
            'extract'
        }
        Assert-That "item.$name method is '$expectedMethod'" `
            ($actual.method -eq $expectedMethod) "actual: $($actual.method)"
    }
}

if ($SampleDocument) {
    if (-not (Test-Path $SampleDocument)) { throw "Sample document not found: $SampleDocument" }
    Write-Host "`n  live analyze probe: $(Split-Path $SampleDocument -Leaf)"

    $bytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($SampleDocument))
    # Direct REST takes inputs[].data - inputFileContent is the connector's
    # simplified surface and is rejected here.
    $body = @{ inputs = @(@{ name = 'contract-probe'; data = $bytes }) } | ConvertTo-Json -Depth 6

    $submit = Invoke-WebRequest -Uri "$Endpoint/contentunderstanding/analyzers/$AnalyzerId`:analyze?api-version=$ApiVersion" `
        -Method POST -Headers (@{ Authorization = "Bearer $token" }) -Body $body -ContentType 'application/json' -TimeoutSec 300
    $operation = $submit.Headers['Operation-Location']
    if ($operation -is [array]) { $operation = $operation[0] }

    $deadline = (Get-Date).AddMinutes(5)
    do {
        Start-Sleep -Seconds 5
        $result = Invoke-RestMethod -Uri $operation -Headers $headers -TimeoutSec 120
    } while ($result.status -eq 'Running' -and (Get-Date) -lt $deadline)

    Assert-That 'live analyze succeeded' ($result.status -eq 'Succeeded') "status: $($result.status)"

    if ($result.status -eq 'Succeeded') {
        $content = $result.result.contents[0]
        $items = $content.fields.items.valueArray
        Assert-That 'analyze returned at least one line item' ($items.Count -gt 0) "count: $($items.Count)"

        if ($items.Count -gt 0) {
            $first = $items[0].valueObject
            foreach ($numeric in 'productquantity', 'productprice', 'productlinetotal') {
                $hasNumber = $null -ne $first.$numeric.valueNumber
                Assert-That "$numeric returned as valueNumber" $hasNumber `
                    'string output means the USD2999.00 defect can recur'
            }
        }

        # The downstream integrity guard counts line-item rows in the markdown.
        Assert-That 'markdown present for the row-count cross-check' `
            ([bool]$content.markdown) 'sourceorderedrowcount would be 0 and the load would block'
    }
}

Write-Host ("`n" + ("=" * 60))
Write-Host ("RESULT: PASS={0} FAIL={1}" -f $script:Pass, $script:Fail) `
    -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) { exit 1 }
