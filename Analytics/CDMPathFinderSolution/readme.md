# Azure SQL to SQL Pipeline  

This is a simple WPF application that can be used to list all the tables in the data lake with their respective paths. Solution uses the root table manifest (in the Tables folder) to traverse the metadata in the lake and retrieve the paths information. It can be useful to list all the paths and finds tables when they are moved due to a change in the metadata.

# How to use

## Prerequisites
1. Retrieve one of the connection strings for the storage account 
![RetreiveConnectionString](RetreiveConnectionString.png) 
2. Collect the contaned name
3. Collect the initial manifest path (e.g. /testenvironment.sandbox.operations.dynamics.com/Tables/Tables.manifest.cdm.json)

## Run the application 
To run the application you can compile the project or use the released version in the zip file ![CDMPathFinder.zip](CDMPathFinder.zip)
1. Run the WPF application and insert the required information already collected. 
2. Press the "Process" button to retrieve the paths. The process will take about a minute. 
3. The results will appear in the bottom textbox. Copy the text for further use.
![CDMPathFinder](CDMPathFinder.png)

