using module LIB_OperationSet
using module LIB_Project
using module LIB_Task

cd $PSScriptRoot
Clear-Host

#environment parameters
$tenant      = "axsolutionsarchitecture.com"
$environment = "https://po-demo2.crm.dynamics.com"

#data file
$projectFile = "ProjectTasks.xlsx"

#project parameters
$projectName    = "MDD_TestPS_06"
$companyName    = "USPM"
$customerName   = "Adatum Corporation"
$calendarName   = "Default Work Template"
$projectManager = "SA Solutions Architect"

[Project] $project = [Project]::new($projectName,$tenant,$environment)
if ($project.id -eq '')
{
   Write-Host 'Create project' $projectName
   $project.customerName = $customerName
   $project.calendar = $calendarName
   $project.company = $companyName
   $project.projectManager = $projectManager
   $project.CreateProject()
}


Write-Host 'Read file' $projectFile
[TaskList] $taskList = [TaskList]::new($PSSCriptRoot + ".\" + $projectFile )

Write-Host 'Create team members'
foreach ($task in $taskList.tasks)
{
   if ($task.resource -ne "")
   {
      $task.teamMemberId = $project.GetTeamMemberId($task.resource)
      if ($task.teamMemberId -eq "")
      {
         $task.teamMemberId = $project.CreateTeamMember($task.resource)
      }
   }
}

Write-Host 'Create tasks'
[OperationSet] $operationSet = [OperationSet]::new($projectName,$project.id,$tenant,$environment)
$operationSet.request.Native = $true
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
$operationSet.request.Native = $true
for ([int] $i = 0; $i -lt $taskList.tasks.Count; $i++)
{
   if ($taskList.tasks[$i].dependency -gt -1)
   {
      $dependencyEntity = $taskList.CreateDependencyEntity($i,$project.id)
      $operationSet.Create($dependencyEntity)
   }
}
$operationSet.Execute()