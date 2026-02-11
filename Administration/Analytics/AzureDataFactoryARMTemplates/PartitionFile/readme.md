# Partition file by size pipeline overview
PartitionBySize is a generic Azure data factory pipeline that uses Data factory Data flow to partition a large file to smaller chunks. This repository contains the pipleline PartitionbySize pipeline and related object as a template file that you can easily import in your existing data factory solution. 

Follow the steps dellow for step by step guidance to deploy the pipeline

## Prerequisites 
1. Download file on your local computer [Template file](/Analytics/AzureDataFactoryARMTemplates/PartitionFile/PartitionBySize.zip)
2. Login to Azure portal and open your existing Azure data factory solution and follow the steps 

## Steps 
As shown in the image, use following steps to import the pipeline
![Importing pipeline template](/Analytics/AzureDataFactoryARMTemplates/PartitionFile/ImportTemplate.png)

1. Click on + and then Pipelines from template 
2. Select My template 
3. Click on use Local template, and then locate the file downloaded in step 1 
4. Select ADLSGen2 link service in the dropdown for all the datasources 
5. Click on Use template button, template will be imported in your data factory 
6. Click on Publish all 
7. Publish to deploy commit the changes to your data factory solution 

Now the data factory pipeline PartitionBySize is ready to use to partition any file. 


# Using Partition file by size pipeline

PartitionBySize is a generic pipeline that can partition any large CSV or Parquet file by providing the required parameters as shown bellow 
![Running pipeline](/Analytics/AzureDataFactoryARMTemplates/PartitionFile/RunningPipelinePartitionbySize.png)

You can also call PartitionBySize pipeline from your main data export pipeline to execute the process end to end.
