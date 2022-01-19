Following table provides the overview of the tools available in this section 

|Tools           |Description |
|----------------- |:---|
|[CDMUtil](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/CDMUtilSolution)|Utility in GitHub to create views/external table ; this helped reduce adoption time for customers by creating view for table, data entities and all dependencies.|
|[Synapse To SQL](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/SynapseToSQL_ADF)|ADF generic solution template that can be used to copy incremental data from data lake using Synapse SQL serverless to another SQL database . Solution uses Export to data lake changeFeed to to identify incremental changes and export incremental changes to destination database and merge it.|
|[SQLToADLS](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/AzureDataFactoryARMTemplates/SQLToADLSFullExport)|A generic sample solution to export SQLServer (on-premise or Azure SQL) tables data to Azure Data lake Gen 2 storage account in Common data model format. Solution utilize Azure data factory pipelines and Azure function based on CDM SDK to copy SQL tables data and generate CDM metadata to Azure storage account.|
|[Data Transformation](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/DataTransform) | This is simple generic pipeline using Synapse Serverless and Azure Data Factory/ Synapse Pipelines to materialize logical dimension and fact tables created on Synapse serverless layer data lake and create view on synapse over materialized data.|
|[TCO Cost Calculator](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/CostCalculator) | From BYOD to Data Lake Storage Gen 2 with Synapse Serverless|
|[Entity Store Tools](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/EntityStoreTools)|Tools and process to transform EntityStore data in data lake using Synapse Analytics|
|[Azure SQL to SQL Pipeline](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/SQLToSQLADF)|ADF and SQL based generic solution template that can be used to copy incremental data from one SQL server database to another. Solution uses SQL ChangeTracking feature on the source database to identify incremental changes and export incremental changes to destination database and merge it.


