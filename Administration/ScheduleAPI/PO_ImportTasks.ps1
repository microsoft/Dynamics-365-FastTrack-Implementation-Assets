using module LIB_OperationSet
using module LIB_Project
using module LIB_Task

cd $PSScriptRoot
Clear-Host

#environment parameters
$tenant      = "axsolutionsarchitecture.com"
$environment = "https://operations-saprojopstest.crm.dynamics.com"

#data file
$projectFile = "ProjectTasks.xlsx"

#Show RestAPI calls
$showRestAPI = $true

#project parameters
$projectName    = "MAW_TestPS01"
$companyName    = "USPM"
$customerName   = "MW Test Customer 2"
$calendarName   = "8 hr PST template"
$projectManager = "SA Solutions Architect"
$startDate      = "2022-11-23 17:00"

[Project] $project = [Project]::new($projectName,$tenant,$environment)
$project.request.Debug = $showRestAPI
if ($project.id -eq '')
{
   Write-Host 'Create project' $projectName
   $project.customerName = $customerName
   $project.calendar = $calendarName
   $project.company = $companyName
   $project.projectManager = $projectManager
   $project.startDate = $startDate
   $project.CreateProject()
}
else
{
   Write-Host 'Add to existing project' $projectName
}

Write-Host 'Read file' $projectFile
[TaskList] $taskList = [TaskList]::new($PSSCriptRoot + ".\" + $projectFile )

Write-Host 'Create team members'
foreach ($task in $taskList.tasks)
{
   if ($task.resource -ne "")
   {
      [string]$teamMemberId = $project.GetTeamMemberId($task.resource)      
      if ($teamMemberId -eq "")
      {
         $task.teamMemberId = $project.CreateTeamMember($task.resource)
      }
      else
      {
         $task.teamMemberId = $teamMemberId
      }
   }
}

Write-Host 'Create tasks'
[OperationSet] $operationSet = [OperationSet]::new($projectName,$project.id,$tenant,$environment)
$operationSet.request.Debug = $showRestAPI
for ([int] $i = 0; $i -lt $taskList.tasks.Count; $i++)
{
   $taskEntity = $taskList.CreateTaskEntity($i,$project.id,$project.GetDefaultBucket())
   $operationSet.Create($taskEntity)
}

foreach ($task in $taskList.tasks)
{
   if ($task.resource -ne "")
   {
      $resourceEntity = $task.CreateResourceAssignment($project.id)
      $operationSet.Create($resourceEntity)
   }
}
$operationSet.Execute()

write-Host 'Create dependencies'
[OperationSet] $operationSet = [OperationSet]::new($projectName,$project.id,$tenant,$environment)
$operationSet.request.Debug = $showRestAPI
for ([int] $i = 0; $i -lt $taskList.tasks.Count; $i++)
{
   if ($taskList.tasks[$i].dependency -gt -1)
   {
      $dependencyEntity = $taskList.CreateDependencyEntity($i,$project.id)
      $operationSet.Create($dependencyEntity)
   }
}
$operationSet.Execute()
