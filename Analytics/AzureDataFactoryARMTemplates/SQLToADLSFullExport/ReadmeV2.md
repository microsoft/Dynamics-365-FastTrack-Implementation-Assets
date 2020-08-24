# SQLToADLS Full Export V2 Highlights  
Following are some highlights of this updated version of data factory solution
1. Creates the folder structure in data lake similar to what F&O Data feed service is going to create
2. Automatically create partition for large tables  
3. Produce schema as Manifest.json format that is the new format of CDM and Data feed service is going to produce this format 
4. With Manifest.json CDM format  and Azure function
5. Pipeline to read metadata and create views in SQLOn-Demand 

# Prerequisites 
1. Azure subscription with access to create resource 
1. Azure data lake storage V2 account  
2. Synapse workspace and SQL-on-Demand endpoint 
3. Visual Studio 2019 
4. Azure data factory

# High level deployment steps
## Setup Storage Account 
1. In Azure portal go to storage account and create a container dynamics365-financeandoperations
2. Create a folder under container to represent your environment name ie - analyticsPerf87dd1496856e213a.cloudax.dynamics.com
3. Download /SQLToADLSFullExport/example-public-standards.zip
4. Extract and upload all files to root folder ie. environment folder 

## Deploy Azure function 
1.	Clone the repository and open C# solution  in Visual Studio 2019 [Visual Studio Solution](/Analytics/CDMUtilSolution)
3.	Install dependencies and Build the solution to make sure all compiles 
4.  update local.setting.json under CDMUtil_AzureFunctions to as per your environment configurations   
5.	Publish the CDMUtil_AzureFunctions Project as Azure function (Ensure that local.Settings.json values are copied during deployment) 
    ![Publish Azure Function](/Analytics/Publish.PNG)
6.	Get your Azure function URL and Key
7.  Ensure that all configuration from local.settings.json in the Azure function app configuration tab.
  ![Azure Function Configurations](/Analytics/AzureFunctionConfiguration.PNG)

## Deploy Azure Data Factory Template 
1. Collect all parameters values 
2.	Downlaod and Deploy arm_template_V2.json as Data factory 

## Execute pipelines 
1. Execute pipeline SQLTablesToADLS to exort data and create CDM schema 
2. Execute pipeline CreateView to create the views

# Troubleshooting 
1. If your pipleline fails on the Azure function calls, validate your Azure function configuration.
2. you can also debug C# code by running the CDMUtil_AzureFunctions locally and PostMan - Postman template can be found under /SQLToADLSFullExport/CDMUtil.postman_collection you can find input parameters for Azure function in Azure data factory pipeline execution history. 

