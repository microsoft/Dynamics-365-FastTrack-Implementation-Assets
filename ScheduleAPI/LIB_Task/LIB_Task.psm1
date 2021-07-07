class Task 
{
   [string]   $taskName
   [int]      $parent
   [double]   $effort
   [DateTime] $startDate
   [DateTime] $endDate   
   [string]   $resource
   [int]      $dependency
   [Guid]     $taskId
   [Guid]     $teamMemberId

   Task ([string] $name, [int] $parent, [int] $dependency)
   {
      $this.taskName = $name
      $this.parent = $parent
      $this.dependency = $dependency
      $this.taskId = [Guid]::NewGuid()
      $this.resource = ""
   }

   [Object] CreateTaskEntity([Guid] $projectId, [Guid] $bucketId)
   {

      $task = @{
         "@odata.type" = "Microsoft.Dynamics.CRM.msdyn_projecttask"
         "msdyn_project@odata.bind" = "/msdyn_projects(" + $projectId + ")"
         msdyn_projecttaskid = $this.taskId
         msdyn_subject = $this.taskName
         msdyn_LinkStatus = 192350000
         msdyn_tasknumber = "";
         msdyn_activitynumber = ""
         "msdyn_projectbucket@odata.bind" = "/msdyn_projectbuckets(" + $bucketId + ")"
      }   
      
      if ($this.effort -gt 0) { $task.msdyn_effort = $this.effort }
      if ($this.startDate -gt 0) { $task.msdyn_scheduledstart = $this.startDate.ToString("yyyy-MM-dd")}
      if ($this.endDate -gt 0) { $task.msdyn_scheduledend = $this.endDate.ToString("yyyy-MM-dd") }
      return $task 
   }

   [Object] CreateResourceAssignment ([string] $projectId)
   {
       $resourceAssignment = @{
         "@odata.type" = "Microsoft.Dynamics.CRM.msdyn_resourceassignment"
         "msdyn_projectid@odata.bind" = "/msdyn_projects(" + $projectId + ")"
         "msdyn_taskid@odata.bind" = "/msdyn_projecttasks(" + $this.taskId + ")"
         "msdyn_projectteamid@odata.bind" = "/msdyn_resourceassignments(" + $this.teamMemberId + ")"
         "msdyn_name" = $this.resource
      }   
      return $resourceAssignment
   }
}

class TaskList
{
   [string] $filename
   [Object] $xl
   [Object] $wb
   [Object] $ws
   [System.Collections.ArrayList] $tasks

   TaskList ([string] $filename)
   {
      $this.filename = $filename
      $this.OpenExcel()
      if ($this.CheckHeader())
      {
        $this.ImportTasks()
      }
      else
      {
         write-host 'error in header'
      }
      $this.CloseExcel()
   }

   [void] OpenExcel()
   {
      $this.xl = New-Object -COM "Excel.Application"
      $this.xl.Visible = $false
      $this.wb = $this.xl.Workbooks.Open($this.fileName)
      $this.ws = $this.wb.Sheets(1)
   }

   [void] CloseExcel()
   {
      $this.wb.Close()
      $this.xl.Quit()
      [System.Runtime.Interopservices.Marshal]::ReleaseComObject($this.xl) | Out-Null
   }

   [boolean] CheckHeader ()
   {
      [boolean] $ok = ($this.ws.Cells.Item(1, 1).Text -eq 'Nr')
      $ok = $ok -and ($this.ws.Cells.Item(1, 2).Text -eq 'TaskName')
      $ok = $ok -and ($this.ws.Cells.Item(1, 3).Text -eq 'Parent Task')
      $ok = $ok -and ($this.ws.Cells.Item(1, 4).Text -eq 'Effort')
      $ok = $ok -and ($this.ws.Cells.Item(1, 5).Text -eq 'Scheduled Start')
      $ok = $ok -and ($this.ws.Cells.Item(1, 6).Text -eq 'Scheduled End')
      $ok = $ok -and ($this.ws.Cells.Item(1, 7).Text -eq 'Resource')
      $ok = $ok -and ($this.ws.Cells.Item(1, 8).Text -eq 'Dependency')
      return $ok
   }

   [void] ImportTasks()
   {
      $this.tasks = New-Object -TypeName System.Collections.ArrayList
      [int] $row = 2
      while ($this.ws.Cells.Item($row, 1).Text -ne '')
      {
         [string] $taskName = $this.ws.Cells.Item($row, 2).Text.Trim()
         [int] $parent = -1;
         [int] $dependency = -1;
         if ($this.ws.Cells.Item($row, 3).Text.Trim() -ne '')
         {
            $parent = $this.ws.Cells.Item($row, 3).Text
         } 
         if ($this.ws.Cells.Item($row, 8).Text.Trim() -ne '')
         {
            $dependency = $this.ws.Cells.Item($row, 8).Text
         } 
         [Task] $task = [Task]::new($taskName,$parent,$dependency)
         
         if ($this.ws.Cells.Item($row, 4).Text.Trim() -ne '')
         {
             $task.effort = $this.ws.Cells.Item($row, 4).Text
         }
         if ($this.ws.Cells.Item($row, 5).Text.Trim() -ne '')
         {
             $task.startDate = $this.ws.Cells.Item($row, 5).Text
         }
         if ($this.ws.Cells.Item($row, 6).Text.Trim() -ne '')
         {
             $task.endDate = $this.ws.Cells.Item($row, 6).Text
         }
         if ($this.ws.Cells.Item($row, 7).Text.Trim() -ne '')
         {
             $task.resource = $this.ws.Cells.Item($row, 7).Text
         }
         $this.tasks.Add($task)
         $row++
      }
   }

   [Object] CreateTaskEntity([int] $taskNr, [Guid] $projectId, [Guid] $bucketId)
   {
      $task = $this.tasks[$taskNr].CreateTaskEntity($projectId,$bucketId)
      $parent = $this.tasks[$taskNr].parent
      if ( $parent -eq -1)
      {
         $task.msdyn_outlinelevel = 1
         write-host $taskNr '-' $this.tasks[$taskNr].taskName '-' $this.tasks[$taskNr].taskId
      } 
      else
      {
         $task."msdyn_parenttask@odata.bind" = "/msdyn_projecttasks(" + $this.tasks[$parent - 1].taskId + ")"
         write-host $taskNr '-' $this.tasks[$taskNr].taskName '-' $this.tasks[$taskNr].taskId '-' $this.tasks[$parent - 1].taskId 
      }
      return $task
   }

   [Object] CreateDependencyEntity([int] $taskNr,[Guid] $projectId)
   {
      $task = $this.tasks[$taskNr]
      [Guid] $predecessor = $this.tasks[$task.dependency -1].taskId
      [Guid] $successor = $task.taskId

      $dependency = @{
         "@odata.type" = "Microsoft.Dynamics.CRM.msdyn_projecttaskdependency"
         "msdyn_Project@odata.bind" = "/msdyn_projects(" + $projectId + ")"
         "msdyn_PredecessorTask@odata.bind" = "/msdyn_projecttasks(" + $predecessor + ")"
         "msdyn_SuccessorTask@odata.bind" = "/msdyn_projecttasks(" + $successor + ")"
         "msdyn_linktype" = 192350000
      } 
    
      return $dependency
   }
}
