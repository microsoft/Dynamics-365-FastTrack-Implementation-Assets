# AOS Slow Query Telemetry dashboard
This dashboard shows information about slow queries that are reported by the AOS. Using this dashboard, it is possible to:
- Measure the number of slow queries over time.
- List slow by their duration.
- Investigate slow queries based on location.

## Dashboard overview

<div align=center><img src="./img/SlowQueriesDashboard1.png"></div>

## Steps to import the sample dashboard:
  1. Import the file "ADE-Dashboard-D365FO-Monitoring-SlowQueries.json".
  
  <div align=center><img src="./img/1ImportSample.png" width="600" height="300"></div>

  2. Name the dashboard appropriately.
  
   <div align=center><img src="./img/2EditName.png" width="300" height="200"></div>
  
  3. Click to select datasources. 
  
  <div align=center><img src="./img/3Datasource.png" width="450" height="300"></div>
  
  4. There is a templated datasource with dummy placeholders. You need to replace with your Azure subscription, resource group and Application Insights instance.
  
  <div align=center><img src="./img/4DatasourceEdit.png" width="350" height="225"></div>
  <div align=center><img src="./img/5DatasourceSet.png" width="350" height="550"></div>
