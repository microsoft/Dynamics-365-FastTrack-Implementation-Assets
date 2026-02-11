# Azure Service Bus Component for Dynamics 365 Commerce Integration

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

The Azure Service Bus component ensures reliable message queuing for decoupling event generation from further processing within **Dynamics 365 Commerce**, the **Events Framework**, and **Customer Insights Journeys**. It facilitates seamless communication between different services, enhancing the scalability and resilience of your commerce solutions.


## Further Learning

For a deep dive and further learning on Azure Service Bus, refer to the [Azure Service Bus Documentation](https://learn.microsoft.com/en-us/azure/service-bus-messaging/service-bus-messaging-overview).

## Features

- **Message Reliability**
  - Messages are added to a Service Bus topic, ensuring that multiple subscribers, such as Azure Logic Apps, can reliably receive and process them.

- **Error Management**
  - In cases of delivery failure, messages are moved to a dead-letter queue for analysis, ensuring no event is lost.

- **Scalability**
  - Service Bus handles high volumes of events efficiently, allowing the system to scale by adding more subscribers as needed.

## Architecture

![Integration Design](../Data/Commerce_CIJ_BetterTogether_SyncAzureIntegrationDesign.png)

The Azure Service Bus component integrates with Dynamics 365 Commerce by decoupling event generation from processing. It uses topics and subscriptions to manage message flow, enabling multiple services to consume events independently. This architecture supports high availability and scalability, ensuring that your commerce operations run smoothly even under heavy load.

## Prerequisites

- **Azure Subscription**: Ensure you have an active Azure subscription.
- **Azure CLI or Azure Portal Access**: For deploying ARM templates.
- **Permissions**: Appropriate permissions to create and manage Azure Service Bus resources.
- **Dynamics 365 Commerce Setup**: Integrated with the Events Framework and Customer Insights Journeys.

## Deployment

To deploy the Azure Service Bus component, follow the [Azure Resource Manager (ARM) template deployment guide](https://learn.microsoft.com/en-us/azure/azure-resource-manager/templates/quickstart-create-templates-use-the-portal).

## Configuration

The ARM template sets up the following resources:

- **Service Bus Namespace**
  - **Name**: `d365bettertogether-ns` (modifiable via parameters)
  - **Location**: East US
  - **SKU**: Standard

- **Authorization Rules**
  - **RootManageSharedAccessKey**: Provides Listen, Manage, and Send rights.

- **Network Rule Sets**
  - **Public Network Access**: Enabled with default action set to Allow.

- **Topics**
  - **order-events**
    - **Max Message Size**: 256 KB
    - **Message Time to Live**: 14 Days
    - **Max Size**: 1 GB

- **Subscriptions**
  - **order-subscription**
    - **Lock Duration**: 1 Minute
    - **Max Delivery Count**: 10
    - **Auto Delete On Idle**: 14 Days
    - **Dead-Lettering**: Disabled for message expiration and filter evaluation exceptions

### Parameters

| Parameter Name                      | Description                         | Default Value            |
|-------------------------------------|-------------------------------------|--------------------------|
| `namespaces_d365bettertogether_ns_name` | Name of the Service Bus namespace    | `d365bettertogether-ns`  |

## Integration

### Dependencies

Before integrating the Azure Service Bus component, Start at the beginning of the documentation [README](../README.md)

Ensure that the [Commerce Events Framework](../Docs/commerce_event_framework.md) document is followed. This document outlines the necessary steps and configurations required for the Events Framework to function correctly with Azure Service Bus.

Ensure that the [Azure Cosmos DB](../Docs/azure_cosmos_db.md) document is followed. 

## Monitoring

Azure Service Bus offers comprehensive monitoring capabilities:

- **Azure Monitor**: Track metrics such as incoming messages, outgoing messages, and active connections.
- **Alerts**: Configure alerts for key performance indicators and failure conditions.
- **Diagnostics Logs**: Enable logging for detailed insights into operations and message flows.

## Security

- **Network Access**
  - Public network access is enabled.
  - IP rules can be configured as needed to restrict access.

- **Authentication**
  - Uses Shared Access Policies for securing access.
  - Roles:
    - **Listen**
    - **Send**
    - **Manage**

- **Data Encryption**
  - Data at rest and in transit is encrypted using industry-standard protocols.

- **Access Control**
  - Role-Based Access Control (RBAC) ensures least privilege access to Service Bus resources.

## Troubleshooting

- **Deployment Issues**
  - Verify ARM template syntax.
  - Ensure you have the necessary permissions.
  - Check Azure service status for any outages.

- **Message Delivery Failures**
  - Inspect dead-letter queues for failed messages.
  - Review subscription rules and filters for correctness.

- **Performance Bottlenecks**
  - Monitor Service Bus metrics and scale the namespace or add more partitions as needed.
  - Optimize message size and TTL settings to enhance performance.

- **Connectivity Problems**
  - Ensure network rules and IP restrictions are correctly configured.
  - Verify firewall settings and virtual network integrations.