# Overview 
CDMUtil solution is client tool based on [CDM SDK](https://github.com/microsoft/CDM/tree/master/objectModel/CSharp) to read and convert CDM metadata as TSQL DDL statements for Synapse Analytics. 
It can also convert SQL Server Table metadata as CDM metadata in Azure Data lake. CDMUtil can be deployed as Azure Function App or local console app to help with following scenarios:

## Create T-SQL metadata on Synapse Analytics from CDM metadata: 
Convert CDM metadata to TSQL DDL statements and execute DDL on Synapse Analytics. You can use CDMUtil reader functions to read the CDM metadata created by Dynamics 365 Export to Data Lake feature to automatically create view or external tables on Synapse Analytics. 
Following diagram shows high level concept of the scenario.  
 ![Cdmreader](cdmreader.png)
## Export SQL server tables data to Azure data lake in CDM format:
Convert SQL server table metadata into CDM format and write cdm.json and manifest.cdm.json into Azure data lake. You can utilize CDMUtil writer functions with Azure data factory/Synapse pipeline to Export SQL Server tables data to data lake in CDM format (Use copy activity to copy table data and CDMUtil to create CDM metadata).

![Cdmwriter](cdmwriter.png)

# Deploy CDMUtil as Function App 
To atomate reading and writing of CDM metadata, CDMUtil can be deployed as function App. Follow the steps bellow to deploy and configure

## Prerequisites
To deploy and use the CDMUtil solution to Azure, following pre-requisites are required
1. Azure subscription. You will require contributor access to an existing Azure subscription. If you don't have an Azure subscription, create a free Azure account before you begin.
2. Install Visual Studio 2019: to build and deploy C# solution as Azure function App (Download and .NET46 framework install https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net462-developer-pack-offline-installer)
3. Create Synapse Analytics Workspace** [create synapse workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/quickstart-create-workspace) 

## Deployment steps
Deploy the CDMUtil solution as Azure function to automate end to end process of creating or updating metadata on Synapse Analytics. 
1. **Install Visual Studio 2019**: to build C# solution you need to Download and Install Visual Studio 2019 and .NET46 framework install https://dotnet.microsoft.com/download/dotnet-framework/thank-you/net462-developer-pack-offline-installer)
2.	Clone the repository [Dynamics-365-FastTrack-Implementation-Assets](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets)
![Clone](/Analytics/CloneRepository.PNG)
3. Open C# solution Microsoft.CommonDataModel.sln in Visual Studio 2019 and build
4.	Publish the CDMUtil_AzureFunctions Project as Azure function 
    1. Right-click on the project CDMUtil_AzureFunctions from Solution Explorer and select "Publish". 
    2. Select Azure as Target and selct Azure Function Apps ( Windows) 
    3. Click Create new Azure Function App and select subscription and resource group to create Azure function app 
    4. Click Publish ![Publish Azure Function](/Analytics/DeployAzureFunction.gif)

## Configuration and access control 
### Enable MSI
1. Open Azure Portal and locate Azure Function App created.
2. ***Enable MSI*** go to Identity tab enable [System managed identity](/Analytics/EnableMSI.PNG) 

### Update configuration 
1. In Azure portal, function app click on configuration and add following new application settings  a

| Name           |Description |Example Value  |
| ----------------- |:---|:--------------|
|TenantId          |Azure active directory tenant Id |979fd422-22c4-4a36-bea6-xxxxx|
|SQLEndPoint    |Synapse SQL Pool endpoint connection string. If Database name is not specified - create new database, if userid and password are not specified - MSI authentication will be used.   |Server=ftd365synapseanalytics-ondemand.sql.azuresynapse.net; 

![Applicationsetting](applicationsetting.png)

2. (Optional) additional optional configuration that can be provided to overide the default values can be found under CDMUTIL parameters details section bellow   

### Grant access control 
#### Storage account 
To Read and Write CDM metadata to storage account, function app must have Blob Data Reader and Blob Data Contributor access.
1. In Azure portal, go to Storage account and grant Blob Data Contributor and Blob Data Reader access to current user 
2. In case solution is Deployed as Azure Function Apps, you must enable ***System managed identity*** and grant MSI app Blob Data Contributor and Blob Data Reader access 
![Storage Access](/Analytics/AADAppStorageAccountAccess.PNG)

#### Synapse Analytics 
To execute DDL statement on synapse analytics, you can either use sql user authentication or MSI authentication. To use MSI authentical, connect to Synapse Analytics and run following script 
```SQL
-- MSI user can only be added when you are connected to Synapse SQL Pool Endpoint using AAD login 

--Option 1: Grant MSI Server level access on Synapse Analytics SQL Pool 
CREATE LOGIN YourFunctionAppName FROM EXTERNAL PROVIDER;
ALTER SERVER ROLE  sysadmin  ADD MEMBER [YourFunctionAppName];

--Option 2 :Grant MSI DB level access on Synapse Analytics SQL Pool. 
--If you grant DB level access then you must create DB and specify Databasename in the FunctionApp configuration  
use YourDBName
Create user [YourFunctionAppName] FROM EXTERNAL PROVIDER;
alter role db_owner Add member [YourFunctionAppName]
```

# Using CDMUTIL

CDMUtil can be used in following way

## 1. Azure function App with integrated storage events (EventGrid) 
For complete automation, CDMUtil EventGrid triiger can be used to react on blob created (cdm.json) and create views/external table on Synapse Analytics. 
 
### Create storage event subscription
1. In Azure portal, go to storage account , click on Events > + Event Subscription to create a new event subscription
2. Give a name and select Azure function app eventGrid_CDMToSynapseView as endpoint.
![Create Event Subscription](createEventSubscription.png)
3. Click of Filters and update event filters as following 
  a.  Enable subject filters
  * **Subject begin with**: /blobServices/default/containers/dynamics365-financeandoperations/blobs/***environment***.sandbox.operations.dynamics.com/Tables
  * **Subject ends with**: .cdm.json
  b. Advance filters
  * **Key**: data.url **Operator**:string does not ends with **Value**:.manifest.cdm.json 
  * **Key**: data.url **Operator**:string does not contain **Value**:/resolved/
  * **Key**: data.url **Operator**:string does not contain **Value**:/ChangeFeed/
  
![Events Filters](EventsFilters.png)

4. Using Finance and Operations, add tables to Export to data lake service. 
5. Cdm.json files gets created, storage event trigers the Function App 
6. Function app reads the CDM metadata and generate and execute TSQL DDL on Synapse.   

## 2. Azure function App with HTTP Events or localy using Visual Studio 
CDMUtil function app HTTP events can be triggered from client application such as ADF/Synapse pipeline, LogicApp, Power Automate or PostMan 
Following HTTP events are available.

|Function name| Description           
|--| ----------------- |
|manifestToSQL| Read cdm metadata, generate TSQL and execute on Synapse endpoint  |
|manifestToSQLDDL| Read cdm metadata, generate TSQL and return metadata  |
|getManifestDefinition|generate manifest definition path |
|createManifest|create CDM metadata |


## 3. CDMUtil Console App 
For simple POC scenario you can execute the CDMUtil solution as a Console Application and create view or external table on Synapse Serverless SQL Pool.
1. Download the Console Application executable [CDMUtilConsoleApp.zip](/Analytics/CDMUtilSolution/CDMUtilConsoleApp.zip)
2. Extract the zip file and extract to local folder 
3. Open CDMUtil_ConsoleApp.dll.config file and update the parameters as per your setup

```XML
<?xml version="1.0" encoding="utf-8" ?>
<configuration>
  <appSettings>
   <add key="TenantId" value="00000000-86f1-41af-91ab-0000000" />
    <add key="AccessKey" value="YourStorageAccountAccessKey" />
    <add key="ManifestURL" value="https://youradls.blob.core.windows.net/dynamics365-financeandoperations/yourenvvi.sandbox.operations.dynamics.com/Tables/Tables.manifest.cdm.json" />
    <add key="TargetDbConnectionString" value="Server=yoursynapseworkspace-ondemand.sql.azuresynapse.net;Database=dbname;Uid=youruser;Pwd=yourpassword" />
    <!--add key="TargetSparkConnection" value="https://yoursynapseworkspace.dev.azuresynapse.net@synapsePool@dbname" /-->
    <!--Parameters bellow are optional overide parameters/-->
    <!--add key="DataSourceName" value="d365folabanalytics_analytics" />
    <add key="DDLType" value="SynapseView" />
    <add key="Schema" value="dbo" />
    <add key="FileFormat" value="CSV" />
    <add key="DateTimeAsString" value ="true"/>
    <add key="ConvertDateTime" value ="true"/>
    <add key="TranslateEnum" value ="false"/>
    <add key="TableNames" value ="SalesTable"/>
    <add key="ProcessEntities" value ="true"/>
    <add key="CreateStats" value ="false"/>
    <add key="AXDBConnectionString" value ="Server=DBServer;Database=AXDB;Uid=youruser;Pwd=yourpassword"/-->
  </appSettings>
</configuration>
```
4. Console application will use AccessKey to read cdm files from data lake and use sql login to execute DDL on synapse sql pool.
5. To use AAD authentication with current windows user you can remove AccessKey and user id and password from connection string.
4. Run CDMUtil_ConsoleApp.exe


# Additional References

## CDMUTIL parameters details 

|Required/Optional| Name           |Description |Example Value  |
|--| ----------------- |:---|:--------------|
|R|TenantId          |Azure active directory tenant Id |979fd422-22c4-4a36-bea6-xxxxx|
|R|SQLEndPoint/TargetDbConnectionString    |Synapse SQL Pool endpoint connection string. If Database name is not specified - create new database, if userid and password are not specified - MSI authentication will be used.   |Server=yoursynapseworkspace-ondemand.sql.azuresynapse.net; 
|R|ManifestURL    |URI of the sub manifest or leaf level manifest.json or cdm.json. When using EventGrid trigger with function app, uri is retrived from event | https://youradls.blob.core.windows.net/dynamics365-financeandoperations/yourenvvi.sandbox.operations.dynamics.com/Tables/Tables.manifest.cdm.json, https://youradls.blob.core.windows.net/dynamics365-financeandoperations/yourenvvi.sandbox.operations.dynamics.com/Entities/Entities.manifest.cdm.json 
|O|AccessKey    |Storage account access key..Only needed if current user does not have access to storage account |  
|O|TargetSparkConnection    |when provided CDMUtil will create lake database that can be used with Spark as well as SQL Pool | https://yoursynapseworkspace.dev.azuresynapse.net@synapsePool@dbname
|O|DDLType          |Synapse DDLType default:SynapseView  |<ul><li>SynapseView:Synapse views using openrowset</li><li>SynapseExternalTable:Synapse external table</li><li>SynapseTable:Synapse permanent table(Refer section)</li></ul>|
|O|Schema    |schema name default:dbo | dbo, cdc 
|O|DataSourceName    |external data source name. new external ds is created if not provided | 
|O|FileFormat    |external file format - default csv file format is created if not provided |
|O|DateTimeAsString    |Openrowset csv V2 parser does not support all date time format and hence this workaround default = true | 
|O|ConvertDateTime    |Openrowset csv V2 parser does not support all date time format and hence this workaround default = true |  
|O|TranslateEnum    |default= false |   
|O|ProcessEntities    |Extract list of entities for EntityList.json file to create view on Synapse SQL Pool| default= false
|O|CreateStats    | Extract Tables and Columns names from joins and create stats on synapse| default= false
|O|TableNames    |limit list of tables to create view when manifestURL is root level |
|O|AXDBConnectionString    |AXDB ConnectionString to retrive dependent views definition for Data entities  |

## Copy data to Synapse Table in dedicated pool (DW GEN2)
If you are using Synapse dedicated pool (Gen 2) and want to copy the Tables data from data lake to Gen2 tables using Copy activity.   
You can use CDMUtil with DDLType = SynapseTable to collect metadata and insert details in control table to further automate the copy activity using synapse pipeline. Follow the steps bellow 
1. ![Create control table and artifacts on Synapse SQL Pool](DataTransform_SynapseDedicatedPool.sql)  
2. Configure CDMUtil to DDLType = SynapseTable
3. Use ADF/Synapse pileline to trigger copy activity by calling generic storedprocedure.    

## Create F&O Data entities as View on Synapse
Dynamics 365 Finance and Operations **Data entities** provides conceptual abstraction and encapsulation (de-normalized view) of underlying table schemas to represent key data concepts and functionalities. 
Existing Finance and Operations customer that are using BYOD for reporting and BI scenarios, may wants to create Data entities as view on Synapse to enable easier transition from BYOD to Export to data lake and minimize changes in existing reports and ETL processes. 
Export to data lake **Select tables using entities** option enables users to export dependent tables and data entity view defintion as cdm file under Entities folder in the data lake. 
To create data entities as view on Synapse, update following configurations to process entities as view 

|Name           |Description |Example Value  |
|----------------- |:---|:--------------|
|ManifestURL|Entity root or specific manifest file|[path]/Entities.manifest.cdm.json,[path]/[entityname].cdm.json |
|ProcessEntities|Process entities list from file Manifest/EntityList.json, this option can be used even if you dont have the entity metadata in the data lake.|true |
|Manifest/EntityList.json|List of the entities, Key name of entity, Value = Entity view definition. Leave value ="" to retrieve view definition from AXDBConnectionString |"Key" = "CUSTCUSTOMERV3ENTITY", Value=""|
|AXDBConnectionString|AXDB ConnectionString to retrive dependent views definition for Data entities. |"Server=DBServer;Database=AXDB;Uid=youruser;Pwd=yourpassword"|

Run CDMUtil console App or trigger Function App using HTTP to create entities as views on Synapse. 

#### Common issues and workarounds 

|Issue           |Current issue |Workaround/Recomendation |
|----------------- |:---|:--------------|
|**Missing dependent Tables** |Data entities view creation may fail if all dependent tables are not already available in Synapse SQL pool. Currently when **Select tables using entities** is used, all dependent tables does not get added to lake. | To easily identify missing tables provide AXDBConnectionString, CDMUtil will list outs missing tables in Synapse. Add missing table to service and run CDMUtil again |
|**Missing dependent views**|Data entities may have dependency on F&O views, currently metadata service does not produce metadata for views.| AXDBConnectionString of source AXDB tier1 to tier2 environment and automatically retrieve dependent views and create before create entity views.|
|**Syntax dependecy**|Some data entities or views may have sql syntax that is not supported in synapse.| CDMUtil parse the sql syntax and replaces with known supported syntax in Synapse SQL. ReplaceViewSyntax.json contains list of known syntax replacements. Additional replacement can be added in the file if required. |
|**Case sensitive object name** |Object name can be case sensitive in Synapse SQL pool and cause error while creating the view definition of entities | Change your database collation to 'alter database DBNAME COLLATE Latin1_General_100_CI_AI_SC_UTF8' |

   
You can also use bellow SQL query to identify views and dependencies manually using developer or sandbox environment
![View Definition and Dependency](/Analytics/CDMUtilSolution/ViewsAndDependencies.sql)

 
