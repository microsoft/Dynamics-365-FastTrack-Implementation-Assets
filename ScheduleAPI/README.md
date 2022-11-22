# Powershell example for Project Operations Schedule API

### Purpose
The docs article https://docs.microsoft.com/en-us/dynamics365/project-operations/project-management/schedule-api-preview describes how the Schedule API provide the ability to perform create, update and delete operations with Scheduling entities. These entities are managed through the Scheduling engine in Project for Web. 
The article also describes a console application.
With this Powershell example we demonstrate the RestAPI calls so that it easily can be used as basis in other middleware software. 

### Components
The main program, PO_ImportTasks.ps1, creates in the specified project the tasks which are described in the data file. If the project doesn't exist it creates the project with parameters projectName, companyName, customerName, calendarName and projectManager.

The sample data file, ProjectTasks.xlsx, contains a simple WBS with one parent task and two sub taskes which are assigned to a resource. The second subtask has a dependency on the first sub task. 

The main program uses modules 
  * LIB_OData
  * LIB_OperationSet
  * LIB_Project
  * LIB_Task

PowerShell was chosen because it is available on any Windows10 computer without the need of installing additional development tools.

### Installation Steps

1) Download the zip file via the green button "Code" on Dynamics-365-FastTrack-Implementation-Assets
2) Extract files make (sure the set switch "Unblock" on the properties from the zip file)
3) Move the directories LIB_OData, LIB_OperationSet, LIB_Project and LIB_TASK from ScheduleAPI under ThisPC > Documents > WindowsPowerShell > Modules. You can manually create directory WindowsPowerShell and/or Modules if these directories are not on your machine.
4) File PO_ImportTasks.ps1 can be saved to any location
5) Setup authentication as described in the README.md file in LIB_Odata. Note that you will be using the native authentication flow (therefore requiring an AAD application client ID, username and password, but not a client secret), due to the current limitation that the Schedule APIs can only be used by Users with a Microsoft Project License.
6) Use "Windows PowerShell ISE" program to open file "PO_CreateProject.ps1" and you start verifying / modifying parameters 
   Environment parameters
    * tenant
    * environment : 

   Project parameters
    * project name
    * company name
    * customer name 
    * calendar name
    * project manager
   
   Data File 
    * project File (if you want to have different sample files). Please review data adn update in your project file (e.g. resource, start and end dates).
