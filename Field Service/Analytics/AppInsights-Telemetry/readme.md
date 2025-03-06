# Field Service Mobile Offline Telemetry Dashboard Sample
Azure Data Explorer Dashboard sample that demonstrates the information that can be queried within the Field Service Mobile Offline Telemetry export into your own Azure Application Insights resources. This dashboard is focused on the usage on Mobile offline synchronization and can be used to understand usage, diagnose performance issues and understand synchronization issues.

## Sync Summary
<div align=center><img src="./img/offline-telemetry-sync-summary.png"></div>

This dashboard shows a summary of recent offline synchronizations
- Distribution of sync types
- Daily users doing offline sync
- Usage by App versions
- Data sync duration (P50) by Sync Mode
- Daily sync success rate

### Distribution of sync types
```
dependencies 
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.eventContext))
| extend dataSyncMode = tostring(customDimensions.DataSyncMode)
| where isnotempty(dataSyncMode)
| summarize count() by dataSyncMode
| project-rename ['Data sync mode'] = dataSyncMode
| render piechart 
```
This query summarizes the number of synchronizations per Data Sync mode from the Offline.SyncDatabase dependency record

### Daily users doing offline sync
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.eventContext))
| extend profileId = tostring(eventContext.ProfileId)
| summarize ['Unique Users'] = dcount(profileId) by bin(timestamp, 1d)
```

This query extracts the number that have executed an offline synchronization per day from the Offline.SyncDatabase dependency record

### Usage by App versions (Requires UCI events)
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| where isnotempty(user_Id) // Filter out rows where user_Id is empty
| where cd.AppFlavor == "FieldService"
| extend appVersion = tostring(cd.AppInfo_Version)
| extend Version = extract(@"\b\d+\.(\d+\.\d+)", 1, appVersion)
| extend DeviceInfo_OsName = tostring(cd.DeviceInfo_OsName)
| where isnotempty(Version)  // Filter our request where there's no app version
| summarize Users = dcount(user_Id),              
             Android = dcountif(user_Id, DeviceInfo_OsName == "Android"), 
             iOS = dcountif(user_Id, DeviceInfo_OsName == "iOS"  or DeviceInfo_OsName == "iPadOS"), 
             Windows = dcountif(user_Id, DeviceInfo_OsName has "Windows") 
         by Version
| order by Version asc
```

This query extracts the Field Service Mobile Application version (removing the prefix major and minor to shorten the length) and shows how many users are running the version by device operating system.


### Data sync duration P50 by Sync mode
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.eventContext))
| extend EventName = tostring(cd.eventName)
| extend DataSyncMode = iff(isempty(['dataSyncMode']), "All", tostring(customDimensions.DataSyncMode))
| where isempty(['dataSyncMode']) or DataSyncMode in (['dataSyncMode'])
| project timestamp, name, user_Id, DataSyncMode, cd, eventContext, duration
| summarize percentiles(duration, 50) by bin(timestamp, 1d), DataSyncMode
| order by timestamp desc
| project-rename ['Timestamp'] =  timestamp, ['Data sync mode'] =  DataSyncMode, ['P50 Duration (ms)'] =  percentile_duration_50
| limit 20
```

This query retrieves the P50 duration of synchronizations

### Daily sync success rate
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name endswith "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.eventContext))
| extend syncMode = tostring(customDimensions.DataSyncMode)
| extend EventName = tostring(cd.eventName)
| extend ScenarioResult = tostring(cd.ScenarioResult)
| where isempty(['dataSyncMode']) or syncMode in (['dataSyncMode'])
| where isnotempty(ScenarioResult)
| summarize Success = todouble(countif(ScenarioResult == "SUCCESS")), All = countif(ScenarioResult == "SUCCESS" or ScenarioResult == "FAILURE") by bin(timestamp, 1d)
| extend SuccessRate = todouble(Success/All) * 100
| project timestamp, SuccessRate
```

This query graphs the percentage of synchronizations that have been successful over time

### Device Types

```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| where isnotempty(user_Id) // Filter out rows where user_Id is empty
| where cd.AppFlavor == "FieldService"
| extend appVersion = tostring(cd.AppInfo_Version)
| extend Version = extract(@"\b\d+\.(\d+\.\d+)", 1, appVersion)
| extend DeviceInfo_OsName = tostring(cd.DeviceInfo_OsName)
| extend DeviceInfo_MakeModel = strcat(tostring(cd.DeviceInfo_make), " ", tostring(cd.DeviceInfo_model))
| summarize count() by DeviceInfo_MakeModel
```
The query shows the distribution of device types being used for Offline synchronization

## Sync Errors
This dashboard shows a summary and timeline of Offline Synchronization Errors

<div align=center><img src="./img/offline-telemetry-sync-errors.png"></div>

