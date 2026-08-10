targetScope = 'resourceGroup'

@description('Resource ID of the Log Analytics workspace that receives Azure Arc Heartbeat records.')
param workspaceResourceId string

@description('Azure region for the scheduled query alert rule. Defaults to the deployment resource group location.')
param location string = resourceGroup().location

@description('Scheduled query alert rule name.')
param alertRuleName string = 'store-monitoring-device-offline'

@description('Number of minutes since the last heartbeat before a device is considered offline.')
@minValue(1)
@maxValue(1440)
param offlineThresholdMinutes int = 5

@description('Number of days to look back for devices that are expected to report heartbeat. Increase this if devices report infrequently; reduce it to avoid alerting on retired devices.')
@minValue(1)
@maxValue(30)
param activeDeviceLookbackDays int = 7

@description('When true, the Device Offline alert only returns results during the configured UTC business-hours window.')
param businessHoursOnly bool = true

@description('UTC hour when the Device Offline alert window starts. The start hour is inclusive.')
@minValue(0)
@maxValue(23)
param businessHoursStartHourUtc int = 8

@description('UTC hour when the Device Offline alert window ends. The end hour is exclusive. Use 17 for 5 PM UTC.')
@minValue(0)
@maxValue(23)
param businessHoursEndHourUtc int = 17

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

@description('Scheduled query alert time window. ISO 8601 duration format.')
param windowSize string = 'PT5M'

@description('Automatically resolve the alert when the device sends heartbeat again and the query no longer returns a row. Set false to leave fired alerts active until manually resolved.')
param autoMitigate bool = false

@description('Existing Azure Monitor action group resource IDs to notify when the alert fires.')
param actionGroupResourceIds array = []

@description('Optional alert relay HTTP endpoint, such as the Store Monitoring Alert Function URL. When provided, this template creates an action group with Common Alert Schema enabled.')
@secure()
param alertFunctionWebhookUri string = ''

@description('Name of the action group to create when alertFunctionWebhookUri is provided.')
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
var deviceOfflineQuery = format(
  '''
let OfflineThresholdMinutes = {0};
let ActiveDeviceLookback = {1}d;
let BusinessHoursOnly = {2};
let BusinessHoursStartHourUtc = {3};
let BusinessHoursEndHourUtc = {4};
let WindowEnd = now();
let CurrentHourUtc = datetime_part("hour", WindowEnd);
let IsInsideBusinessHoursUtc =
  not(BusinessHoursOnly)
  or BusinessHoursStartHourUtc == BusinessHoursEndHourUtc
  or (BusinessHoursStartHourUtc < BusinessHoursEndHourUtc and CurrentHourUtc >= BusinessHoursStartHourUtc and CurrentHourUtc < BusinessHoursEndHourUtc)
  or (BusinessHoursStartHourUtc > BusinessHoursEndHourUtc and (CurrentHourUtc >= BusinessHoursStartHourUtc or CurrentHourUtc < BusinessHoursEndHourUtc));
Heartbeat
| where IsInsideBusinessHoursUtc
| where TimeGenerated between ((WindowEnd - ActiveDeviceLookback) .. WindowEnd)
| where ResourceProvider =~ "Microsoft.HybridCompute"
| summarize LastHeartbeat = max(TimeGenerated) by Computer
| extend MinutesSinceLastHeartbeat = datetime_diff("minute", WindowEnd, LastHeartbeat)
| where MinutesSinceLastHeartbeat > OfflineThresholdMinutes
| project DeviceName = Computer
| distinct DeviceName
''',
  offlineThresholdMinutes,
  activeDeviceLookbackDays,
  businessHoursOnly ? 'true' : 'false',
  businessHoursStartHourUtc,
  businessHoursEndHourUtc
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

resource deviceOfflineAlert 'Microsoft.Insights/scheduledQueryRules@2022-06-15' = {
  name: alertRuleName
  location: location
  kind: 'LogAlert'
  properties: {
    displayName: 'Store Monitoring - Device Offline'
    description: 'An Arc-connected store device has been offline for more than ${offlineThresholdMinutes} minutes.'
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
          query: deviceOfflineQuery
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
        alertType: 'DeviceOffline'
        offlineThresholdMinutes: '${offlineThresholdMinutes}'
        businessHoursOnly: '${businessHoursOnly}'
        businessHoursStartHourUtc: '${businessHoursStartHourUtc}'
        businessHoursEndHourUtc: '${businessHoursEndHourUtc}'
      }
    }
  }
}

output alertRuleResourceId string = deviceOfflineAlert.id
output actionGroupResourceIds array = alertActionGroupResourceIds
output query string = deviceOfflineQuery
