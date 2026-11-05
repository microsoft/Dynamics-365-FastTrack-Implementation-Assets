using module LIB_OData
Clear-Host
cd $PSScriptRoot

[string] $file = ".\secure.txt"
$username     = encrypt "<your username>"
$password     = encrypt "<your password>"
$clientId     = encrypt "<your client id>"
$clientSecret = encrypt "<your client secret>"
Out-File $file
($clientId + '-' + $clientSecret) | Add-Content $file
($username+ '-' + $password + '-' + $clientid) | Add-Content $file
Write-Host 'file' $file 'created'
