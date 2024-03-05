function encrypt ([string] $plain)
{
   $encrypt = $plain | ConvertTo-SecureString -AsPlainText -Force | ConvertFrom-SecureString 
   return $encrypt
}

function decrypt ([string] $encrypted)
{
   [SecureString] $secure = ( $encrypted | ConvertTo-SecureString)
   return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

class HttpRequest
{
   [string] $Tenant
   [string] $Resource
   [string] $Method
   [string] $Command
   [boolean]$Debug
   [System.Collections.IDictionary]$Header
   [PSCustomObject]$Body
   [Boolean] $Native
   [Credentials] $Credentials

   HttpRequest ( [string] $Tenant, [string] $Resource )
   {
      $this.Tenant = $Tenant
      $this.Resource = $Resource
      $this.Method = "GET"
      $this.Debug = $false
      $this.Native = $false
   }

   [void] Authenticate ()
   {
      $this.Credentials = [Credentials]::new($this.Native)
      $this.AADLogin()

   }
 
   [void] Login ()
   {
      $DefaultProfile = Connect-AzAccount -Tenant $this.Tenant
      $bearer = (Get-AzAccessToken -ResourceUrl $this.Resource -DefaultProfile $DefaultProfile)
      $this.Header = @{ Authorization = "Bearer " + $bearer.token }
      if ($this.Debug)
      {
          Write-Host "AAD interactive login :" $bearer.UserId
      }
   }

   [object] WebCall ()
   {
      $response = $null

      [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
   
      $cmd = $this.Resource + '/' + $this.Command
      if ($this.Debug) { write-host $this.Method $cmd}
      if ($this.Body -eq $null) {
         $httpBody = ''
      } else {
         $httpBody = ($this.Body | ConvertTo-Json)
         if ($this.Debug -and $this.Method -ne 'GET')
         {
            write-host $httpbody
         }
      }
      switch ($this.Method)
      {
         'GET'    { $response = Invoke-RestMethod -Uri $cmd -Method GET    -Headers $this.Header -ContentType application/json }
         'POST'   { $response = Invoke-RestMethod -Uri $cmd -Method POST   -Headers $this.Header -Body $httpBody -ContentType application/json }
         'PATCH'  { $response = Invoke-RestMethod -Uri $cmd -Method PATCH  -Headers $this.Header -Body $httpBody -ContentType application/json}
         'DELETE' { $response = Invoke-RestMethod -Uri $cmd -Method DELETE -Headers $this.Header -ContentType application/json}
         default  { Write-Host 'unknown method : ' $this.Method }
      }
      return $response
   }

   [void] AADLogin()
   {
      if ($this.native)
      {
          $creds = @{
            grant_type = "password"
            client_id = decrypt($this.Credentials.ClientId)
            username = decrypt($this.Credentials.key)
            password = decrypt($this.Credentials.value)
            resource = $this.Resource
         }
      } else {
         $creds = @{
            grant_type = "client_credentials"
            client_id = decrypt($this.credentials.key)
            client_secret = decrypt($this.credentials.value)
            resource = $this.Resource
         }
      }
      $AADLogin = "https://login.microsoftonline.com/" + $this.tenant + "/oauth2/token" 
      if ($this.Debug) 
      { 
         Write-Host "AAD:" $AADLogin (decrypt($this.Credentials.key))
      }
      $bearer = (Invoke-RestMethod $AADLogin -Method Post -Body $creds)
      $this.Header = @{ Authorization = "Bearer " + $bearer.access_token }
   }
}

class Credentials
{
   [string] $ClientId 
   [string] $Key 
   [string] $Value 

   [string] $filename = $PSScriptRoot + "\secure.txt"

   Credentials ([boolean] $native)
   {
      $list = Get-Content $this.filename
      $found = $false
      foreach ($element in $list)
      {
         if ($found -eq $false)
         {
            $this.ReadKey($element)
            if ( $native -and ($this.ClientId -ne $null) )
            {
               $found = $true
            }
            elseif ( ($native -eq $false) -and ($this.ClientId -eq $null) )
            {
               $found = $true
            }
         }
      }
   }

   [void] ReadKey([string] $element)
   {
      [string[]] $segment = $element.Split('-')
      $this.Key = $segment[0]
      $this.Value = $segment[1]
      if ( (decrypt($segment[0])).Contains('@') )
      {
         $this.ClientId = $segment[2]
      }
   }
}


