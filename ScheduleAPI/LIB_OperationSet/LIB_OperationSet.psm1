using module LIB_OData

class OperationSet
{
   [string]      $id
   [HttpRequest] $request
   [string]      $projectName 
   [string]      $projectId
   [int]         $maxRequest = 100
   [int]         $nrRequest 

   OperationSet ([string] $projectName, [string] $projectId, [string] $tenant, [string] $environment)
   {
      $this.projectName = $projectName
      $this.projectId = $projectId
      $this.request = [HttpRequest]::new($tenant,$environment)
      $this.request.Native = $true
   }

   [void] NewSet()
   {
      $this.request.Command = 'api/data/v9.1/msdyn_CreateOperationSetV1'
      $this.request.Body = @{ 
         ProjectId   = $this.projectId
         Description = ($this.projectName + (Get-Date -Format "yyMMddhhmm") )
      }
      $this.request.Method = 'POST'
      $result = $this.request.WebCall()
      $this.id = $result.OperationSetId
      $this.nrRequest = 0
   }

   [void] Create([Object] $entity)
   {
      if ($this.id -eq $null)
      {
         $this.request.Authenticate()
         $this.NewSet()
      }
      elseif ($this.nrRequest -eq $this.maxRequest)
      {
        $this.Execute()
        $this.NewSet()
      }
      $this.request.Body = @{ 
         Entity  = $entity
         OperationSetId = $this.id
      }
      $this.request.Command = 'api/data/v9.1/msdyn_PssCreateV1'
      $this.request.Method = 'POST'
      $this.request.WebCall()
      $this.nrRequest++
   }

   [string]Execute ()
   {
      if ($this.nrRequest -eq 0)
      {
        $response = "operation set is empty"
      }
      else
      {
         $this.request.Command = 'api/data/v9.1/msdyn_ExecuteOperationSetV1'
         $this.request.Body = @{ 
            OperationSetId = $this.Id
         }
         $this.request.Method = 'POST'
         $result = $this.request.WebCall()
         [string] $response = $result.response
      
         While (!($this.OperationSetFinished()))
         {
            Write-host 'executing...'
            sleep -Seconds 10
         }
         $this.nrRequest = 0
      }
      return $response
   }

   [boolean] OperationSetFinished()
   {
      [int] $open = 192350000
      [int] $pending = 192350001
   
      $this.request.Command = 'api/data/v9.1/msdyn_operationsets(' + $this.id + ')'
      $this.request.Method = 'GET'
      $result = $this.request.WebCall()  
      [boolean] $finished = ($result.msdyn_status -ne $open -and $result.msdyn_status -ne $pending)
      return $finished
   }
}
