# Architecture Documentation

## Store Monitoring Agent Architecture

### Overview

The Store Monitoring Agent provides centralized monitoring and management of Windows-based Point-of-Sale (POS) devices across retail locations using Azure Arc, Azure Monitor Agent, Azure Monitor alerts, and Microsoft Copilot Studio. It supports both interactive investigations and alert-triggered automated investigations.

## High-Level Architecture

![Architecture](image.png)

## Alert Mechanism

Azure Monitor continuously evaluates telemetry in Log Analytics. When an alert condition is met, the alert is relayed through an Azure Function to the Copilot Studio Agent Flow for investigation and notification.

```mermaid
%%{init: {"theme": "base", "themeVariables": {"fontFamily": "Segoe UI, sans-serif", "fontSize": "16px", "lineColor": "#475569", "primaryTextColor": "#172033"}}}%%
flowchart TB
  subgraph detection["1  DETECT"]
    direction TB
    logs["Log Analytics<br/>POS telemetry"]
    rules["Scheduled query alerts<br/>Device offline · Retail Server · Database size"]
    action["Action Group<br/>Common Alert Schema"]
    logs -->|Evaluate KQL| rules
    rules -->|Alert fires| action
  end

  subgraph relay["2  RELAY SECURELY"]
    direction LR
    function["Alert Function<br/>Validate and relay payload"]
    entra["Microsoft Entra ID<br/>Service principal"]
    function <-.->|OAuth token| entra
  end

  subgraph investigate["3  INVESTIGATE AND NOTIFY"]
    direction TB
    flow["Copilot Studio Agent Flow<br/>Route by alert type"]
    agent["Store Monitoring Agent<br/>Investigate affected device"]
    teams["Microsoft Teams<br/>Alert details and findings"]
    flow -->|Investigation prompt| agent
    agent -->|Investigation result| flow
    flow -->|Post notification| teams
  end

  action -->|HTTPS POST| function
  function -->|Original alert payload| flow

  classDef monitor fill:#DCEEFF,stroke:#1769AA,color:#102A43,stroke-width:2px;
  classDef alert fill:#FFF1CC,stroke:#B7791F,color:#4A2C00,stroke-width:2px;
  classDef secure fill:#E5E7EB,stroke:#475569,color:#172033,stroke-width:2px;
  classDef copilot fill:#E8E0F7,stroke:#6B46A1,color:#2D1B4E,stroke-width:2px;
  classDef outcome fill:#DDF5E5,stroke:#238636,color:#123D20,stroke-width:2px;

  class logs monitor;
  class rules,action alert;
  class function,entra secure;
  class flow,agent copilot;
  class teams outcome;

  style detection fill:#F7FBFF,stroke:#1769AA,stroke-width:2px
  style relay fill:#F8FAFC,stroke:#64748B,stroke-width:2px
  style investigate fill:#FAF8FD,stroke:#6B46A1,stroke-width:2px
```

1. Scheduled query alert rules evaluate Log Analytics data for device availability, Retail Server response time, and offline database size.
2. A triggered rule invokes an Azure Monitor action group that sends the Common Alert Schema payload to the Store Monitoring Alert Function over HTTPS.
3. The Function validates the JSON request, obtains a Microsoft Entra access token using its dedicated service principal, and relays the original payload unchanged to the Agent Flow.
4. The Agent Flow extracts the device and alert metadata, routes the request using `data.customProperties.alertType`, and invokes the Store Monitoring Agent with the matching investigation prompt.
5. The Agent Flow posts the investigation result and alert metadata to Microsoft Teams.

Alert rules are split by `DeviceName`, allowing each affected device to be tracked independently. For deployment, configuration, and security details, see [Alert-Triggered Agent](alert-triggered-agent.md).

## Component Details

### 1. POS Devices

**Components**:

- Windows 10/11 devices
- Azure Connected Machine Agent (AzCM)
- Azure Monitor Agent (AMA)

**Responsibilities**:

- Run POS applications
- Collect logs and performance metrics
- Send data to Azure (outbound only)
- Maintain heartbeat to Azure Arc

**Communication**:

- **Protocol**: HTTPS
- **Port**: 443 (outbound only)
- **Direction**: POS → Azure (no inbound)
- **Frequency**: Continuous (real-time events, periodic metrics)

### 2. Management & Governance Layer

#### Azure Arc

**Purpose**: Device lifecycle management and governance

**Capabilities**:

- Device registration and identity
- Centralized management
- Extension deployment (AMA)
- Policy enforcement
- Inventory and tagging

**Key Features**:

- Hybrid connectivity
- Projected as Azure resources
- RBAC integration
- Azure Resource Manager integration

#### Azure Policy

**Purpose**: Automated compliance and configuration management

**Policy Initiative Includes**:

1. Deploy AMA extension on Arc Windows machines
2. Associate DCR with Arc machines
3. Enable dependency agent (optional)

**Enforcement**:

- **Mode**: DeployIfNotExists
- **Scope**: Resource Group or Subscription
- **Remediation**: Automatic via managed identity

### 3. Data Collection Layer

#### Azure Monitor Agent (AMA)

**Purpose**: Unified agent for data collection

**Advantages over Legacy Agents**:

- Centralized configuration via DCR
- Support for multi-homing
- Enhanced security (managed identities)
- Better performance
- Azure Arc native

**Collection Methods**:

- Windows Event Logs (Application, System, Security)
- Performance Counters
- Custom logs (optional)

#### Data Collection Rules (DCR)

**Purpose**: Define what data to collect and where to send it

**DCR Components**:

- **Data Sources**: Event logs, performance counters
- **Destinations**: Log Analytics workspace(s)
- **Transformations**: KQL-based filtering (optional)
- **Data Flows**: Routing rules

**Solution DCRs**:

1. **dcr-windows-events**: General Windows events and performance

### 4. Storage & Analytics Layer

#### Log Analytics Workspace

**Purpose**: Centralized data repository and query engine

**Tables Used**:

- **Event**: Windows Event Logs
- **Perf**: Performance counters
- **Heartbeat**: Device availability
- **Custom tables**: (optional)

### 5. AI & Query Layer

#### Agent Flow

**Purpose**: Middleware for executing KQL queries against Log Analytics

### 6. User Interface Layer

#### Microsoft Copilot Studio

**Purpose**: Conversational AI interface for monitoring

**Components**:

- **Topics**: Predefined conversation flows (Device Health, Errors, Performance)
- **Actions**: Agent Flow integration

**Channels**:

- M365 Copilot
- Microsoft Teams

## Data Flow

### 1. Data Collection Flow

```
POS Device
  ↓ (Events occur)
Windows Event Log / Performance Counters
  ↓ (AMA reads)
Azure Monitor Agent
  ↓ (Filters per DCR)
Data Collection Endpoint (DCE)
  ↓ (Transforms if needed)
Log Analytics Ingestion API
  ↓ (Writes)
Log Analytics Workspace Tables
```
