# Form Load and Plugin Dashboard
This dashboard shows information about DMF errors and distribution of DMF errors in your solution. Using this dashboard, it is possible to identify:
- Distribution of different eror types in your solution. error code description here : https://review.learn.microsoft.com/en-us/dynamics365/fin-ops-core/dev-itpro/data-entities/dm-error-descriptions
- ExecutionId, ActivityId and other details for the errors in DMF
- Error message

## Dashboard overview

<div align=center><img src="./img/Dashboard.png"></div>

## Steps to import the sample dashboard:
  1. Import the file "dashboard-DMF Errors.json".
  
  <div align=center><img src="./img/ImportDashboard.png" width="600" height="300"></div>

  2. Name the dashboard appropriately and then click to select datasources
  
  <div align=center><img src="./img/Datasources.png" width="450" height="300"></div>
  
  3. In the Datasource selection pane you have to put your Azure Application Insights subscriptionID in the placeholder .
  
  <div align=center><img src="./img/SubscriptionId.png" width="350" height="225"></div>
  <div align=center><img src="./img/SubscriptionIdAndDatasource.png" width="350" height="650"></div>

  4. After updating the correct subscriptionID. click on connect.

  5. You will get a list of databases. Select your ApplicationInsights name from that list and save changes.

  6. your dashboard should have data now. Feel free to edit the queries to suit your needs. 
