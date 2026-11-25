function Assert-CustomerIdentityConfiguration {
    param(
        [Parameter(Mandatory = $true)]
        [object]$ParameterDocument
    )

    $enabledIssuers = @()
    $commerceIssuer = $ParameterDocument.parameters.commerceTokenIssuer.value
    if (!$commerceIssuer -and $ParameterDocument.parameters.retailServerBaseUrl.value) {
        $issuerPath = $ParameterDocument.parameters.commerceIssuerPath.value
        if ($null -eq $issuerPath) { $issuerPath = "auth" }
        $commerceIssuer = $ParameterDocument.parameters.retailServerBaseUrl.value.TrimEnd("/") + "/" + $issuerPath
    }

    foreach ($provider in @("b2c", "externalId")) {
        $enabled = $ParameterDocument.parameters."${provider}Enabled".value
        if ($null -eq $enabled) { continue }
        if ($enabled -isnot [bool]) {
            throw "${provider}Enabled must be a JSON boolean."
        }
        if (!$enabled) { continue }

        foreach ($suffix in @("OpenIdConfigUrl", "TokenIssuer", "TokenAudience")) {
            $name = "$provider$suffix"
            $value = $ParameterDocument.parameters.$name.value
            if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value) -or $value -eq "__not-configured__") {
                throw "$name must be configured when ${provider}Enabled is true."
            }
            if ($value -ne $value.Trim() -or $value -match '["\\<>&''\s]') {
                throw "$name must not contain whitespace, quotes, backslashes or XML delimiters."
            }
            if ($suffix -ne "TokenAudience") {
                $uri = $null
                if (![Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -or
                    $uri.Scheme -ne "https" -or !$uri.IsWellFormedOriginalString() -or
                    !$uri.Host -or $uri.Host -eq "identity.invalid" -or $uri.UserInfo -or $uri.Fragment) {
                    throw "$name must be an absolute HTTPS URL for the trusted identity provider."
                }
                if ($suffix -eq "TokenIssuer" -and $uri.Query) {
                    throw "$name must not contain a query."
                }
            }
        }

        $issuer = $ParameterDocument.parameters."${provider}TokenIssuer".value
        if ($enabledIssuers -ccontains $issuer) {
            throw "Enabled customer providers must have distinct issuers."
        }
        if ($issuer -ceq $commerceIssuer -or
            $issuer -match '^https://(sts\.windows\.net|login\.microsoftonline\.com)/') {
            throw "${provider}TokenIssuer must not overlap the existing Commerce or workforce Entra issuer."
        }
        $enabledIssuers += $issuer

        $scope = $ParameterDocument.parameters."${provider}RequiredScope".value
        if ($null -ne $scope -and ($scope -isnot [string] -or $scope -notmatch '\A[A-Za-z0-9._:/-]+\z')) {
            throw "${provider}RequiredScope must be a single permission name, or __not-configured__."
        }
    }

    if ($ParameterDocument.parameters.b2cEnabled.value -eq $true) {
        $claim = $ParameterDocument.parameters.b2cPolicyClaim.value
        if ($null -ne $claim -and $claim -cnotin @("tfp", "acr")) {
            throw "b2cPolicyClaim must be tfp or acr."
        }
        $policy = $ParameterDocument.parameters.b2cPolicy.value
        if ($null -ne $policy -and ($policy -isnot [string] -or $policy -notmatch '\A[A-Za-z0-9._-]+\z')) {
            throw "b2cPolicy must be a policy name, or __not-configured__."
        }
    }

    $origin = $ParameterDocument.parameters.c2Origin.value
    if ($null -ne $origin -and $origin -cne "*") {
        $uri = $null
        if ($origin -isnot [string] -or ![Uri]::TryCreate($origin, [UriKind]::Absolute, [ref]$uri) -or
            $uri.Scheme -ne "https" -or !$uri.IsWellFormedOriginalString() -or !$uri.Host -or
            $uri.UserInfo -or $uri.Query -or $uri.Fragment -or $uri.AbsolutePath -ne "/" -or
            $origin.EndsWith("/") -or $origin -match '[\s*]') {
            throw "c2Origin must be an exact HTTPS browser origin without a trailing slash or path, or * for explicitly unrestricted non-credentialed CORS."
        }
    }
}

function ConvertTo-CustomerIdentityCorsPolicy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Policy,

        [Parameter(Mandatory = $true)]
        [object]$ParameterDocument
    )

    if ($ParameterDocument.parameters.c2Origin.value -cne "*") { return $Policy }

    [xml]$document = $Policy
    $cors = $document.SelectSingleNode("/policies/inbound/cors")
    if ($null -eq $cors -or $cors.GetAttribute("allow-credentials") -ne "false") {
        throw "Wildcard CORS requires an inbound cors policy with allow-credentials=false."
    }
    $origins = $cors.SelectSingleNode("allowed-origins")
    if ($null -eq $origins) { throw "The CORS policy is missing allowed-origins." }
    $origins.RemoveAll()
    $origin = $document.CreateElement("origin")
    $origin.InnerText = "*"
    [void]$origins.AppendChild($origin)
    return $document.OuterXml
}
