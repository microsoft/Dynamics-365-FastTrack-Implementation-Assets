# Azure Logic App Component for Dynamics 365 Commerce Integration

## Table of Contents

- [Overview](#overview)
- [Further Learning](#further-learning)
- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Deployment](#deployment)
- [Configuration](#configuration)
- [Integration](#integration)
- [Monitoring](#monitoring)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

## Overview

The Azure Logic App component orchestrates the integration process within **Dynamics 365 Commerce**, the **Events Framework**, and **Customer Insights Journeys**. It ensures that enriched event data reaches Customer Insights – Journeys reliably and efficiently, managing complex workflows with a low-code interface.

## Further Learning

For a deep dive and further learning on Azure Logic Apps, refer to the [Azure Logic Apps Documentation](https://learn.microsoft.com/en-us/azure/logic-apps/).

## Features

- **Message Retrieval**
  - Logic Apps listen to Azure Service Bus for new messages. Upon receiving them, Logic Apps start the workflow to process customer data.

- **Data Transformation**
  - Transforms enriched data into a format suitable for Customer Insights – Journeys, ensuring all data conforms to the expected structure.

- **Conditional Logic and Creation**
  - Checks if the contact already exists in Customer Insights. If not, creates new contacts and links existing customer information.

- **Error Handling**
  - Built-in mechanisms for retries, ensuring temporary failures in downstream services are retried before escalation.

- **Triggering Customer Journeys**
  - Once customer data is verified and enriched, Logic Apps trigger specific journeys in Customer Insights, such as personalized campaigns or loyalty program invitations.

## Architecture

![Integration Design](../Data/Commerce_CIJ_BetterTogether_SyncAzureIntegrationDesign.png)

The Azure Logic App component integrates with Dynamics 365 Commerce by orchestrating workflows that process and transform event data. It interacts with Azure Service Bus to retrieve messages, transforms data as needed, interacts with Microsoft Dataverse for data operations, and triggers Customer Insights – Journeys to initiate personalized customer engagements.

## Prerequisites

- **Azure Subscription**: Ensure you have an active Azure subscription.
- **Azure CLI or Azure Portal Access**: For deploying ARM templates.
- **Permissions**: Appropriate permissions to create and manage Azure Logic Apps and related resources.
- **Dynamics 365 Commerce Setup**: Integrated with the Events Framework and Customer Insights Journeys.

## Deployment

To deploy the Azure Logic App component, follow the [Azure Resource Manager (ARM) template deployment guide](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/quickstart-create-templates-use-the-portal).

## Configuration

The ARM template sets up the following resources:

- **Logic App**
  - **Name**: `d365bettertogether-logicapp` (modifiable via parameters)
  - **Location**: East US
  - **Triggers**: Configured to listen to a specific Service Bus topic and subscription, polling for new messages every minute.

- **Connections**
  - **Service Bus**: For receiving messages.
  - **Web Contents**: For making HTTP requests to external services.
  - **Dataverse**: For interacting with Microsoft Dataverse entities.

- **Workflow Actions**
  - **Parse Service Bus Payload**
    - Parses the raw Service Bus message payload into JSON using the `ParseJson` action.
    - Extracts key details about orders, customers, and events.

  - **Integration with Dataverse**
    - Fetches relevant data from Microsoft Dataverse via API calls based on attributes in the parsed payload.
    - Verifies and/or creates records in Dataverse, including contacts and other customer-related entities.

  - **Email Check**
    - Verifies if a contact already exists in Dataverse based on the provided receipt email from the parsed payload.
    - Uses existing contact if a match is found; otherwise, creates a new contact.

  - **Custom Trigger Invocation**
    - Invokes a custom trigger (specified by the `CustomTriggerName` parameter) with the checkout event details, including order information such as amount paid, currency, and sales ID.

  - **Error Handling**
    - Includes conditional logic to handle scenarios such as missing or invalid data.
    - Retries temporary failures before escalating issues.

### Parameters

| Parameter Name            | Description                                 | Default Value                |
|---------------------------|---------------------------------------------|------------------------------|
| `logicAppName`            | Name of the Logic App                       | `d365bettertogether-logicapp`|
| `CustomTriggerName`       | Name of the custom trigger to invoke        | `CustomTriggerName`          |

## Integration

### Dependencies

Before integrating the Azure Service Bus component, Start at the beginning of the documentation [README](../README.md)

Ensure that the [Commerce Events Framework](../Docs/commerce_event_framework.md) document is followed. This document outlines the necessary steps and configurations required for the Events Framework to function correctly with Azure Service Bus.

Ensure that the [Azure Cosmos DB](../Docs/azure_cosmos_db.md) document is followed. 

Ensure that the [Azure Service Bus](../Docs/azure_service_bus.md) document is followed. 

## Monitoring

Azure Logic Apps offers comprehensive monitoring capabilities:

- **Azure Monitor**: Track metrics such as workflow runs, success rates, and failure rates.
- **Alerts**: Configure alerts for key performance indicators and failure conditions.
- **Diagnostics Logs**: Enable logging for detailed insights into workflow executions and errors.

## Security

- **Network Access**
  - Public network access is enabled.
  - IP rules can be configured as needed to restrict access.

- **Authentication**
  - Uses Managed Identity or service principals for securing connections.
  - Ensures secure access to connected services like Service Bus and Dataverse.

- **Data Encryption**
  - Data at rest and in transit is encrypted using industry-standard protocols.

- **Access Control**
  - Role-Based Access Control (RBAC) ensures least privilege access to Logic App resources.

## Troubleshooting

- **Deployment Issues**
  - Verify ARM template syntax.
  - Ensure you have the necessary permissions.
  - Check Azure service status for any outages.

- **Workflow Failures**
  - Inspect Logic App run history for failed actions.
  - Review error messages and stack traces for debugging.
  - Ensure that connected services (Service Bus, Dataverse) are accessible and configured correctly.

- **Performance Bottlenecks**
  - Monitor Logic App performance metrics.
  - Optimize workflow actions to reduce latency.
  - Scale out Logic Apps if necessary.

- **Connectivity Problems**
  - Ensure network rules and IP restrictions are correctly configured.
  - Verify firewall settings and virtual network integrations for connected services.
