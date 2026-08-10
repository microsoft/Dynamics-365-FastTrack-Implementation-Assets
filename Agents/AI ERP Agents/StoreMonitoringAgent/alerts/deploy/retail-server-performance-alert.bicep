targetScope = 'resourceGroup'

@description('Resource ID of the Log Analytics workspace that receives Store Commerce Event records.')
param workspaceResourceId string

@description('Azure region for the scheduled query alert rule. Defaults to the deployment resource group location.')
param location string = resourceGroup().location

@description('Scheduled query alert rule name.')
param alertRuleName string = 'store-monitoring-retail-server-performance'

@description('Retail Server request execution time threshold in milliseconds. 10000 ms equals 10 seconds.')
@minValue(1)
param performanceThresholdMs int = 10000

@description('How far back each alert evaluation should inspect Store Commerce Retail Server request duration events. KQL duration format. Keep this longer than the evaluation frequency to tolerate log ingestion delay.')
param queryLookback string = '10m'

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
param evaluationFrequency string = 'PT5M'

@description('Scheduled query alert time window. ISO 8601 duration format. This should cover queryLookback.')
param windowSize string = 'PT10M'

@description('Automatically resolve the alert when the query no longer returns a row for the affected device. Set false to leave fired alerts active until manually resolved.')
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
var retailServerPerformanceQuery = format(
  '''
let PerformanceThresholdMs = {0};
let Lookback = {1};
Event
| where TimeGenerated > ago(Lookback)
| where EventLog == "Application"
| where EventID == 40102
| where Source == "Microsoft Dynamics - Store Commerce"
| where EventData has "ModelManagersRetailServerRequestFinished" or RenderedDescription has "ModelManagersRetailServerRequestFinished"
| extend DeviceName = Computer
| extend ParsedXml = parse_xml(EventData)
| extend EventDataXml = ParsedXml.DataItem.EventData
| extend DataNodes = EventDataXml.Data
| mv-expand DataNode = DataNodes
| extend DataValue = tostring(DataNode)
| summarize DataValues = make_list(DataValue), arg_max(TimeGenerated, *) by EventData
| extend
    PayloadText = trim_start("payload: ", tostring(DataValues[6])),
    Scope = tostring(DataValues[7])
| extend Payload = parse_json(PayloadText)
| extend
  ExecutionTimeInMs = toint(Payload.executionTimeInMs)
| where ExecutionTimeInMs > PerformanceThresholdMs
| distinct DeviceName
''',
  performanceThresholdMs,
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

resource retailServerPerformanceAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: alertRuleName
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'Store Monitoring - Retail Server Performance'
    description: 'A Store Commerce Retail Server request exceeded ${performanceThresholdMs} ms on a POS device.'
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
          query: retailServerPerformanceQuery
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
        alertType: 'RetailServerPerformance'
        performanceThresholdMs: '${performanceThresholdMs}'
      }
    }
  }
}

output alertRuleResourceId string = retailServerPerformanceAlert.id
output actionGroupResourceIds array = alertActionGroupResourceIds
output query string = retailServerPerformanceQuery
