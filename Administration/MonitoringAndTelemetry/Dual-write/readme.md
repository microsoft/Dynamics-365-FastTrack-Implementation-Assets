# Dual-write Application Insights Dashboard
This dashboard consists of a single page with different tiles visualizing different signals related to Dual-write

Using this dashboard, you can identify:

- Dataverse Dual-write errors
- FnO Dual-write errors
- Error count and details for errors raised by SCM PlugIns
- Dual-write daily generated error distribution
- Monitor Account SDK success rate
- Performance of Account SDK dataverse operations

## Dashboard overview

<div align=center><img src="./img/Dashboard.png"></div>

## Steps to import the sample dashboard:
  1. Import the file "dashboard-Power Automate Monitoring.json".
  
  <div align=center><img src="./img/ImportDashboard.png" width="600" height="300"></div>

  2. Name the dashboard appropriately and then click to select datasources
  
  <div align=center><img src="./img/Datasources.png" width="450" height="300"></div>
  
  3. In the Datasource selection pane you have to put your Azure Application Insights subscriptionID in the placeholder .
  
  <div align=center><img src="./img/SubscriptionId.png" width="350" height="225"></div>
  <div align=center><img src="./img/SubscriptionIdAndDatasource.png" width="350" height="650"></div>

  4. After updating the correct subscriptionID. click on connect.

  5. You will get a list of databases. Select your ApplicationInsights name from that list and save changes.

  6. your dashboard should have data now. Feel free to edit the queries to suit your needs. 
