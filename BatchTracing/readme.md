# Batch Tracing Tool
The batch tracing tool allow you to capture traces from batch. It supports single to multi-server batch setups. This document desribes how to install and use the tool. 

## Revision History
v1.0 - Initial Release

## Disclaimer
This application is freeware and is provided on an "as is" basis without warranties of any kind, whether express or implied, including without limitation warranties that the code is free of defect, fit for a particular purpose or non-infringing.  The entire risk as to the quality and performance of the code is with the end use.
## Installation
Under the Metadata folder download the **SABatchTracing** folder and copy into your PackagesLocalDirectory folder (Cloud Hosted Environments) or for UDE (Unified Development Experience) to the custom metadata folder you specified. 
Is you wish you can then also copy the **SABatchTracing** Visual Studio solution and project files from the **Project** folder to your repos folder.
Build and deploy as per your normal release processes.

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


