# MCP Tools Reference

This document provides a quick reference for all available tools in the Microsoft Release Planner MCP Server.

## Available Tools

### 1. search_release_plans

Search and filter Microsoft Release Planner features across Dynamics 365 and Power Platform products.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| product | string | No | Product name to filter (e.g., 'Dynamics 365 Sales', 'Power Automate') |
| featureKeyword | string | No | Keyword to search in feature names, feature details, and business value |
| releaseWave | string | No | Release wave (e.g., '2025 release wave 1') |
| status | enum | No | Feature status: 'early_access', 'public_preview', 'ga', 'all' |
| investmentArea | string | No | Investment area (e.g., 'Copilot and AI innovation') |
| limit | number | No | Maximum number of results (default: 20) |

**Example Usage:**

```json
{
  "product": "Dynamics 365 Sales",
  "investmentArea": "Copilot and AI innovation",
  "releaseWave": "2025 release wave 1",
  "status": "ga",
  "limit": 10
}
```

**Sample Response:**

```
Found 16 matching features:

1. Dynamics 365 Sales: Sales Qualification Agent
   Status: GA 04/01/2025, Preview 02/01/2025
   Wave: 2025 release wave 1
   Area: Copilot and AI innovation

2. Dynamics 365 Sales: Copilot in Sales
   Status: GA 03/01/2025, Preview 01/15/2025
   Wave: 2025 release wave 1
   Area: Copilot and AI innovation
```

**cURL Example:**

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc":"2.0",
    "id":2,
    "method":"tools/call",
    "params":{
      "name":"search_release_plans",
      "arguments":{
        "product":"Dynamics 365 Supply Chain Management",
        "releaseWave":"2025 release wave 1",
        "limit":2
      }
    }
  }'
```

---

### 2. list_products

Get a list of all products available in the Release Planner, optionally with feature counts.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| includeCount | boolean | No | Include feature count per product (default: false) |

**Example Usage:**

```json
{
  "includeCount": true
}
```

**Sample Response:**

With `includeCount: true`:
```
Total Products: 32

Dynamics 365 Sales (125 features)
Dynamics 365 Supply Chain Management (98 features)
Power Automate (87 features)
Power Apps (76 features)
...
```

With `includeCount: false`:
```
Total Products: 32

Dynamics 365 Sales
Dynamics 365 Supply Chain Management
Power Automate
Power Apps
...
```

**cURL Example:**

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc":"2.0",
    "id":3,
    "method":"tools/call",
    "params":{
      "name":"list_products",
      "arguments":{"includeCount":true}
    }
  }'
```

---

### 3. get_release_wave_summary

Get a comprehensive summary of a specific release wave, including feature counts by product and investment area.

**Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| releaseWave | string | Yes | Release wave name (e.g., '2025 release wave 1') |

**Example Usage:**

```json
{
  "releaseWave": "2025 release wave 1"
}
```

**Sample Response:**

```markdown
# 2025 release wave 1 Summary

## Overview
- Total Features: 500
- GA Features: 350
- Public Preview: 280
- Early Access: 5

## Top Products
  - Dynamics 365 Sales: 75 features
  - Dynamics 365 Supply Chain Management: 68 features
  - Power Automate: 62 features
  - Power Apps: 58 features
  ...

## Top Investment Areas
  - Copilot and AI innovation: 120 features
  - User experience: 85 features
  - Performance: 72 features
  ...
```

**cURL Example:**

```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc":"2.0",
    "id":4,
    "method":"tools/call",
    "params":{
      "name":"get_release_wave_summary",
      "arguments":{
        "releaseWave":"2025 release wave 1"
      }
    }
  }'
```

---

## Common Use Cases

### Finding Copilot Features

**Copilot Studio Prompt:**
> "Show me all Copilot and AI features in Dynamics 365 Sales"

**MCP Tool Call:**
```json
{
  "name": "search_release_plans",
  "arguments": {
    "product": "Dynamics 365 Sales",
    "investmentArea": "Copilot and AI innovation",
    "status": "ga"
  }
}
```

---

### Exploring a Product's Release Wave

**Copilot Studio Prompt:**
> "List features for Dynamics 365 Supply Chain Management 2025 release wave 1"

**MCP Tool Call:**
```json
{
  "name": "search_release_plans",
  "arguments": {
    "product": "Dynamics 365 Supply Chain Management",
    "releaseWave": "2025 release wave 1",
    "limit": 50
  }
}
```

---

### Release Wave Analysis

**Copilot Studio Prompt:**
> "What's in the 2025 release wave 2?"

**MCP Tool Call:**
```json
{
  "name": "get_release_wave_summary",
  "arguments": {
    "releaseWave": "2025 release wave 2"
  }
}
```

---

### Finding Specific Features

**Copilot Studio Prompt:**
> "Find features about automation in Power Automate"

**MCP Tool Call:**
```json
{
  "name": "search_release_plans",
  "arguments": {
    "product": "Power Automate",
    "featureKeyword": "automation"
  }
}
```

---

### Product Discovery

**Copilot Studio Prompt:**
> "What products are available?"

**MCP Tool Call:**
```json
{
  "name": "list_products",
  "arguments": {
    "includeCount": true
  }
}
```

---

## Status Types

- **early_access**: Features available for early access
- **public_preview**: Features in public preview
- **ga**: Generally available features
- **all**: All features regardless of status

---

## Investment Areas (Examples)

Common investment areas you can filter by:

- Copilot and AI innovation
- User experience
- Performance
- Security and compliance
- Integration
- Analytics and insights
- Mobile
- Administration

---

## Tips

1. **Use `limit` parameter** to control result size for large queries
2. **Combine multiple filters** for more specific results (product + releaseWave + investmentArea)
3. **Check release wave summaries first** to understand the scope before detailed searches
4. **Product names are case-insensitive** and support partial matches
5. **Use feature keywords** to find specific capabilities across all products
6. **Status filtering** helps you find what's available now (ga) vs. coming soon (public_preview)

---

## Feature Data Fields

Each feature returned by the API contains these fields:

| Field | Description |
|-------|-------------|
| **Product name** | The product this feature belongs to (e.g., "Dynamics 365 Sales") |
| **Feature name** | Name of the feature |
| **Investment area** | Category (e.g., "Copilot and AI innovation") |
| **Business value** | Description of the business impact |
| **Feature details** | Detailed description of the feature |
| **Enabled for** | Who the feature is enabled for (e.g., "Users by admins, makers, or analysts") |
| **Early access date** | When early access becomes available |
| **Public preview date** | When public preview becomes available |
| **GA date** | General availability date |
| **Public Preview Release Wave** | Which wave the preview is part of |
| **GA Release Wave** | Which wave the GA is part of |
| **Release Plan ID** | Unique identifier for the feature |
| **GeographicAreasDetails** | Geographic availability information |

> **Note:** The `search_release_plans` tool returns a summarized view (product, feature name, dates, wave, investment area). Use the full API data in `src/utils/api.ts` if you need access to all fields.

---

## API Notes

- All cURL examples require the `Accept: application/json, text/event-stream` header. Without it, the MCP transport returns a "Not Acceptable" error.
- All string filters are **case-insensitive** and use **partial matching** (e.g., "sales" matches "Dynamics 365 Sales").
- Data is cached for **1 hour** after the first API call. Subsequent requests within the TTL return cached results.
