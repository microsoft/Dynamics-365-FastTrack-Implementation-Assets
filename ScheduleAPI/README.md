Powershell example for Project Operations Schedule API

Purpose : The docs article https://docs.microsoft.com/en-us/dynamics365/project-operations/project-management/schedule-api-preview describes how the Schedule API provide the ablitlity to perform create, update and delete opeations with Scheduding entities. These entities are managed through the Scheduling engine in Project for Web. 
The article also describes a console application.
With this Powershell example we demonstrate the RestAPI calls so that it easily can be used as basis in other middleware software. 

The main program, PO_ImportTasks.ps1, creates in the specified project the tasks which are describe in the data file. If the project doesn't exist it creates the project with parameters projectName, companyName, customerName, calendarName and projectManager.

The sample data file, ProjectTasks.xlsx, contains a simple WBS with one parent task and two sub taskes which are assigned to a resource. The second subtask has a dependency on the first sub task. 

The main program uses modules 
  * LIB_OData
  * LIB_OperationSet
  * LIB_Project
  * LIB_Task
( This modules need to be copied or linked under "This PC > Documents > PowerShell > Modules")

PowerShell was chosing because it is available on any Windows10 computer without the need of installing additional development tools.
Just start "Windows PowerShell ISE" and open file "PO_CreateProject.ps1" and you can start modifying parameters and run/debug the program. 

