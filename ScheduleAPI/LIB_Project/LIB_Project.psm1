using module LIB_OData

class Project
{
   [HttpRequest] $request 
   [string]      $id
   [string]      $projectName
   [string]      $customerName
   [string]      $calendar
   [string]      $company 
   [string]      $projectManager
   [string]      $startDate

   Project ([string] $projectName,$tenant,$environment)
   {
      $this.request = [HttpRequest]::new($tenant,$environment)
      $this.request.Authenticate()
      $this.projectName = $projectName
      $this.GetProjectId()
      $this.customerName = ""
      $this.calendar = ""
      $this.projectManager = ""
      $this.startDate = ""
   }

   [void] GetProjectId ()
   {
      $this.request.Command  = 'api/data/v9.1/msdyn_projects?$select=msdyn_projectid'
      $this.request.Command += '&$filter=msdyn_subject eq ''' + $this.projectName + ''''
      $this.request.Method = 'GET'
      $this.id = $this.request.WebCall().value.msdyn_projectid
   }

   [void] CreateProject()
   {
      $project = @{
         msdyn_subject                       = $this.projectName
         msdyn_description                   = $this.projectName
      }
      $this.request.Method = "GET"
      if ($this.customerName -ne "")
      {
         $this.request.Command = 'api/data/v9.1/accounts?$select=accountid&$filter=name eq ''' + $this.customerName + ''''
         $customerRef = $this.request.WebCall().value.accountId
         $project."msdyn_customer@odata.bind" = "/accounts(" + $customerRef + ")"
      }
      if ($this.calendar -ne "")
      {
         $this.request.Command = 'api/data/v9.1/msdyn_workhourtemplates?$select=msdyn_workhourtemplateid&$filter=msdyn_name eq ''' + $this.calendar + ''''
         $workhourtemplateRef = $this.request.WebCall().value.msdyn_workhourtemplateid
         $project."msdyn_workhourtemplate@odata.bind" = "/msdyn_workhourtemplates(" + $workhourtemplateRef + ")"
      }
      if ($this.company -ne "")
      {
          $this.request.Command = 'api/data/v9.1/cdm_companies?$select=cdm_companyid&$filter=cdm_companycode eq ''' + $this.company + ''''
          $companyRef =  $this.request.WebCall().value.cdm_companyid
          $project."msdyn_OwningCompany@odata.bind"    = "/cdm_companies(" + $companyRef + ")"
      }
      if ($this.projectManager -ne "")
      {
          $this.request.Command = 'api/data/v9.1/systemusers?$select=systemuserid&$filter=fullname eq ''' + $this.projectManager + ''''
          $projectManagerRef = $this.request.WebCall().value.systemuserid
          $project."msdyn_projectmanager@odata.bind"   = "/systemusers(" + $projectManagerRef +")"
      }
      if ($this.startDate -ne "")
      {
         $project.msdyn_scheduledstart = $this.startDate
      }
      $this.request.Command = 'api/data/v9.1/msdyn_CreateProjectV1'
      $this.request.Body = @{ Project = $project }
      $this.request.Method = 'POST'
      $result = $this.request.WebCall()
      $this.id = $result.ProjectId
   }

     
   [string] GetDefaultBucket ()
   {
      $this.request.Command = 'api/data/v9.1/msdyn_projectbuckets?$select=msdyn_projectbucketid,msdyn_project,msdyn_name'
      $this.request.Command += '&$filter=_msdyn_project_value eq ' + $this.id + ' and msdyn_name eq ''Bucket 1'''
      $this.request.Method = 'GET'
      $response = $this.request.WebCall()
      return $response.value[0].msdyn_projectbucketid
   }
      
   [string] GetTeamMemberId ([string] $teamMemberName)
   {
      [string]$teamMemberId = ""
      [string]$bookableresource = $this.GetBookableResource($teamMemberName)
      if ($bookableresource -ne "")
      {
         $this.request.Method = "GET"
         $this.request.Command = 'api/data/v9.1/msdyn_projectteams?$select=msdyn_name,msdyn_projectteamid&$filter=_msdyn_project_value eq ' + $this.id  
         $this.request.Command += ' and _msdyn_bookableresourceid_value eq ' + $bookableresource 
         $result = $this.request.WebCall()
         if ($result.value.Count -eq 1) {$teamMemberId = $result.value.msdyn_projectteamid }
      }
      return $teamMemberId
   }

   [string] CreateTeamMember ([string] $teamMemberName)
   {
      [string] $teamId = $this.GetBookableResource($teamMemberName)
      if ($teamId -eq "")
      {
         $teamMember = @{
            msdyn_name                    =  $teamMemberName
            "msdyn_project@odata.bind"    = "/msdyn_projects(" + $this.id + ")"
         }
      } 
      else
      {
         $teamMember = @{
            msdyn_name                    =  $teamMemberName
            "msdyn_project@odata.bind"    = "/msdyn_projects(" + $this.id + ")"
            "msdyn_bookableresourceid@odata.bind" = "/bookableresources(" + $teamId + ")"
         }
      }

      $this.request.Command = 'api/data/v9.1/msdyn_CreateTeamMemberV1'
      $this.request.Body = @{ TeamMember = $teamMember }
      $this.request.Method = 'POST'
      $result = $this.request.WebCall()
      return $result.TeamMemberId
   } 

   [string] GetBookableResource([string] $name)
   {
      [string] $resourceId = ""

      $this.request.Method = "GET"
      $this.request.Command = 'api/data/v9.1/bookableresources?$select=bookableresourceid&$filter=name eq ''' + $name + "'"
      $result = $this.request.WebCall()
      if ($result.value.count -eq 1) 
      {
         $resourceId = $result.value.bookableresourceid
      }
      return $resourceId
   }
}