### Sync errors summary
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| where success == false
| extend cd = parse_json(customDimensions)
| extend AppVersion = tostring(cd.AppInfo_Version)
| extend ErrorCode = tostring(cd.ErrorCode)
| extend ErrorMessage = tostring(cd.ErrorMessage)
| extend FailureType = tostring(cd.FailureType)
| where isempty(['userId']) or user_Id == ['userId']
| summarize UsersImpacted = dcount(user_Id), ErrorCount= count() by ErrorCode, ErrorMessage, FailureType
| order by ErrorCount
| project-rename ['Error code'] = ErrorCode,['Error message'] = ErrorMessage, ['Failure type'] = FailureType, ['Errors'] = ErrorCount,  ['Users impacted'] = UsersImpacted
| order by ['Error code']
```

Gain an insight into the type of Offline sync errors 

## Sync errors timeline
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name == "Offline.SyncDatabase"
| where success == false
| where isempty(['userId']) or user_Id == ['userId']
| extend cd = parse_json(customDimensions)
| extend AppVersion = tostring(cd.AppInfo_Version)
| extend ErrorCode = tostring(cd.ErrorCode)
| extend ErrorMessage = tostring(cd.ErrorMessage)
| extend FailureType = tostring(cd.FailureType)
| where isempty(['errorMessage']) or ErrorMessage contains ['errorMessage']
| summarize ['Users Impacted'] = dcount(user_Id), Errors = count() by bin(timestamp, 1d)
| render timechart 
```
Timeline of the number of errors and users impacted over time

## Sync Performance
This dashboard provides insights into the performance of the Offline synchronization 
- Average duration of Sync by Device Type
- Offline Filter performance
- Network connectivity

<div align=center><img src="./img/offline-telemetry-sync-performance.png"></div>

### Average duration of Sync by Device Type
```
dependencies
| where name == "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend ActiveDuration = toint(tostring(cd.ActiveDuration))
| extend WithBackgroundTime = duration
| extend DataSyncMode = tostring(cd.DataSyncMode)
| extend DeviceInfo_OsName = tostring(cd.DeviceInfo_OsName)
| extend DeviceInfo_Make = tostring(cd.DeviceInfo_make)
| extend DeviceInfo_Model = tostring(cd.DeviceInfo_model)
| where isnotempty(DataSyncMode)
| summarize percentile_ActiveDuration_50= round(percentile(ActiveDuration, 50)/1000, 0), percentile_WithBackgroundTime_50 = round(percentile(WithBackgroundTime, 50)/1000, 0) by client_Type, DataSyncMode, DeviceInfo_Make, DeviceInfo_Model
| order by DataSyncMode, client_Type, DeviceInfo_Make, DeviceInfo_Model
| project ['Data sync mode']  = DataSyncMode, ['Client type'] = client_Type, ['Device Make'] = DeviceInfo_Make,['Model'] = DeviceInfo_Model, ['P50 Active Duration (in seconds)'] = percentile_ActiveDuration_50, ['P50 With Background Time Duration (in seconds)'] = percentile_WithBackgroundTime_50

```
The average duration of offline synchronization by the type of Device

