[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [uri]$ApimEndpoint,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CommerceSdkPackagesVersion,

    [ValidatePattern('^\d+\.\d+$')]
    [string]$BuildNumber = '1.0',

    [string]$MSBuildPath
)

$ErrorActionPreference = 'Stop'
if (-not $ApimEndpoint.IsAbsoluteUri -or $ApimEndpoint.Scheme -ne 'https' -or
    $ApimEndpoint.UserInfo -or $ApimEndpoint.Query -or $ApimEndpoint.Fragment) {
    throw 'ApimEndpoint must be an absolute HTTPS base URL without credentials, a query, or a fragment.'
}
if ($ApimEndpoint.AbsolutePath.TrimEnd('/') -match '/(chat|attachments)$') {
    throw 'Supply the APIM base URL, not a chat or attachments operation URL.'
}

if (-not $MSBuildPath) {
    $command = Get-Command MSBuild.exe -ErrorAction SilentlyContinue
    if ($command) {
        $MSBuildPath = $command.Source
    }
    else {
        $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
        if (Test-Path -LiteralPath $vswhere) {
            $MSBuildPath = & $vswhere -latest -prerelease -products '*' -requires Microsoft.Component.MSBuild -find 'MSBuild\**\Bin\MSBuild.exe' |
                Select-Object -First 1
            if ($LASTEXITCODE -ne 0) { throw 'Visual Studio MSBuild discovery failed.' }
        }
    }
}
if (-not $MSBuildPath -or -not (Test-Path -LiteralPath $MSBuildPath)) {
    throw 'Visual Studio MSBuild was not found. Install the Commerce SDK prerequisites or supply MSBuildPath.'
}

$projects = @(
    'ScaleUnit\Contoso.PosExtensions.ScaleUnit.csproj',
    'StoreCommerce.Installer\Contoso.PosExtensions.StoreCommerce.Installer.csproj'
)
Push-Location $PSScriptRoot
try {
    foreach ($project in $projects) {
        # Installer packaging consumes POS outputs before its normal project-reference build.
        $target = if ($project.StartsWith('ScaleUnit\')) { 'Rebuild' } else { 'Build' }
        & $MSBuildPath (Join-Path $PSScriptRoot $project) /restore "/t:$target" /nologo /v:minimal `
            /p:Configuration=Release "/p:BuildNumber=$BuildNumber" `
            "/p:CommerceSdkPackagesVersion=$CommerceSdkPackagesVersion" `
            "/p:ContosoApimEndpoint=$($ApimEndpoint.AbsoluteUri.TrimEnd('/'))"
        if ($LASTEXITCODE -ne 0) { throw "Commerce extension build failed: $project" }
    }
}
finally {
    Pop-Location
}

Write-Host 'Builds completed. Use the SDK-generated deployment packages, not a ZIP of the source.'
Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'ScaleUnit\bin\Release'),
    (Join-Path $PSScriptRoot 'StoreCommerce.Installer\bin\Release') -File -Recurse |
    Where-Object { $_.Extension -in @('.zip', '.exe', '.config') } |
    Select-Object FullName, Length
