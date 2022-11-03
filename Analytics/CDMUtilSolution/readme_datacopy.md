
# Overview

Analytics for Dynamics 365 finance and operation apps requires few building blocks, that when connected together can enable your organization to build an Analytical and Integration solution. You take your data to your Data Lake and from there to Synapse data warehouse. You create what we call a modern data warehouse. This will also let you replace your BYOD entities, which have their challenges. 
	
The main building blocks are [Export to data lake service](https://learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/azure-data-lake-ga-version-overview), CDMUtil solution, [Azure Data Lake](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction) and [Azure Synapse Analytics](https://learn.microsoft.com/en-us/azure/synapse-analytics/overview-what-is).

Using above building blocks, an organization can come up with the right architecture for their analytical requirements. These architecture patterns are industry standard, namely, serverless pools, dedicated pools, and lakehouse. These have been covered in depth in an earlier TechTalk and GitHub, that are highly recommended. https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/ArchitecturePatterns#lakehouse-databricks-pyspark

In below post, we will step through instructions on how you can setup a working solution using one of the above patterns. The templates used are provided as links. 

The following diagram conceptualizes high level architecture: 
![Cdm Util As Pipeline](CdmUtilAsPipeline.png)


# Foundational concepts

1. Export to data lake - This feature lets you copy data and metadata from your Finance and Operations apps into your own data lake (Azure Data Lake Storage Gen2). 
Data that is stored in the data lake is organized in a folder structure that uses the Common Data Model format. 
Export to data lake feature exports data as headerless CSV files and metadata as [Cdm manifest](https://docs.microsoft.com/en-us/common-data-model/cdm-manifest). 

2. CDMUtil - converts CDM metadata in the lake to **Synapse Analytics** or **SQL metadata**. CDMUtil is a Synapse/ADF pipeline that reads [Common Data Model](https://docs.microsoft.com/en-us/common-data-model/) metadata and converts and executes  **Synapse Analytics SQL pools** or **SQL Server** DDL statements. **Note**: We also have [CDMUtil as an Azure Function or Console App](readme.md). This utility is developed in C# and utilizes the CDM SDK to read the CDM metadata and create Synapse metadata. Unlike CDMUtil as an Azure function and console App, the CDMUtil pipeline reads the json files directly and uses TSQL scripts to create the DDL statements required for Synapse Analytics. Since CDMUtil is just a pipeline within Synapse or Azure Data Factory, this approach simplifies the deployment and maintenance of the utilities.


3. Azure Data Lake - this is Blob storage

4. Azure Synapse Analytics - Synapse brings together the best of **SQL** and **Spark** technologies to work with your data in the data lake, provides **Pipelines** for data integration and ETL/ELT, and facilitates deep integration with other Azure services such as Power BI. 

5. Serverless pool - This is a virtualised DW
6. Dedicated pool - This is a cloud based DW
7. Lakehouse - This builds on Serverless and is an Industry standard that takes data through three layers of Bronze, Silver and Gold.

# Templates 

1. CDMUtil 
2. Data copy to Dedicated pool
3. Data copy to SQL

# Pre-requisites

# Instructions







