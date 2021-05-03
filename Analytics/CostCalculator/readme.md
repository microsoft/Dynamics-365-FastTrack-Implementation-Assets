# TCO calculator : From BYOD to Data Lake Storage Gen 2 with Synapse SQL-OD

## Scenario covered
Customer leverages BYOD export to extract data and then hydrates an enterprise DW or reports on top of BYOD tables (e.g using PBI import mode or Direct query)
Customer wants to have this shift absolutely transparent from data consumption perpsective and wants to have a SQL endpoint to interact with data in the lake.
### Question we aim to answer :  
what will be customer cost impact or savings to move from BYOD to Azure SQL + SynapseSQL-OD ?
To arrive at that number, use the sheets in this workbook in order.  Fields highlighted in green are input fields, intended for you to populate.
Worksheet cells legend is described above 


### Who is this aimed at ?
This is aimed at D365 It professionals, customers or partners working on a D365 FO/ Commerce /HR implementation or live project and wants to have a total cost of ownership estimation to leverage Data Lake Storage Gen2 and Synapse SQl On Demand


## Prerequisites

1. Perform a Database refresh of AXDB from Production to Sandbox environment (e.g : PITR PROD to Sandbox)- 
This is required to collect latest statistics by running queries provided with the tool
2. Need access to production BYOD database and setup “Query store capture mode” to All -  
This is required to collect query statistics to understand the read patterns on the BYOD database in production








