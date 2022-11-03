
# Overview

Analytics for Dynamics 365 finance and operation apps requires few building blocks, that when connected together can enable your organization to build an Analytical and Integration solution.

The main building blocks are [Export to data lake service](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/azure-data-lake-ga-version-overview), CDMUtil solution, [Azure Data Lake](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction) and [Azure Synapse Analytics](https://learn.microsoft.com/en-us/azure/synapse-analytics/overview-what-is).

Using above building blocks, an organization can come up with the right architecture for their analytical requirements. These architecture patterns are industry standard, namely, serverless pools, dedicated pools, and lakehouse. These have been covered in depth in an earlier TechTalk and GitHub, that are highly recommended. https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/ArchitecturePatterns#lakehouse-databricks-pyspark

In below post, we will step through instructions on how you can setup a working solution using one of the above patterns. The templates used are provided as links. <disclaimer needed?>

starts from getting the Dynamics data into [Azure Synapse Analytics] (https://docs.microsoft.com/en-us/azure/synapse-analytics/overview-what-is) Synapse brings together the best of **SQL** and **Spark** technologies to work with your data in the data lake, provides **Pipelines** for data integration and ETL/ELT, and facilitates deep integration with other Azure services such as Power BI. 


In Dynamics 365 Finance and Operations Apps, the [Export to data lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/finance-data-azure-data-lake) feature lets you copy data and metadata from your Finance and Operations apps into your own data lake (Azure Data Lake Storage Gen2). 
Data that is stored in the data lake is organized in a folder structure that uses the Common Data Model format. 
Export to data lake feature exports data as headerless CSV files and metadata as [Cdm manifest](https://docs.microsoft.com/en-us/common-data-model/cdm-manifest).  

Many Microsoft and third-party tools such as Power Query, Azure Data Factory, and Synapse Pipeline support reading and writing CDM, 
however, the data model from OLTP systems such as Finance and Operations is highly normalized and hence must be transformed and optimized for BI and Analytical workloads. 

Using Synapse Analytics, Dynamics 365 customers can unlock following scenarios: 

1. Data exploration and ad-hoc reporting using T-SQL 
2. Logical datawarehouse using lakehouse architecture 
3. Replace BYOD with Synapse Analytics
4. Data transformation and ETL/ELT using Pipelines, T-SQL, and Spark
5. Enterprise Datawarehousing
6. System integration using T-SQL

To get started with Synapse Analytics with data in the lake, you can use CDMUtil pipeline to convert CDM metadata in the lake to **Synapse Analytics** or **SQL metadata**. 
CDMUtil is a Synapse/ADF pipeline that reads [Common Data Model](https://docs.microsoft.com/en-us/common-data-model/) metadata and converts and executes  **Synapse Analytics SQL pools** or **SQL Server** DDL statements. 

The following diagram conceptualizes the use of Synapse Analytics at a high level: 
![Cdm Util As Pipeline](CdmUtilAsPipeline.png)


**Note**: We also have [CDMUtil as an Azure Function or Console App](readme.md). This utility is developed in C# and utilizes the CDM SDK to read the CDM metadata and create Synapse metadata. 
Unlike CDMUtil as an Azure function and console App, the CDMUtil pipeline reads the json files directly and uses TSQL scripts to create the DDL statements required for Synapse Analytics.
Since CDMUtil is just a pipeline within Synapse or Azure Data Factory, this approach simplifies the deployment and maintenance of the utilities.


