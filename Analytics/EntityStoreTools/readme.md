
# Export & Process Entity Store Measures in Azure Synapse 

Processing Aggregate Measurements in the Entity Store is compute-intensive and will not scale for large datasets. The process below is intendend to make this process scalable by running it on Apache Spark clusters in Azure Synapse.

Notice that this process is different from [Making Entity Store Available in the Data Lake](https://docs.microsoft.com/en-us/azure/synapse-analytics/get-started-create-workspace), in that the steps below allow distributing the Entity Store *processing* across several tens of nodes and thus being able to handle large volumes of data. 

## Requirements

- Dynamics 365 Environment with [Export to Data Lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/configure-export-data-lake) enabled
- [Azure Synapse Analytics workspace](https://docs.microsoft.com/en-us/azure/synapse-analytics/get-started-create-workspace)

## Step-by-step Process

![Images](.wiki/images/EntityStoreToAzureSynapse.png)

### Step 1. Export Tables in Dynamics F&O

Enable the syncing of tables in the lake using the [Export to Data Lake](https://docs.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/configure-export-data-lake) feature.

### Step 2. Create Tables in Azure Synapse

Use the [CDMUtil](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/CDMUtilSolution) tool to create tables in Azure Synapse from the cdm.json files in the lake.

### Step 3. Export Entity Store Metadata
Use [EMEX Tool](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/EntityStoreTools/EntityStoreMetadataExporter) to export Entity Store Metadata for a given aggregate measurement.

### Step 4. Create Views and Entities in Azure Synapse

Use [ESYN Tool](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/tree/master/Analytics/EntityStoreTools/EntityStoreToSynapse) to create the views and entities from the aggregate measurement in Azure Synapse.

### Step 5. Process Measurement

Using Spark Notebooks and Entity Store SDK, load Entity Store metadata and process tables and views on Azure Synapse. Store the aggregate measurements back in Azure Synapse. [Import](https://docs.microsoft.com/en-us/azure/synapse-analytics/spark/apache-spark-development-using-notebooks?tabs=classical#create-a-notebook) the following Notebook into your Azure Synapse workspace: [Processing AggregateMeasurements On Azure Synapse.ipynb](https://github.com/microsoft/Dynamics-365-FastTrack-Implementation-Assets/blob/master/Analytics/EntityStoreTools/EntityStoreTransforms/Processing_AggregateMeasurements_On_Azure_Synapse.ipynb).

### Step 6. Consume Measurement

Aggregate measurements can now be consumed through SQL views in Azure Synapse.