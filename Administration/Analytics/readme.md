The following table provides an overview of the tools available in this section: 

|Tools           |Description |
|----------------- |:---|
|[CDMUtil](CDMUtilSolution)|CDMUtil is a client tool based on the CDM SDK that reads Common Data Model metadata and converts it into metadata for Synapse Analytics SQL pools and Spark pools. For customers adopting Export to Azure Data Lake, this utility helps reduce adoption time by creating views for tables, data entities, and all dependencies.|
|[Synapse To SQL](SynapseToSQL_ADF)|An Azure Data Factory generic solution template that can be used to copy incremental data from data lake using Synapse SQL serverless to another SQL database. This solution uses Export to data lake change feed data to to identify and export incremental changes to a destination database and merge it.|
|[SQLToADLS](AzureDataFactoryARMTemplates/SQLToADLSFullExport)|A generic sample solution to export SQL Server (on-premise or Azure SQL) tables data to Azure Data Lake Gen 2 storage account in Common Data Model (CDM) format. The solution utilizes Azure data factory pipelines and Azure function based on CDM SDK to copy SQL tables data and generate CDM metadata to Azure storage account.|
|[Data Transformation](DataTransform) | This is a simple generic pipeline using Synapse Serverless and Azure Data Factory / Synapse Pipelines to materialize logical dimension and fact tables created on Synapse serverless layer data lake, and create views on Synapse over materialized data.|
|[TCO Cost Calculator](CostCalculator) | An Excel spreadsheet that helps calculate the cost of moving from BYOD to Data Lake storage Gen 2 with Synapse Serverless.|
|[Entity Store Tools](EntityStoreTools)|Tools and process to transform Entity store data in data lake using Synapse Analytics.|
|[Azure SQL to SQL Pipeline](SQLToSQLADF)|ADF and SQL-based generic solution template that can be used to copy incremental data from one SQL server database to another. Solution uses SQL Change Tracking feature on the source database to identify incremental changes and export incremental changes to destination database and merge it.|
|[CDMPathFinderSolution](CDMPathFinderSolution)|Simple WPF application to retrieve all table paths provided the initial Tables.manifest.cdm.json file.|
|[Architecture Patterns](ArchitecturePatterns)|Architecture patterns and sample code solutions to build end-to-end Analytical pipelines. |
|[ML Samples](ML-Samples)|Sample ML notebooks and solutions with commentary to showcase how ML can be incorporated into your Analytics pipelines and BI dashboards. 


