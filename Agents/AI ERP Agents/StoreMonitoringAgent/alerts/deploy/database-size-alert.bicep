targetScope = 'resourceGroup'

@description('Resource ID of the Log Analytics workspace that receives DatabaseMetricsService Event records.')
param workspaceResourceId string

@description('Azure region for the scheduled query alert rule. Defaults to the deployment resource group location.')
param location string = resourceGroup().location

@description('Scheduled query alert rule name.')
param alertRuleName string = 'store-monitoring-database-size'

@description('Database size threshold in MB. 8192 MB equals 8 GB.')
@minValue(1)
param databaseSizeThresholdMB int = 8192

@description('How far back each alert evaluation should inspect DatabaseMetricsService reports. KQL duration format.')
param queryLookback string = '24h'

@description('Whether the alert rule is enabled after deployment.')
param enabled bool = true

@description('Azure Monitor alert severity. 0 is highest, 4 is lowest.')
@allowed([
  0
  1
  2
  3
  4
])
param severity int = 2

@description('How often Azure Monitor evaluates the query. ISO 8601 duration format.')
param evaluationFrequency string = 'PT24H'

@description('Scheduled query alert time window. ISO 8601 duration format. This should cover queryLookback so the latest metric is available even when collection is less frequent.')
param windowSize string = 'PT24H'

@description('Automatically resolve the alert when the latest database metrics report no longer exceeds the threshold. Set false to leave fired alerts active until manually resolved.')
param autoMitigate bool = false

@description('Existing Azure Monitor action group resource IDs to notify when the alert fires.')
param actionGroupResourceIds array = []

@description('Optional alert relay HTTP endpoint, such as the Store Monitoring Alert Function URL. When provided, this template creates or updates an action group with Common Alert Schema enabled.')
@secure()
param alertFunctionWebhookUri string = ''

@description('Name of the action group to create or update when alertFunctionWebhookUri is provided.')
param actionGroupName string = 'store-monitoring-agent-alerts'

@description('Short name for the created action group. Azure Monitor requires 12 characters or fewer.')
@maxLength(12)
param actionGroupShortName string = 'SMAgent'

@description('Webhook receiver name for the created action group.')
param webhookReceiverName string = 'AlertFunction'

@description('Skip Azure Monitor query validation during deployment. Keep false unless deploying before data exists in the workspace.')
param skipQueryValidation bool = false

var shouldCreateActionGroup = !empty(alertFunctionWebhookUri)
var alertFunctionWebhookReceiver = {
  name: webhookReceiverName
  serviceUri: alertFunctionWebhookUri
  useCommonAlertSchema: true
}
var databaseSizeQuery = format(
  '''
let DatabaseSizeThresholdMB = {0};
let Lookback = {1};
Event
| where TimeGenerated > ago(Lookback)
| where Source == "DatabaseMetricsService"
| where EventID == 3000
| extend DeviceName = Computer
| extend MetricsText = strcat(RenderedDescription, " ", ParameterXml)
| extend
    DatabaseName = extract(@"Database:\s*([^\r\n]+)", 1, MetricsText),
    ServerName = extract(@"Server:\s*([^\r\n]+)", 1, MetricsText),
    DatabaseSizeMB = todouble(extract(@"Total Database Size:\s*([0-9.]+)\s*MB", 1, MetricsText)),
    DataFileSizeMB = todouble(extract(@"Data File Size:\s*([0-9.]+)\s*MB", 1, MetricsText)),
    LogFileSizeMB = todouble(extract(@"Log File Size:\s*([0-9.]+)\s*MB", 1, MetricsText)),
    UnallocatedSpaceMB = todouble(extract(@"Unallocated Space:\s*([0-9.]+)\s*MB", 1, MetricsText))
| where isnotnull(DatabaseSizeMB)
| summarize arg_max(TimeGenerated, DatabaseSizeMB, DataFileSizeMB, LogFileSizeMB, UnallocatedSpaceMB, ServerName) by DeviceName, DatabaseName
| where DatabaseSizeMB > DatabaseSizeThresholdMB
| distinct DeviceName
''',
  databaseSizeThresholdMB,
  queryLookback
)

resource actionGroup 'Microsoft.Insights/actionGroups@2023-01-01' = if (shouldCreateActionGroup) {
  name: actionGroupName
  location: 'Global'
  properties: {
    groupShortName: actionGroupShortName
    enabled: true
    webhookReceivers: [
      alertFunctionWebhookReceiver
    ]
  }
}

var createdActionGroupResourceIds = shouldCreateActionGroup ? [actionGroup.id] : []
var alertActionGroupResourceIds = concat(actionGroupResourceIds, createdActionGroupResourceIds)

resource databaseSizeAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: alertRuleName
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'Store Monitoring - Database Size'
    description: 'A POS offline database size exceeded ${databaseSizeThresholdMB} MB.'
    enabled: enabled
    severity: severity
    scopes: [
      workspaceResourceId
    ]
    evaluationFrequency: evaluationFrequency
    windowSize: windowSize
    autoMitigate: autoMitigate
    skipQueryValidation: skipQueryValidation
    criteria: {
      allOf: [
        {
          query: databaseSizeQuery
          timeAggregation: 'Count'
          operator: 'GreaterThan'
          threshold: 0
          dimensions: [
            {
              name: 'DeviceName'
              operator: 'Include'
              values: [
                '*'
              ]
            }
          ]
          failingPeriods: {
            numberOfEvaluationPeriods: 1
            minFailingPeriodsToAlert: 1
          }
        }
      ]
    }
    actions: {
      actionGroups: alertActionGroupResourceIds
      customProperties: {
        alertType: 'DatabaseSize'
        databaseSizeThresholdMB: '${databaseSizeThresholdMB}'
      }
    }
  }
}

output alertRuleResourceId string = databaseSizeAlert.id
output actionGroupResourceIds array = alertActionGroupResourceIds
output query string = databaseSizeQuery
