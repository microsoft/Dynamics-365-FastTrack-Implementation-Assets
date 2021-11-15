## Data Transformation using Synapse Servless and Azure Data Factory/ Synapse Pipelines 
This is simple generic pipeline to materialize logical dimension and fact tables created on Synapse serverless layer data lake and create view on synapse over materialized data.

Below is the graphical representation of how we can transform the data from raw data to a materialized data model:

![image](https://user-images.githubusercontent.com/65608469/139340657-1f61bcd7-3b61-4206-a6b1-1c38c12dd00a.png)

 
## Setup: 
1.	Create container in the storage account where materialized data will be stored. 
2.	Run DataTransform_TargetDB.sql, change appropriate values and run script on Synapse Serverless to create target database, external data source and stored procedure to create views for materialized data.  
3.	Run DataTransform_SourceDB.sql script on Source Synapse Serverless database to create stored procedure to collect source metadata information. 
4. Deploy ADF template by providing required parameters


## Execute
1. Run DimTableCopy and FactTableCopy pipelines  


