# Architecture Documentation

## Store Monitoring Solution Architecture

### Overview

The Store Monitoring solution provides centralized monitoring and management of Windows-based Point-of-Sale (POS) devices across retail locations using Azure Arc, Azure Monitor Agent, and Microsoft Copilot Studio.

## High-Level Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                          AZURE CLOUD                               │
├───────────────────────────────────────────────────────────────────┤
│                                                                     │
│  ┌────────────────┐                                                │
│  │   Azure Arc    │  ← Device Registration & Management            │
│  │   Management   │                                                │
│  └────────┬───────┘                                                │
│           │                                                         │
│           │ Governance                                             │
│           ▼                                                         │
│  ┌────────────────┐       ┌─────────────────┐                     │
│  │ Azure Policy   │──────►│ Policy Assigned │                     │
│  │  Initiative    │       │  to Arc Devices │                     │
│  └────────────────┘       └─────────────────┘                     │
│           │                                                         │
│           │ Auto-deploy AMA + DCR                                  │
│           ▼                                                         │
│  ┌────────────────┐       ┌─────────────────┐                     │
│  │ Azure Monitor  │──────►│ Data Collection │                     │
│  │  Agent (AMA)   │       │   Rules (DCR)   │                     │
│  └────────┬───────┘       └─────────────────┘                     │
│           │                                                         │
│           │ Event & Perf Data                                      │
│           ▼                                                         │
│  ┌────────────────────────────────────┐                           │
│  │     Log Analytics Workspace        │                           │
│  │  ┌──────────┬──────────┬────────┐ │                           │
│  │  │  Event   │   Perf   │Heartbeat│ │                           │
│  │  │  Table   │  Table   │ Table   │ │                           │
│  │  └──────────┴──────────┴────────┘ │                           │
│  └────────────────┬───────────────────┘                           │
│                   │                                                 │
│                   │ Direct KQL Query (via Knowledge Source)       │
│                   ▲                                                 │
│  ┌────────────────┴───────────────────┐                           │
│  │   Microsoft Copilot Studio Agent   │                           │
│  │  ┌──────────────────────────────┐  │                           │
│  │  │ Natural Language → KQL       │  │                           │
│  │  │ Direct Log Analytics Access  │  │                           │
│  │  └──────────────────────────────┘  │                           │
│  └────────────────┬───────────────────┘                           │
│                   │                                                 │
└───────────────────┼─────────────────────────────────────────────┘
                    │
                    │ User Interaction
                    ▼
            ┌──────────────┐
            │    Users     │
            │ (IT Staff,   │
            │  Managers)   │
            └──────────────┘

                    ▲
                    │ HTTPS:443 (Outbound Only)
                    │
    ┌───────────────┴───────────────┐
    │                               │
┌───▼───────┐              ┌────────▼────┐
│ Store A   │              │  Store B    │
├───────────┤              ├─────────────┤
│ POS-01    │              │ POS-05      │
│ POS-02    │              │ POS-06      │
│ POS-03    │              │ POS-07      │
│ POS-04    │              │ POS-08      │
└───────────┘              └─────────────┘
```

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
