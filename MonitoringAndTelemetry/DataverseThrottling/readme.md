# Dataverse Query Throttling — ADX/AI Logs Dashboard

A ready-to-use Azure Data Explorer (ADX) / Application Insights dashboard that visualizes **Dataverse Query Throttling** so you can spot hot windows, find the noisiest queries, understand reasons, and prioritize fixes.

---

## What you’ll see (Tiles)

1. **Throttles Over Time + Avg Delay** – trend of throttled queries with average delay.  
2. **Top Throttled Queries (by Hash)** – the worst offenders with a sample command text.  
3. **Reasons for Throttling** – distribution of throttle reasons.  
4. **Delay Percentiles** – P50/P90/P95/P99 to understand user impact.  
5. **Hot Windows (Spike Detection)** – statistically significant spikes.  
6. **Most-Affected Callers/Operations** – users/operations hit hardest.  
7. **Recent Samples** – last 100 throttling records for fast triage.  
8. **Environment/Org Breakdown** – multi-tenant view (optional).

---

## Prerequisites

- Application Insights logs that include the **Query Throttling** signal (commonly in `traces` or `customEvents`).
- Access to ADX / Log Analytics / Workbooks to run KQL.
- Permissions to create a dashboard/workbook.

---

## Dashboard overview

<div align=center><img src="./Images/Dashboard.png"></div>


## Steps to import the sample dashboard:
  1. Import the file "dashboard-Dataverse Throttling Dashboard.json".
  
  <div align=center><img src="./Images/ImportDashboard.png" width="600" height="300"></div>

  2. Name the dashboard appropriately and then click to select datasources
  
  <div align=center><img src="./Images/Datasources.png" width="450" height="300"></div>
  
  3. In the Datasource selection pane you have to put your Azure Application Insights subscriptionID in the placeholder .
  
  <div align=center><img src="./Images/SubscriptionId.png" width="350" height="225"></div>
  <div align=center><img src="./Images/SubscriptionIdAndDatasource.png" width="350" height="650"></div>

  4. After updating the correct subscriptionID. click on connect.

  5. You will get a list of databases. Select your ApplicationInsights name from that list and save changes.

  6. your dashboard should have data now. Feel free to edit the queries to suit your needs. 
