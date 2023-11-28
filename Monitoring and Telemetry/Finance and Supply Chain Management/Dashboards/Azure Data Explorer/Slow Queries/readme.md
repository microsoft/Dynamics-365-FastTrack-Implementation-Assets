# AOS Slow Query Telemetry dasboard
This dashboard shows information about slow queries that are reported by the AOS. Using this dashboard, it is possible to:
- Measure the number of slow queries over time.
- List slow by their duration.
- Investigate slow queries based on location.

## Dashboard overview
![Dashboard](SlowQueriesDashboard1.png)

## Steps to import the sample dashboard:
  1. Import the file "ADE-Dashboard-D365FO-Monitoring-SlowQueries.json".
  
  ![1ImportSample](1ImportSample.png){width=750 height=350}

  2. Name the dashboard appropriately.
  
  ![2EditName](2EditName.png){width=250 height=175}
  
  
  3. Click to select datasources. 
  
  ![3Datasource](3Datasource.png)
  
  4. There is a templated datasource with dummy placeholders. You need to replace with your Azure subscription, resource group and Application Insights instance.
  
   ![4DatasourceEdit](4DatasourceEdit.png) 

   ![5DatasourceSet](5DatasourceSet.png) 