### Offline Filter performance
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where name startswith "Offline.SyncDatabase"
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.EventContext))
| extend currentSyncId = tostring(eventContext["CurrentSyncId"])
| project operation_Id, currentSyncId
| where isempty(['externalCorrelationId']) or operation_Id == ['externalCorrelationId']
| join 
(
    dependencies    
    | where timestamp > ago(7d)
    | where type == "SDKRetrieveMultiple"
    | extend requestId = trim_end("_([a-z0-9-]*)", operation_Id)    
) on $left.operation_Id == $right.requestId
| summarize  percentiles(duration, 50,90) by target
| order by  percentile_duration_90
| project Table = target, ['Average Duration (ms)'] = round(percentile_duration_50, 0), ['P90 Duration (ms)'] = round(percentile_duration_90, 0)
```

The types correlates between the backend server SDK Retrieve Multiple requests and the Offline Synchronization request to help to identify which Offline sync filters queries are the most expensive

### Network connectivity
```
pageViews
| where timestamp between  (_startTime.._endTime)
| extend hostType = tostring(customDimensions.hostType)
| where hostType == "MobileApplication"
| extend networkConnectivityState = tostring(customDimensions.networkConnectivityState)
| extend networkConnected = toint(networkConnectivityState == "online")
| where isempty(['userId']) or user_Id == ['userId']
| summarize ['Network connection'] = max(networkConnected) by bin(timestamp, 1min)
| render timechart 
```

This graph shows where network detection is detected over time

## Sync Payload
This dashboard shows the number of records stored, synchronized and the size of the data synchronization
- Records on the device
- Records Synchronized
- Payload size

<div align=center><img src="./img/offline-telemetry-sync-payload.png"></div>

### Records on the Device
```
dependencies
| where timestamp between  (_startTime.._endTime)
| where isempty(['userId']) or user_Id == ['userId']
| where name startswith "Offline" 
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.EventContext))
| extend entityName = tostring(eventContext.EntityName)
| extend recordCount = toint(eventContext.RecordCount)
| extend currentSyncId = tostring(eventContext.CurrentSyncId)
| where recordCount > 0
| where isnotempty(entityName) 
| project timestamp, recordCount, entityName, currentSyncId
| summarize sum(recordCount) by entityName, currentSyncId
| summarize avg(sum_recordCount) by entityName
```

This pie chart shows the number of records on the device by table name

### Records Synced
```
dependencies
| where timestamp between (['_startTime'] .. ['_endTime']) // Time range filtering
| where isempty(['userId']) or user_Id == ['userId'] // Single selection filtering
| where name startswith "Offline" 
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.EventContext))
| extend entityName = tostring(eventContext.EntityName)
| where entityName == ['tableName'] // Single selection filtering
| extend dataSyncMode  = iff(isempty(['dataSyncMode']), "All", tostring(customDimensions.DataSyncMode))
| where isempty(['dataSyncMode']) or dataSyncMode == ['dataSyncMode']
| extend recordCount = toint(eventContext.RecordCount)
| extend currentSyncId = tostring(eventContext.CurrentSyncId)
| where recordCount > 0
| where isnotempty(entityName) 
| project timestamp, recordCount, entityName,  user_Id
| order by timestamp asc
| extend syncCount = recordCount
| summarize sum(syncCount) by bin(timestamp, 1min)
```

This timeline shows the number of records being sync. This can be filtered by sync mode, user and table name.

### Payload Size
```
dependencies 
| where timestamp between  (_startTime.._endTime)
| where name startswith "Offline" 
| extend cd = parse_json(customDimensions)
| extend eventContext = parse_json(tostring(cd.EventContext))
| extend entityName = tostring(eventContext.EntityName)
| extend syncMode = tostring(customDimensions.DataSyncMode)
| extend contentLength = toint(eventContext.ContentLength)
| extend responseSize = toint(eventContext.ResponseSize)
| extend shortName = trim_start("Offline.DdsClient.([A-Za-Z)*])", name)
| where isnotempty(syncMode)
| where responseSize > 0// (decompressedSize)
| extend responseSizeKb = responseSize/1024
| project timestamp, contentLength, responseSize,responseSizeKb, entityName,  user_Id, syncMode, shortName
| summarize ['Average Response Size in Kb'] = round(avg(responseSizeKb)) by syncMode
| project-rename ['Data sync mode'] = syncMode
| order by ['Average Response Size in Kb']
```

This table shows the size of the offline synchronization payload by Data sync mode

## Sync details
Use this dashboard to drill into individual users synchronization

<div align=center><img src="./img/offline-telemetry-sync-details.png"></div>

### User Sync Details

```
dependencies
| where name == "Offline.SyncDatabase"
| where isempty(['userId']) or user_Id == ['userId'] // Single selection filtering
| extend cd = parse_json(customDimensions)
| extend ActiveDuration = toint(tostring(cd.ActiveDuration))
| extend WithBackgroundTime = duration
| extend DataSyncMode = tostring(cd.DataSyncMode)
| extend ErrorMessage = tostring(cd.ErrorMessage)
| extend DeviceInfo_OsName = tostring(cd.DeviceInfo_OsName)
| extend DeviceInfo_make = tostring(cd.DeviceInfo_make)
| extend DeviceInfo_model = tostring(cd.DeviceInfo_model)
| where isnotempty(DataSyncMode)
| summarize P50ActiveDurationInSec = round(percentile(ActiveDuration, 50)/1000, 0),P50WithBackgroundTimeInSec = round(percentile(WithBackgroundTime, 50)/1000, 0), arg_max(timestamp, ErrorMessage), Failures = countif(success == false) by UserAzureObjectID = user_Id, DataSyncMode,DeviceInfo_OsName, DeviceInfo_make, DeviceInfo_model
| project ['Timestamp'] = timestamp, ['User Azure Object ID'] = UserAzureObjectID, ['Data Sync Mode'] = DataSyncMode, ['OS'] = DeviceInfo_OsName, ['Make'] = DeviceInfo_make, ['Model'] =  DeviceInfo_model, ['P50 Active duration (seconds)'] = P50ActiveDurationInSec , ['P50 with background time (sec)'] = P50WithBackgroundTimeInSec,Failures, ['Error message'] = ErrorMessage
| order by Timestamp desc
```

The table drills into the detailed synchronization events for users. Use this to do detailed diagnostics.

## Steps to import the sample dashboard:
  1. Import the file "dashboard-CSAppInsights.json".
  
  <div align=center><img src="./img/ImportDashboard.png" width="600" ></div>

  2. Name the dashboard appropriately and then click to select datasources
  
  <div align=center><img src="./img/Datasources.png" width="450" ></div>
  
  3. In the Datasource selection pane you have to put your Azure Application Insights subscriptionID in the placeholder .
  
  <div align=center><img src="./img/SubscriptionId.png" width="350" height="225"></div>
  <div align=center><img src="./img/SubscriptionIdAndDatasource.png" width="350" height="650"></div>

  4. After updating the correct subscriptionID. click on connect.

  5. You will get a list of databases. Select your Application Insights name from that list and save changes.

  6. your dashboard should have data now. Feel free to edit the queries to suit your needs. 
