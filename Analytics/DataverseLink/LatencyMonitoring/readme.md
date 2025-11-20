# Fabric Link Staleness Report  
This repository contaions the components to crete a stalenessreport base in the data extracted using Fabric Link. 

## Challenge
Many Dynamics 365 Fiance and SCM customers measure latency by simply comparing the value of **SinkModifiedOn** with **ModifiedDateTime** (or CretedDateTime). ​Problem: Fabric Link can sink multiple times the same RecId/RecVersion leaving only the last SinkModifiedOn. This leads to perceived latency that can be way higher than the real latency.​
This solution allow to crete a report on top of Fabric, that provides accurate latency.​

## Solution Components
1. Table to store the actual staleness for RecId/RecVersion pairs (granular).​
2. Table to store aggregated information (summarized).​
3. Two scripts (Fabric Notebooks) to maintain the tables.​ 
4. (opt) Pipeline to run the notebooks with a schedule.​
5. (opt) Power BI dashboard to visualize the status.​

## Content
- **FabricLinkDataStaleness.ipynb**: the main notebook that generates the granular staleness data
- **FabricLinkDataStaleness_Summarization.ipynb**: the aggregation script that generates the summarized data and cleans up the ranualr table 
- **Staleness analysis pipeline.zip**: contining the pileline to run the scripts in sequence
- **Staleness report Fabric Link.pbix**: simple example of Power BI report leveraging the generated data

## Preprequisites
The script works only with tables that have modifieddatatime or creteddatetime activated. 

## Intructions
Download the contet and set up the two notebboks in fabric.
Import the two notebooks in Fabric and set up the needed paramentes. 

#### FabricLinkDataStaleness paramenters:
- **tables_list**: the comma-separated list of tables to analyze (*mandatory*)
- **source_workspace_id**: the id of the workspace that contains the tables (*mandatory*)
- **source_lakehouse_name**: the name of he lakehouse that conatins teh tables (*mandatory*)
- **hours_back**: how many hours back the script has to consider. This paraenter must be an integer greaterthan zero (*mandatory*)
- **target_table_name**: name of the table that will contain the granular staleness data (*mandatory*)
- **versions_bucket_size**: the script works in chunks, this paramenter decides how many versions must be considered for each chunk. It hepls redeuce the strain on the processig resources. It must be an integer greater than 2. (*mandatory*)
- **display_sample**: this paramenter is used for debugging purpuses to display samples of records in the console durin the runs
- **target_table_base_path**: use this paramenter to have the target table sitting in a different lake. If target_table_base_path is empty, the standard tables' path will be used (*optional*)

#### FabricLinkDataStaleness_Summarization paramenters:
- **lookback_hours**: The granular rows are processed starting form *first_SinkCreatedOn < now - lookback_hours*. This paramenter must be an integer greather than 1
- **grouping_time_zone**: Default timezone UTC
- **source_table**: Must be the same as *target_table_name* paramenter in the FabricLinkDataStaleness script 
- **target_table**: The target summarization table *Staleness analysis pipeline.zip*


*(opt.)* Crete the pipeline using **Staleness analysis pipeline.zip**. In your workspace crete a new pipeline then import the zip file from the edit page.
Note that all the above paramenters can be changed in the pipeline in order to adapt to the specific needs. Make sure the pipeline's recurrence matcher the scripts paramentes *hours_back* and *lookback_hours* to avoid leaving ou soe changes. 

Use the Power BI report example or build your own to easily analyze the data.

## Suggestions
1. Run the recurring pipeline​ to have a stable and autoamted flow of information
2. Limit the analysis to critical tables​. The latency analysis can be quite heavy depending on the change rate of tables
3. Make the summarization chase the granular analysis. For example: Granular analysis can process the last 3 hours while the summarization compresses everything before that. 
4. If the update flow is massive, keep the granular level window small. There is hardly any value in having details for billions of records.
5. In general, adapt the parameters to your scenario.​
6. Test with few tables and then increase as needed.​
7. Use *versions_bucket_size* paramenter to reduce the CPU strain. 

