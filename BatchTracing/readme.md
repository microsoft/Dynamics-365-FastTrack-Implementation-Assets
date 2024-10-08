# Batch Tracing Tool
The batch tracing tool adds in additional functionality to captures traces from batch processing. It supports single to multi-server batch setups. This document describes how to install and use the tool. 

## Revision History
v1.0 - Initial Release

## Disclaimer
This application is freeware and is provided on an "as is" basis without warranties of any kind, whether express or implied, including without limitation warranties that the code is free of defect, fit for a particular purpose or non-infringing.  The entire risk as to the quality and performance of the code is with the end use.
## Installation
Under the Metadata folder download the **SABatchTracing** folder and copy into your **PackagesLocalDirectory** folder (Cloud Hosted Environments) or for UDE (Unified Development Experience) to the custom metadata folder you specified. 
Is you wish you can then also copy the **SABatchTracing** Visual Studio solution and project files from the **Project** folder to your repos folder.
Build and deploy as per your normal release processes.
##  How it Works
The batch tracing tool relies on a batch job to start and stop the traces. The tracing is built upon the same framework as the interactive tracing you are familiar with for client traces.
Due to the batch priority scheduling framework, there is no way to force a task on each batch server. Therefore, the tracing batch job will create a high number of batch tasks to ensure a task gets run on each batch server. Once a tracing task is running on a server, any subsequent tasks that may get picked up will end immediately. Initially there is a bundle of tasks that is started, if after that initial bundle there are batch servers that haven’t picked up a tracing task, then the batch job will create another bundle of tasks. Once the maximum number of tasks have been met, no more tasks will be created. It would be expected that within the few bundles all batch servers have started the tracing task. The bundle size and max number of tasks can be set in the parameters form, see notes later in this document.
The batch job running does not mean a trace is running. The tracing tasks are polling a table to see if tracing has been requested to start or stop. 

## Usage
From the Microsoft D365 Finance and Operation click on; **Help and Support (?) > Trace > Batch Tracing**
When you first open the Batch Tracing form, the status will be **Not Read**
### Starting Tracing
Before you can start a trace, you need to start the **Tracing Batch Job**. To do this select the **Batch Tracing  Menu > Start Batch Tracing Batch Job**.
Once the batch job has started, the status will change from **Not Ready** to **Stopped**
> [!NOTE]  
> It can take some time for the status to change to **Stopped** after the batch job has started. This can depend on the number of batch servers.

With the status in a **Stopped** state, select the **Batch Tracing > Menu Start Tracing**.
This will update the status to **Start Requested**, and shortly after the status will change to **Starting** then **Started** or **Partially Started**. 
> [!NOTE]  
> **Partially Started**, means that the trace task couldn’t be started on some of the batch servers. See the troubleshooting section below on how to prevent this. 
You can refresh the form while the trace is running to see the status and file size.

> [!NOTE]  
> If there is more than one batch server then the file size shown is the average of the traces over the servers.

### Stopping Tracing
You can stop a started or partially started trace by selecting **Batch Tracing  Menu > Stop Tracing**.
This will update the status to **Stop Requested**, and shortly after the status will change to **Stopping** then **Uploading** then **Stopped**.
You can refresh the form while the trace is running to see the status and file size. 
> [!NOTE]  
> If there is more than one batch server then the file size shown is the average of the traces over the servers.

### Downloading Traces
Completed traces can be viewed and downloaded from: **Batch Tracing  Menu > Captured Traces**.
### Starting and Stopping the Tracing Batch Job
The batch tracing tool relies on a batch job to start and stop the traces, see notes in the **How it Works** section. This batch job must be running before you can start and stop traces. 
To start the batch job: **Batch Tracing  Menu > Start Batch Tracing Batch Job**
To stop the batch job: **Batch Tracing  Menu > Stop Batch Tracing Batch Job**
> [!NOTE]  
> Starting the batch job does not start a trace. It just provides the mechanism on the batch servers to start and stop traces when needed.

Once you have finished tracing and no longer require to capture any more traces, then you can stop the batch job.

### Parameters
There are several parameters that can be set for the batch tracing. To open the parameters form **Batch Tracing  Menu > Batch Tracing Parameters**.
The parameters are outlined below:
 
#### General Parameters for Batch Tracing
 - Include SQL parameter values: As per the client tracing, will capture SQL parameter values in the trace.
 - Stop Tracing After (Mins): Trace will stop after the time set here
 - Max Trace File Size (MB): Trace will stop once the file size has been set. 
> [!NOTE]  
> The trace will stop based on which metric is met first between file size and time. 

 - Stop Batch Job After (Hours): Will automatically stop the batch tracing batch job after the number of hours set here. This can be useful if you forget to stop the job manually.
 - Tasks per Bundle: Set the number of tasks be bundle that get created in the batch job. Once a tracing batch task is created on each batch server, then no further bundles will be needed.
 - Max Batch Tasks: To prevent the batch job from continually throwing out batch tasks, it will stop once this maximum value is set.
 - Sort Traces by Date Desc: The captured traces form does not automatically sort by date descending. Even adding in a personalization to save an order on the grid does not work. Turning this switch on means that the captured traces form is sorted by trace stop time descending.
#### Advanced Parameters for Batch Tracing
 - Min Trace File Size Limit (MB): Information only, not adjustable. 
 - Max Trace File Size Limit (MB): Information only, not adjustable.
 - Default Trace File Size (MB): Information only, not adjustable.
 - Delay between bundles (Secs): This is the delay between bundles of tasks being created. 
 - Polling for Start/Stop (Secs): The polling frequency for the batch tasks to check for when tracing is started or stopped. 
 - Scheduling Priority is overridden: Set this on to override the default scheduling priority for the tracing batch job.
 - Scheduling Priority: If the ** Scheduling Priority is overridden** is on, then you can adjust the priority to one of the following - Low, Normal, High, Critical, Reserved Capacity. This can be useful if you have other batch jobs running but need to force the batch tracing job to run. For reserved capacity see: [Priority-based batch scheduling - Set the batch reserved capacity level](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/sysadmin/priority-based-batch-scheduling#set-the-batch-reserved-capacity-level)
 - Reset All Setting: If you are having issues with the statuses not updating for tracing, you can click this button to reset the tracing data and parameters. 
> [!NOTE]  
> A check is made to ensure the tracing batch job is stopped before the Reset All Settings can be run. 
 

## Troubleshooting
### Statuses not Updating
Issue: You find that the statues are not updating as expected in the batch tracing form.

Solution: Stop (is running) the batch tracing job. Go into Batch Tracing Parameters, and in the Advanced tab, click Reset All Settings
### Partially Started Status
Issue: After stating the trace, you find that the status in the batch tracing form only shows Partially Started.

Cause: There can be a couple of causes for this: 
 - A batch server couldn’t start a batch tracing task as it was busy with other tasks.
 - There are old servers still referenced in the Server Configuration for. This issue only occurs if you’ve migrated from D365 On-Premises (LBD), imported data from a development environment or have upgraded from AX 2012.
   
Solutions:
 - Increase the maximum number of tasks, this can be set in the Batch Tracing Parameters in **Max Batch Tasks**
 - Change the priority scheduling. In the Batch Tracing Parameters, on the Advanced tab, turn on the ** Scheduling Priority is overridden** and set the priority in the dropdown to high, critical or reserved capacity. 
 - Check for redundant old servers in the Server Configuration form: Go to – System Administration > Setup > Server configuration. Remove old LBD, Development or AX2012 AOS servers referenced. 


