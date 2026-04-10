# Complete MCP Server Guide

A comprehensive step-by-step guide for creating, developing, and deploying Model Context Protocol (MCP) servers.

---

## Table of Contents

1. [Part 1: Creating an MCP Server](#part-1-creating-an-mcp-server)
2. [Part 2: Deploying to Azure](#part-2-deploying-to-azure)
3. [Part 3: Deploying on a Local PC/Laptop](#part-3-deploying-on-a-local-pclaptop)

---

# Part 1: Creating the Microsoft Release Planner MCP Server

This part walks you through building an MCP server that connects to the public [Microsoft Release Planner API](https://releaseplans.microsoft.com/) and exposes it as MCP tools. By the end, you'll have a working server that Copilot Studio (or any MCP client) can use to search Dynamics 365 and Power Platform release plans.

## Step 1: Prerequisites

Before starting, ensure you have the following installed:

### Required Software
- **Node.js** (version 20 or higher)
  - Download: https://nodejs.org/
  - Verify: `node --version`
- **npm** (comes with Node.js)
  - Verify: `npm --version`
- **Visual Studio Code** (recommended IDE)
  - Download: https://code.visualstudio.com/
- **Git** (for version control)
  - Download: https://git-scm.com/

### Verify Installation
```bash
node --version   # Should show v20.x.x or higher
npm --version    # Should show 10.x.x or higher
```

---

## Step 2: Initialize Your Project

### 2.1 Create Project Directory
```bash
mkdir ms-release-planner-mcp-server
cd ms-release-planner-mcp-server
```

### 2.2 Initialize npm Project
```bash
npm init -y
```

### 2.3 Update package.json
Edit `package.json` with the following configuration:

```json
{
  "name": "ms-release-planner-mcp-server",
  "version": "1.0.0",
  "description": "MCP server for Microsoft Release Planner API",
  "type": "module",
  "main": "build/index.js",
  "scripts": {
    "build": "tsc",
    "start": "node build/index-mcp.js",
    "dev": "npm run build && node build/index-mcp.js"
  },
  "keywords": ["mcp", "microsoft", "release-planner", "dynamics365", "power-platform"],
  "author": "",
  "license": "MIT"
}
```

> **Important**: The `"type": "module"` is required for ES modules support.

---

## Step 3: Install Dependencies

### 3.1 Install Production Dependencies
```bash
npm install @modelcontextprotocol/sdk express zod
```

| Package | Purpose |
|---------|---------|
| `@modelcontextprotocol/sdk` | MCP protocol implementation |
| `express` | HTTP server framework |
| `zod` | Runtime schema validation |

### 3.2 Install Development Dependencies
```bash
npm install --save-dev typescript @types/node @types/express
```

---

## Step 4: Configure TypeScript

### 4.1 Create tsconfig.json
Create a file named `tsconfig.json` in your project root:

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ES2022",
    "moduleResolution": "node",
    "outDir": "./build",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "build"]
}
```

---

## Step 5: Create Project Structure

### 5.1 Create Directory Structure
```bash
mkdir src
mkdir src/utils
```

Your project structure will look like this when complete:
```
ms-release-planner-mcp-server/
├── src/
│   ├── index-mcp.ts      # MCP server (HTTP, for Azure/Copilot Studio)
│   ├── index.ts           # MCP server (stdio, for Claude Desktop)
│   ├── types.ts           # Zod schemas and type definitions
│   └── utils/
│       └── api.ts         # Release Planner API client with caching
├── build/                 # Compiled JavaScript output (after build)
├── package.json
├── package-lock.json
└── tsconfig.json
```

---

## Step 6: Create Type Definitions

### 6.1 Create src/types.ts

This file defines Zod schemas that validate data from the Microsoft Release Planner API at runtime and provide TypeScript types for the tool input parameters.

```typescript
import { z } from 'zod';

// Release Plan Feature Schema - matches the API response structure
export const ReleasePlanFeatureSchema = z.object({
  ProductId: z.string(),
  "Product name": z.string(),
  "Feature name": z.string(),
  "Investment area": z.string(),
  "Business value": z.string(),
  "Feature details": z.string(),
  "Enabled for": z.string(),
  "Early access date": z.string(),
  "Public preview date": z.string(),
  "GA date": z.string(),
  "Public Preview Release Wave": z.string(),
  "GA Release Wave": z.string(),
  "Release Plan ID": z.string(),
  "GeographicAreasDetails": z.string(),
  "Last Gitcommit date": z.string()
});

export type ReleasePlanFeature = z.infer<typeof ReleasePlanFeatureSchema>;

// API Response Schema - wraps the feature array with pagination metadata
export const ReleasePlanResponseSchema = z.object({
  morerecords: z.boolean(),
  "paging-cookie-encoded": z.string(),
  totalrecords: z.string(),
  results: z.array(ReleasePlanFeatureSchema)
});

export type ReleasePlanResponse = z.infer<typeof ReleasePlanResponseSchema>;

// Tool Input Schemas - used to validate and parse tool arguments
export const SearchReleasePlansInputSchema = z.object({
  product: z.string().optional().describe("Product name to filter (e.g., 'Dynamics 365 Sales', 'Power Automate')"),
  featureKeyword: z.string().optional().describe("Keyword to search in feature names"),
  releaseWave: z.string().optional().describe("Release wave (e.g., '2025 release wave 1')"),
  status: z.enum(["early_access", "public_preview", "ga", "all"]).optional().describe("Feature status filter"),
  investmentArea: z.string().optional().describe("Investment area (e.g., 'Copilot and AI innovation')"),
  limit: z.number().optional().default(20).describe("Maximum number of results to return")
});

export const GetFeatureDetailsInputSchema = z.object({
  featureId: z.string().describe("Release Plan ID of the feature")
});

export const ListProductsInputSchema = z.object({
  includeCount: z.boolean().optional().default(false).describe("Include feature count per product")
});

export const GetReleaseWaveSummaryInputSchema = z.object({
  releaseWave: z.string().describe("Release wave name (e.g., '2025 release wave 1')")
});

export type SearchReleasePlansInput = z.infer<typeof SearchReleasePlansInputSchema>;
export type GetFeatureDetailsInput = z.infer<typeof GetFeatureDetailsInputSchema>;
export type ListProductsInput = z.infer<typeof ListProductsInputSchema>;
export type GetReleaseWaveSummaryInput = z.infer<typeof GetReleaseWaveSummaryInputSchema>;
```

> **Why Zod?** Zod provides both runtime validation (the API could return unexpected data) and TypeScript type inference (no need to define types separately). The tool input schemas validate arguments from Copilot Studio or other MCP clients before processing.

---

## Step 7: Create API Client with Caching

### 7.1 Create src/utils/api.ts

This file handles fetching data from the Microsoft Release Planner API, caching responses for 1 hour, and providing filtering/aggregation functions used by the MCP tools.

```typescript
import { ReleasePlanResponse, ReleasePlanResponseSchema, ReleasePlanFeature } from "../types.js";

const API_BASE_URL = "https://releaseplans.microsoft.com/en-US/allreleaseplans/";

// Cache for API data (1 hour TTL)
let cachedData: ReleasePlanFeature[] | null = null;
let cacheTime: number = 0;
const CACHE_TTL = 60 * 60 * 1000; // 1 hour

/**
 * Fetch all release plans from Microsoft Release Planner API
 * Uses caching to reduce API calls
 */
export async function fetchAllReleasePlans(): Promise<ReleasePlanFeature[]> {
  // Return cached data if still valid
  const now = Date.now();
  if (cachedData && (now - cacheTime) < CACHE_TTL) {
    return cachedData;
  }

  try {
    const response = await fetch(API_BASE_URL);
    if (!response.ok) {
      throw new Error(`API request failed: ${response.status} ${response.statusText}`);
    }

    const data = await response.json();
    const validated = ReleasePlanResponseSchema.parse(data);

    // Update cache
    cachedData = validated.results;
    cacheTime = now;

    return validated.results;
  } catch (error) {
    throw new Error(`Failed to fetch release plans: ${error}`);
  }
}

/**
 * Filter features based on provided criteria
 */
export function filterFeatures(
  features: ReleasePlanFeature[],
  filters: {
    product?: string;
    featureKeyword?: string;
    releaseWave?: string;
    status?: string;
    investmentArea?: string;
  }
): ReleasePlanFeature[] {
  let filtered = [...features];

  if (filters.product) {
    const productLower = filters.product.toLowerCase();
    filtered = filtered.filter(f =>
      f["Product name"].toLowerCase().includes(productLower)
    );
  }

  if (filters.featureKeyword) {
    const keywordLower = filters.featureKeyword.toLowerCase();
    filtered = filtered.filter(f =>
      f["Feature name"].toLowerCase().includes(keywordLower) ||
      f["Feature details"].toLowerCase().includes(keywordLower) ||
      f["Business value"].toLowerCase().includes(keywordLower)
    );
  }

  if (filters.releaseWave) {
    const waveLower = filters.releaseWave.toLowerCase();
    filtered = filtered.filter(f =>
      f["GA Release Wave"].toLowerCase().includes(waveLower) ||
      f["Public Preview Release Wave"].toLowerCase().includes(waveLower)
    );
  }

  if (filters.status && filters.status !== "all") {
    filtered = filtered.filter(f => {
      switch (filters.status) {
        case "early_access":
          return f["Early access date"] && f["Early access date"].trim() !== "";
        case "public_preview":
          return f["Public preview date"] && f["Public preview date"].trim() !== "";
        case "ga":
          return f["GA date"] && f["GA date"].trim() !== "";
        default:
          return true;
      }
    });
  }

  if (filters.investmentArea) {
    const areaLower = filters.investmentArea.toLowerCase();
    filtered = filtered.filter(f =>
      f["Investment area"].toLowerCase().includes(areaLower)
    );
  }

  return filtered;
}

/**
 * Find a specific feature by its ID
 */
export function findFeatureById(features: ReleasePlanFeature[], featureId: string): ReleasePlanFeature | undefined {
  return features.find(f => f["Release Plan ID"] === featureId);
}

/**
 * Get list of unique products with optional feature counts
 */
export function getUniqueProducts(features: ReleasePlanFeature[]): { name: string; count?: number }[] {
  const productMap = new Map<string, number>();

  features.forEach(f => {
    const count = productMap.get(f["Product name"]) || 0;
    productMap.set(f["Product name"], count + 1);
  });

  return Array.from(productMap.entries())
    .map(([name, count]) => ({ name, count }))
    .sort((a, b) => a.name.localeCompare(b.name));
}

/**
 * Get summary statistics for a specific release wave
 */
export function getWaveSummary(features: ReleasePlanFeature[], releaseWave: string) {
  const waveFeatures = features.filter(f =>
    f["GA Release Wave"].toLowerCase().includes(releaseWave.toLowerCase()) ||
    f["Public Preview Release Wave"].toLowerCase().includes(releaseWave.toLowerCase())
  );

  const productCounts = new Map<string, number>();
  const investmentAreas = new Map<string, number>();
  let gaCount = 0;
  let previewCount = 0;
  let earlyAccessCount = 0;

  waveFeatures.forEach(f => {
    // Count by product
    const productCount = productCounts.get(f["Product name"]) || 0;
    productCounts.set(f["Product name"], productCount + 1);

    // Count by investment area
    const areaCount = investmentAreas.get(f["Investment area"]) || 0;
    investmentAreas.set(f["Investment area"], areaCount + 1);

    // Count by status
    if (f["GA date"]) gaCount++;
    if (f["Public preview date"]) previewCount++;
    if (f["Early access date"]) earlyAccessCount++;
  });

  return {
    releaseWave,
    totalFeatures: waveFeatures.length,
    gaFeatures: gaCount,
    previewFeatures: previewCount,
    earlyAccessFeatures: earlyAccessCount,
    productBreakdown: Array.from(productCounts.entries())
      .map(([product, count]) => ({ product, count }))
      .sort((a, b) => b.count - a.count),
    investmentAreaBreakdown: Array.from(investmentAreas.entries())
      .map(([area, count]) => ({ area, count }))
      .sort((a, b) => b.count - a.count)
  };
}
```

> **Key design decisions:**
> - **1-hour cache**: The Release Planner API returns the full dataset (~500+ features). Caching avoids repeated large fetches.
> - **Zod validation**: `ReleasePlanResponseSchema.parse(data)` validates the API response at runtime, catching schema changes early.
> - **Case-insensitive filtering**: All string comparisons use `.toLowerCase()` for user-friendly search.
> - **No authentication**: The Release Planner API is public and requires no API keys.

---

## Step 8: Create the MCP Server

### 8.1 Create src/index-mcp.ts (HTTP-based MCP Server)

This is the main entry point for HTTP deployment (Azure App Service, Copilot Studio). It creates an Express server with an `/mcp` endpoint that handles MCP protocol requests.

```typescript
import express, { Request, Response } from 'express';
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
import { z } from 'zod';
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";

import {
  SearchReleasePlansInputSchema,
  ListProductsInputSchema,
  GetReleaseWaveSummaryInputSchema,
} from "./types.js";

import {
  fetchAllReleasePlans,
  filterFeatures,
  getUniqueProducts,
  getWaveSummary,
} from "./utils/api.js";

const app = express();
app.use(express.json());

// Create the MCP server at module level (shared across all requests)
const server = new Server(
  {
    name: "ms-release-planner-mcp-server",
    version: "1.0.0",
  },
  {
    capabilities: {
      tools: {},
    },
  }
);

// Handler: List available tools (registered once at module level)
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return {
    tools: [
      {
        name: "search_release_plans",
        description: "Search Microsoft Release Planner for features in Dynamics 365 and Power Platform products. Filter by product, keywords, release wave, status, and investment area.",
        inputSchema: {
          type: "object",
          properties: {
            product: {
              type: "string",
              description: "Product name to filter (e.g., 'Dynamics 365 Sales', 'Power Automate')"
            },
            featureKeyword: {
              type: "string",
              description: "Keyword to search in feature names"
            },
            releaseWave: {
              type: "string",
              description: "Release wave (e.g., '2025 release wave 1')"
            },
            status: {
              type: "string",
              enum: ["early_access", "public_preview", "ga", "all"],
              description: "Feature status filter"
            },
            investmentArea: {
              type: "string",
              description: "Investment area (e.g., 'Copilot and AI innovation')"
            },
            limit: {
              type: "number",
              description: "Maximum number of results to return",
              default: 20
            }
          },
          required: []
        },
      },
      {
        name: "list_products",
        description: "List all products available in the Release Planner with optional feature counts.",
        inputSchema: {
          type: "object",
          properties: {
            includeCount: {
              type: "boolean",
              description: "Include feature count per product",
              default: false
            }
          },
          required: []
        },
      },
      {
        name: "get_release_wave_summary",
        description: "Get a summary of a specific release wave including feature counts by product and investment area.",
        inputSchema: {
          type: "object",
          properties: {
            releaseWave: {
              type: "string",
              description: "Release wave name (e.g., '2025 release wave 1')"
            }
          },
          required: ["releaseWave"]
        },
      },
    ],
  };
});

// Handler: Call tool (registered once at module level)
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "search_release_plans") {
      const input = SearchReleasePlansInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const filtered = filterFeatures(allFeatures, input);
      const limited = filtered.slice(0, input.limit || 20);

      let resultText = `Found ${filtered.length} matching features:\n\n`;

      limited.forEach((feature, idx) => {
        resultText += `${idx + 1}. ${feature["Product name"]}: ${feature["Feature name"]}\n`;
        resultText += `   Status: GA ${feature["GA date"] || "TBD"}, Preview ${feature["Public preview date"] || "TBD"}\n`;
        resultText += `   Wave: ${feature["GA Release Wave"] || "Not specified"}\n`;
        resultText += `   Area: ${feature["Investment area"]}\n\n`;
      });

      return {
        content: [{ type: "text", text: resultText }],
      };
    }

    if (name === "list_products") {
      const input = ListProductsInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const products = getUniqueProducts(allFeatures);

      const productList = input.includeCount
        ? products.map((p) => `${p.name} (${p.count} features)`).join("\n")
        : products.map((p) => p.name).join("\n");

      return {
        content: [{ type: "text", text: `Total Products: ${products.length}\n\n${productList}` }],
      };
    }

    if (name === "get_release_wave_summary") {
      const input = GetReleaseWaveSummaryInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const summary = getWaveSummary(allFeatures, input.releaseWave);

      const summaryText = formatWaveSummary(summary);

      return {
        content: [{ type: "text", text: summaryText }],
      };
    }

    throw new Error(`Unknown tool: ${name}`);

  } catch (error) {
    return {
      content: [{ type: "text", text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}` }],
      isError: true,
    };
  }
});

// Helper function to format wave summary as readable text
function formatWaveSummary(summary: any): string {
  const productBreakdown = summary.productBreakdown
    .slice(0, 10)
    .map((p: any) => `  - ${p.product}: ${p.count} features`)
    .join("\n");

  const investmentBreakdown = summary.investmentAreaBreakdown
    .slice(0, 10)
    .map((i: any) => `  - ${i.area}: ${i.count} features`)
    .join("\n");

  return `# ${summary.releaseWave} Summary

## Overview
- Total Features: ${summary.totalFeatures}
- GA Features: ${summary.gaFeatures}
- Public Preview: ${summary.previewFeatures}
- Early Access: ${summary.earlyAccessFeatures}

## Top Products
${productBreakdown}

## Top Investment Areas
${investmentBreakdown}`;
}

// MCP endpoint - each request gets a new transport, connected to the shared server
app.post('/mcp', async (req: Request, res: Response) => {
  try {
    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: undefined,
      enableJsonResponse: true
    });

    res.on('close', () => {
      transport.close();
    });

    await server.connect(transport);
    await transport.handleRequest(req, res, req.body);
  } catch (error) {
    console.error('Error handling MCP request:', error);
    if (!res.headersSent) {
      res.status(500).json({
        jsonrpc: '2.0',
        error: {
          code: -32603,
          message: 'Internal server error'
        },
        id: null
      });
    }
  }
});

// Health check endpoint
app.get('/health', (req: Request, res: Response) => {
  res.json({
    status: "healthy",
    service: "Microsoft Release Planner MCP Server",
    version: "1.0.0",
    timestamp: new Date().toISOString(),
  });
});

const PORT = parseInt(process.env.PORT || '3000');
app.listen(PORT, () => {
  console.log(`Microsoft Release Planner MCP Server running on http://localhost:${PORT}/mcp`);
}).on('error', error => {
  console.error('Server error:', error);
  process.exit(1);
});
```

> **Key patterns in this code:**
> - Use `Server` from `@modelcontextprotocol/sdk/server/index.js` (not `McpServer` from `mcp.js`)
> - Create the server and register handlers **at module level** (not inside the request handler)
> - Each POST to `/mcp` creates a new `StreamableHTTPServerTransport` and connects it to the shared server
> - Call `server.connect(transport)` **before** `transport.handleRequest()`
> - On response close, only close the **transport** (not the server)
> - Define `inputSchema` as plain JSON Schema objects (no `zod-to-json-schema`)
> - Return **text-only** responses for maximum compatibility with Copilot Studio

---

## Step 9: Build and Test

### 9.1 Build the Project
```bash
npm run build
```

This compiles TypeScript files from `src/` to JavaScript in `build/`.

### 9.2 Start the Server
```bash
npm start
```

### 9.3 Test the Server

**Test health endpoint:**
```bash
curl http://localhost:3000/health
```

**Test MCP tools list:**
```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/list",
    "params": {}
  }'
```

**Test a tool call (list products):**
```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/call",
    "params": {
      "name": "list_products",
      "arguments": {}
    }
  }'
```

**Test search (Dynamics 365 Sales features):**
```bash
curl -X POST http://localhost:3000/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": {
      "name": "search_release_plans",
      "arguments": {
        "product": "Dynamics 365 Sales",
        "releaseWave": "2025 release wave 1",
        "limit": 5
      }
    }
  }'
```

> **Note:** The `Accept: application/json, text/event-stream` header is required by the MCP StreamableHTTP transport. Without it, you'll get a "Not Acceptable" error.

---

## Step 10: Create .gitignore

Create a `.gitignore` file:

```gitignore
# Dependencies
node_modules/

# Build output
build/
dist/

# Environment files
.env
.env.local
.env.*.local

# IDE
.vscode/
.idea/

# Logs
*.log
npm-debug.log*

# OS files
.DS_Store
Thumbs.db

# Test coverage
coverage/

# Deployment artifacts
deploy-staging/
deploy.zip
azure-logs/
azure-logs.zip
logs.zip
```

---

## Step 11: Add README

Create a `README.md` file:

```markdown
# Microsoft Release Planner MCP Server

A TypeScript-based MCP (Model Context Protocol) server for querying the Microsoft Release Planner API. Integrates with Copilot Studio agents to provide AI-powered access to Dynamics 365 and Power Platform release plans.

## Quick Start

\`\`\`bash
npm install        # Install dependencies
npm run build      # Compile TypeScript
npm start          # Start MCP server on port 3000
\`\`\`

## Endpoints

- **MCP**: `POST http://localhost:3000/mcp`
- **Health**: `GET http://localhost:3000/health`

## Available Tools

1. **search_release_plans** - Search and filter release plans by product, wave, status, and keywords
2. **list_products** - List all available products with optional feature counts
3. **get_release_wave_summary** - Get release wave statistics and breakdowns by product and investment area

## API Information

- **Base URL**: `https://releaseplans.microsoft.com/en-US/allreleaseplans/`
- **Authentication**: Not required (public API)
- **Cache TTL**: 1 hour
```

---

# Part 2: Deploying to Azure

> **Shell Syntax Note:** This guide provides commands for both **Bash** (Linux/macOS/Git Bash) and **PowerShell** (Windows). Key differences:
> - **Line continuation:** Bash uses `\`, PowerShell uses `` ` `` (backtick)
> - **Runtime separator:** Bash uses `NODE|20-lts`, PowerShell uses `NODE:20-lts`
> - **Variables:** Bash uses `$VAR`, PowerShell uses `$VAR` (same) but subshell syntax differs
> - **Zip files:** Bash uses `zip`, PowerShell uses `Compress-Archive`

## Option A: Azure App Service (Recommended)

### Step 1: Prerequisites

- **Azure Account**: https://azure.microsoft.com/
- **Azure CLI**: Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
  - Verify: `az --version`

### Step 2: Login to Azure
```bash
az login
```

### Step 3: Create Resource Group

**Bash:**
```bash
az group create \
  --name rel-planner-mcp-server-rg \
  --location eastus \
  --tags Owner=your-alias
```

**PowerShell:**
```powershell
az group create --name rel-planner-mcp-server-rg --location eastus --tags Owner=your-alias
```

> **Note (Microsoft Subscriptions):** Many Azure subscriptions enforce policies that require tags on resource groups. The `--tags Owner=your-alias` parameter is mandatory if your subscription has a "Require a tag on resource groups" policy. Replace `your-alias` with your Microsoft alias or email. Without this tag, the command will fail with a `RequestDisallowedByPolicy` error.

> **Quota Note:** If you receive a quota error for your chosen SKU (B1, F1, etc.) in a region, try a different region (e.g., `westus2`, `westeurope`) or request a quota increase via Azure Portal → Quotas → Microsoft.Web.

### Step 4: Create App Service Plan

**Bash:**
```bash
az appservice plan create \
  --name rel-planner-mcp-server-plan \
  --resource-group rel-planner-mcp-server-rg \
  --sku B1 \
  --is-linux
```

**PowerShell:**
```powershell
az appservice plan create --name rel-planner-mcp-server-plan --resource-group rel-planner-mcp-server-rg --sku B1 --is-linux
```

### Step 5: Create Web App

**Bash:**
```bash
az webapp create \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --plan rel-planner-mcp-server-plan \
  --runtime "NODE|20-lts"
```

**PowerShell:**
```powershell
az webapp create --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --plan rel-planner-mcp-server-plan --runtime "NODE:20-lts"
```

> **Windows Note:** In PowerShell, use `NODE:20-lts` (colon separator) instead of `NODE|20-lts` (pipe). The pipe character `|` is interpreted by PowerShell as a pipeline operator.

### Step 6: Configure Web App

> **Important:** We use `WEBSITE_RUN_FROM_PACKAGE=1` to completely bypass Azure's Oryx build system. This means Azure mounts the deployment ZIP directly as the app filesystem -- no `npm install` or `tsc` runs on the server. Everything is built locally and deployed as-is.

**6.1 Set app settings (disable Oryx build, enable run-from-package):**

**Bash:**
```bash
az webapp config appsettings set \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --settings \
    WEBSITE_RUN_FROM_PACKAGE=1 \
    SCM_DO_BUILD_DURING_DEPLOYMENT=false
```

**PowerShell:**
```powershell
az webapp config appsettings set --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --settings WEBSITE_RUN_FROM_PACKAGE=1 SCM_DO_BUILD_DURING_DEPLOYMENT=false
```

> **If migrating from a previous deployment approach:** Remove any conflicting build settings that may have been set by earlier attempts:
>
> **Bash:**
> ```bash
> az webapp config appsettings delete \
>   --name rel-planner-mcp-server \
>   --resource-group rel-planner-mcp-server-rg \
>   --setting-names CUSTOM_BUILD_COMMAND PRE_BUILD_COMMAND POST_BUILD_COMMAND WEBSITE_NODE_DEFAULT_VERSION
> ```
>
> **PowerShell:**
> ```powershell
> az webapp config appsettings delete --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --setting-names CUSTOM_BUILD_COMMAND PRE_BUILD_COMMAND POST_BUILD_COMMAND WEBSITE_NODE_DEFAULT_VERSION
> ```

> **Why `WEBSITE_RUN_FROM_PACKAGE=1`?** Azure's Oryx build system detects `"build": "tsc"` in `package.json` and tries to rebuild TypeScript on the server. On B1 tier this always times out. `WEBSITE_RUN_FROM_PACKAGE=1` skips Oryx entirely -- the ZIP is mounted directly as a read-only filesystem.

**6.2 Set startup command:**

> **Important:** Use `az webapp config set` (NOT `az webapp config appsettings set`):
> - `az webapp config appsettings set` --> environment variables (`--settings`)
> - `az webapp config set` --> server configuration (`--startup-file`)

**Bash:**
```bash
az webapp config set \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --startup-file "node build/index-mcp.js"
```

**PowerShell:**
```powershell
az webapp config set --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --startup-file "node build/index-mcp.js"
```

> **Note:** We use `node build/index-mcp.js` directly instead of `npm start` for faster startup.

### Step 7: Deploy Using ZIP Deploy

The deployment creates a **staging directory** with only what's needed to run: pre-built JavaScript + production dependencies. This keeps the ZIP small (~15-20 MB) and deploys in seconds.

> **Quick Deploy:** If you prefer a one-command deployment, use the included scripts:
> - **PowerShell:** `.\deploy.ps1` (first time: `.\deploy.ps1 -Setup`)
> - **Bash:** `./deploy.sh` (first time: `./deploy.sh --setup`)

**7.1 Build your project locally:**
```bash
npm run build
```

**7.2 Create staging directory with production dependencies only:**

**Bash (Linux/macOS):**
```bash
# Create staging directory
rm -rf deploy-staging
mkdir -p deploy-staging
cp -r build deploy-staging/
cp package.json deploy-staging/
cp package-lock.json deploy-staging/

# Install production dependencies only (no TypeScript, no @types/*)
cd deploy-staging
npm ci --omit=dev
cd ..
```

**PowerShell (Windows):**
```powershell
# Create staging directory
if (Test-Path deploy-staging) { Remove-Item -Recurse -Force deploy-staging }
New-Item -ItemType Directory -Force -Path deploy-staging | Out-Null
Copy-Item -Recurse build deploy-staging/
Copy-Item package.json deploy-staging/
Copy-Item package-lock.json deploy-staging/

# Install production dependencies only (no TypeScript, no @types/*)
Push-Location deploy-staging
npm ci --omit=dev
Pop-Location
```

> **Why a staging directory?** Running `npm ci --omit=dev` installs only the 3 production dependencies (`@modelcontextprotocol/sdk`, `express`, `zod`) instead of all 6 including TypeScript and type definitions. This reduces the package from ~65 MB to ~15-20 MB.

**7.3 Create ZIP package:**

**Bash (Linux/macOS):**
```bash
rm -f deploy.zip
cd deploy-staging
zip -r ../deploy.zip .
cd ..
```

**PowerShell (Windows):**
```powershell
Remove-Item deploy.zip -ErrorAction SilentlyContinue
Compress-Archive -Path deploy-staging/* -DestinationPath deploy.zip -Force
```

**7.4 Deploy to Azure:**

**Bash:**
```bash
az webapp deploy \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --src-path deploy.zip \
  --type zip
```

**PowerShell:**
```powershell
az webapp deploy --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --src-path deploy.zip --type zip
```

**7.5 Cleanup:**

**Bash:**
```bash
rm -rf deploy-staging deploy.zip
```

**PowerShell:**
```powershell
Remove-Item -Recurse -Force deploy-staging
Remove-Item deploy.zip
```

> Deployment should complete in **under 1 minute** since no server-side build is needed.

### Step 8: Verify Deployment

**Bash:**
```bash
az webapp show \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --query defaultHostName \
  --output tsv
```

**PowerShell:**
```powershell
az webapp show --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --query defaultHostName --output tsv
```

Your MCP server will be available at:
- **MCP Endpoint**: `https://rel-planner-mcp-server.azurewebsites.net/mcp`
- **Health Check**: `https://rel-planner-mcp-server.azurewebsites.net/health`

**Test with curl/Invoke-WebRequest:**

**Bash:**
```bash
curl https://rel-planner-mcp-server.azurewebsites.net/health
```

**PowerShell:**
```powershell
Invoke-WebRequest -Uri https://rel-planner-mcp-server.azurewebsites.net/health
```

### Step 9: Enable Logging and View Logs (Troubleshooting)

**9.1 Enable application and Docker logging:**

**Bash:**
```bash
az webapp log config \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --application-logging filesystem \
  --level verbose \
  --docker-container-logging filesystem
```

**PowerShell:**
```powershell
az webapp log config --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --application-logging filesystem --level verbose --docker-container-logging filesystem
```

**9.2 Stream live logs:**

**Bash:**
```bash
az webapp log tail \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg
```

**PowerShell:**
```powershell
az webapp log tail --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg
```

---

## Option B: Azure Container Apps

### Step 1: Create Dockerfile

Create a `Dockerfile` in your project root:

```dockerfile
# Build stage
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy source code
COPY . .

# Build TypeScript
RUN npm run build

# Production stage
FROM node:20-alpine AS production

WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies only
RUN npm ci --omit=dev

# Copy built files from builder
COPY --from=builder /app/build ./build

# Expose port
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000

# Start the server
CMD ["node", "build/index-mcp.js"]
```

### Step 2: Create Azure Container Registry

**Bash:**
```bash
# Create container registry
az acr create \
  --name relplannermcpregistry \
  --resource-group rel-planner-mcp-server-rg \
  --sku Basic \
  --admin-enabled true

# Login to registry
az acr login --name relplannermcpregistry
```

**PowerShell:**
```powershell
# Create container registry
az acr create --name relplannermcpregistry --resource-group rel-planner-mcp-server-rg --sku Basic --admin-enabled true

# Login to registry
az acr login --name relplannermcpregistry
```

### Step 3: Build and Push Image

**Bash:**
```bash
az acr build \
  --registry relplannermcpregistry \
  --image rel-planner-mcp-server:v1 \
  .
```

**PowerShell:**
```powershell
az acr build --registry relplannermcpregistry --image rel-planner-mcp-server:v1 .
```

### Step 4: Create Container App Environment

**Bash:**
```bash
az containerapp env create \
  --name rel-planner-mcp-environment \
  --resource-group rel-planner-mcp-server-rg \
  --location eastus
```

**PowerShell:**
```powershell
az containerapp env create --name rel-planner-mcp-environment --resource-group rel-planner-mcp-server-rg --location eastus
```

### Step 5: Deploy Container App

**Bash:**
```bash
# Get registry credentials
ACR_PASSWORD=$(az acr credential show --name relplannermcpregistry --query passwords[0].value -o tsv)

# Create container app
az containerapp create \
  --name rel-planner-mcp-server-app \
  --resource-group rel-planner-mcp-server-rg \
  --environment rel-planner-mcp-environment \
  --image relplannermcpregistry.azurecr.io/rel-planner-mcp-server:v1 \
  --target-port 3000 \
  --ingress external \
  --registry-server relplannermcpregistry.azurecr.io \
  --registry-username relplannermcpregistry \
  --registry-password $ACR_PASSWORD \
  --min-replicas 1 \
  --max-replicas 3
```

**PowerShell:**
```powershell
# Get registry credentials
$ACR_PASSWORD = az acr credential show --name relplannermcpregistry --query passwords[0].value -o tsv

# Create container app
az containerapp create --name rel-planner-mcp-server-app --resource-group rel-planner-mcp-server-rg --environment rel-planner-mcp-environment --image relplannermcpregistry.azurecr.io/rel-planner-mcp-server:v1 --target-port 3000 --ingress external --registry-server relplannermcpregistry.azurecr.io --registry-username relplannermcpregistry --registry-password $ACR_PASSWORD --min-replicas 1 --max-replicas 3
```

### Step 6: Get Application URL

**Bash:**
```bash
az containerapp show \
  --name rel-planner-mcp-server-app \
  --resource-group rel-planner-mcp-server-rg \
  --query properties.configuration.ingress.fqdn \
  --output tsv
```

**PowerShell:**
```powershell
az containerapp show --name rel-planner-mcp-server-app --resource-group rel-planner-mcp-server-rg --query properties.configuration.ingress.fqdn --output tsv
```

---

## Option C: Azure Kubernetes Service (AKS)

For enterprise-scale deployments, refer to the Azure AKS documentation:
https://docs.microsoft.com/en-us/azure/aks/

---

## Azure Deployment Best Practices

### 1. Environment Variables

If your MCP server needs environment variables (e.g., API keys for authenticated APIs), set them via app settings:

**Bash:**
```bash
az webapp config appsettings set \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --settings \
    NODE_ENV=production \
    PORT=3000
```

**PowerShell:**
```powershell
az webapp config appsettings set --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --settings NODE_ENV=production PORT=3000
```

> **Note:** The Microsoft Release Planner API is public and requires no API keys. For servers that access authenticated APIs, store secrets in Azure Key Vault and reference them as `@Microsoft.KeyVault(SecretUri=...)`.

### 2. Enable Application Insights

**Bash:**
```bash
# Create Application Insights
az monitor app-insights component create \
  --app rel-planner-mcp-insights \
  --location eastus \
  --resource-group rel-planner-mcp-server-rg

# Get instrumentation key
APPINSIGHTS_KEY=$(az monitor app-insights component show \
  --app rel-planner-mcp-insights \
  --resource-group rel-planner-mcp-server-rg \
  --query instrumentationKey -o tsv)

# Add to web app
az webapp config appsettings set \
  --name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --settings APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY
```

**PowerShell:**
```powershell
# Create Application Insights
az monitor app-insights component create --app rel-planner-mcp-insights --location eastus --resource-group rel-planner-mcp-server-rg

# Get instrumentation key
$APPINSIGHTS_KEY = az monitor app-insights component show --app rel-planner-mcp-insights --resource-group rel-planner-mcp-server-rg --query instrumentationKey -o tsv

# Add to web app
az webapp config appsettings set --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --settings APPINSIGHTS_INSTRUMENTATIONKEY=$APPINSIGHTS_KEY
```

### 3. Configure Custom Domain (Optional)

**Bash:**
```bash
az webapp config hostname add \
  --webapp-name rel-planner-mcp-server \
  --resource-group rel-planner-mcp-server-rg \
  --hostname mcp.yourdomain.com
```

**PowerShell:**
```powershell
az webapp config hostname add --webapp-name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg --hostname mcp.yourdomain.com
```

---

# Part 3: Deploying on a Local PC/Laptop

## Option A: Direct Node.js Deployment

### Step 1: Install Node.js

**Windows:**
1. Download from https://nodejs.org/
2. Run the installer
3. Restart terminal

**macOS:**
```bash
# Using Homebrew
brew install node@20
```

**Linux (Ubuntu/Debian):**
```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
```

### Step 2: Clone/Copy Your Project
```bash
# Clone from repository
git clone https://github.com/yourusername/ms-release-planner-mcp-server.git
cd ms-release-planner-mcp-server

# Or copy the project folder to your desired location
```

### Step 3: Install Dependencies
```bash
npm install
```

### Step 4: Build the Project
```bash
npm run build
```

### Step 5: Start the Server
```bash
npm start
```

The server will be available at:
- **MCP Endpoint**: `http://localhost:3000/mcp`
- **Health Check**: `http://localhost:3000/health`

---

## Option B: Running as a Background Service

### Windows - Using NSSM (Non-Sucking Service Manager)

**Step 1: Download NSSM**
- Download from https://nssm.cc/download

**Step 2: Install as Service**
```cmd
nssm install MCPServer
```

In the GUI:
- **Path**: `C:\Program Files\nodejs\node.exe`
- **Startup directory**: `C:\path\to\ms-release-planner-mcp-server`
- **Arguments**: `build/index-mcp.js`

**Step 3: Start Service**
```cmd
nssm start MCPServer
```

### Linux - Using systemd

**Step 1: Create Service File**
```bash
sudo nano /etc/systemd/system/mcp-server.service
```

**Step 2: Add Configuration**
```ini
[Unit]
Description=Microsoft Release Planner MCP Server
After=network.target

[Service]
Type=simple
User=your-username
WorkingDirectory=/path/to/ms-release-planner-mcp-server
ExecStart=/usr/bin/node build/index-mcp.js
Restart=on-failure
RestartSec=10
Environment=NODE_ENV=production
Environment=PORT=3000

[Install]
WantedBy=multi-user.target
```

**Step 3: Enable and Start Service**
```bash
sudo systemctl daemon-reload
sudo systemctl enable mcp-server
sudo systemctl start mcp-server
```

**Step 4: Check Status**
```bash
sudo systemctl status mcp-server
```

### macOS - Using launchd

**Step 1: Create plist File**
```bash
nano ~/Library/LaunchAgents/com.mcp.server.plist
```

**Step 2: Add Configuration**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.mcp.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/node</string>
        <string>/path/to/ms-release-planner-mcp-server/build/index-mcp.js</string>
    </array>
    <key>WorkingDirectory</key>
    <string>/path/to/ms-release-planner-mcp-server</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>3000</string>
    </dict>
</dict>
</plist>
```

**Step 3: Load Service**
```bash
launchctl load ~/Library/LaunchAgents/com.mcp.server.plist
```

---

## Option C: Using PM2 Process Manager (Recommended for Production)

PM2 is a production process manager for Node.js with built-in load balancer.

### Step 1: Install PM2
```bash
npm install -g pm2
```

### Step 2: Start with PM2
```bash
cd /path/to/ms-release-planner-mcp-server
pm2 start build/index-mcp.js --name "ms-release-planner-mcp"
```

### Step 3: Configure Auto-Start on Boot
```bash
pm2 startup
pm2 save
```

### Step 4: Useful PM2 Commands
```bash
pm2 list                          # List all processes
pm2 logs ms-release-planner-mcp   # View logs
pm2 restart ms-release-planner-mcp # Restart server
pm2 stop ms-release-planner-mcp   # Stop server
pm2 delete ms-release-planner-mcp # Remove from PM2
```

### Step 5: Create PM2 Ecosystem File (Optional)

Create `ecosystem.config.js`:
```javascript
module.exports = {
  apps: [{
    name: 'ms-release-planner-mcp',
    script: 'build/index-mcp.js',
    instances: 'max',
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: 'logs/error.log',
    out_file: 'logs/output.log',
    log_file: 'logs/combined.log',
    time: true
  }]
};
```

Start with ecosystem file:
```bash
pm2 start ecosystem.config.js
```

---

## Option D: Using Docker Locally

### Step 1: Install Docker
- **Windows/Mac**: Download Docker Desktop from https://www.docker.com/products/docker-desktop
- **Linux**:
  ```bash
  curl -fsSL https://get.docker.com | sh
  ```

### Step 2: Create Dockerfile
(Use the Dockerfile from Part 2, Option B)

### Step 3: Build Docker Image
```bash
docker build -t ms-release-planner-mcp .
```

### Step 4: Run Container
```bash
docker run -d \
  --name ms-release-planner-mcp \
  -p 3000:3000 \
  -e NODE_ENV=production \
  --restart unless-stopped \
  ms-release-planner-mcp
```

### Step 5: Verify
```bash
docker ps
docker logs ms-release-planner-mcp
curl http://localhost:3000/health
```

---

## Exposing Local Server to Internet

### Using VS Code Dev Tunnels

1. Open VS Code
2. Go to **PORTS** panel (View → Ports)
3. Click **Forward a Port**
4. Enter `3000`
5. Right-click → **Port Visibility** → **Public**
6. Copy the generated URL

### Using ngrok

```bash
# Install ngrok
npm install -g ngrok

# Start tunnel
ngrok http 3000
```

### Using Cloudflare Tunnel

```bash
# Install cloudflared
# Then run:
cloudflared tunnel --url http://localhost:3000
```

---

## Integration with AI Clients

### Copilot Studio Integration

1. Build and start your MCP server (locally with Dev Tunnel, or deployed to Azure)
2. In Copilot Studio (https://copilotstudio.microsoft.com):
   - Select your agent
   - Go to **Tools** (left sidebar)
   - Click **"Add an MCP server"**
   - Fill in:
     - **Name**: Microsoft Release Planner
     - **URL**: `https://your-tunnel-or-azure-url/mcp`
     - **Authentication**: None
   - Click **Add**
3. Test with prompts like:
   - "What products are available?"
   - "List features for Dynamics 365 Sales 2025 release wave 1"
   - "Show me Copilot and AI features in Supply Chain Management"

### Claude Desktop Integration

1. Edit Claude Desktop config file:

**Windows:**
```
%APPDATA%\Claude\claude_desktop_config.json
```

**macOS:**
```
~/Library/Application Support/Claude/claude_desktop_config.json
```

2. Add your server:
```json
{
  "mcpServers": {
    "ms-release-planner": {
      "command": "node",
      "args": ["C:/path/to/ms-release-planner-mcp-server/build/index.js"]
    }
  }
}
```

> **Note:** Claude Desktop uses the **stdio** transport (`index.js`), not the HTTP transport (`index-mcp.js`). The stdio entry point communicates via stdin/stdout instead of HTTP.

3. Restart Claude Desktop

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Port already in use | Change PORT environment variable or kill existing process |
| TypeScript errors | Run `npm run build` and check for compilation errors |
| Module not found | Run `npm install` to ensure all dependencies are installed |
| Connection refused | Check if server is running and firewall allows traffic |

### Azure-Specific Issues

| Issue | Solution |
|-------|----------|
| `RequestDisallowedByPolicy` | Add `--tags Owner=your-alias` to resource group creation |
| Quota exceeded (B1/F1 VMs) | Try a different region or request quota increase via Azure Portal → Quotas |
| `NODE\|20-lts` not recognized (Windows) | Use `NODE:20-lts` (colon) in PowerShell instead of pipe |
| `zip` command not found (Windows) | Use `Compress-Archive` in PowerShell instead |
| `--startup-file` unrecognized | Use `az webapp config set` (NOT `az webapp config appsettings set`) |
| Site hangs on "Starting the site..." | Set `WEBSITE_RUN_FROM_PACKAGE=1` and deploy with staging dir approach |
| Oryx build times out | Set `SCM_DO_BUILD_DURING_DEPLOYMENT=false` + `WEBSITE_RUN_FROM_PACKAGE=1` |
| `deployment source config-zip` deprecated | Use `az webapp deploy --src-path deploy.zip --type zip` instead |
| ZIP deploy 400 error (too large) | Use staging dir with `npm ci --omit=dev` to reduce package size |
| Container exits with code 1 | Clean up conflicting settings (see Step 6 note), restart: `az webapp restart` |
| "Not Acceptable" error on MCP endpoint | Add `Accept: application/json, text/event-stream` header to requests |
| App logging not visible | Enable logging: `az webapp log config --name ... --application-logging filesystem --level verbose --docker-container-logging filesystem` |

> **Oryx Build Bypass:** If your TypeScript project keeps failing during Azure deployment with build timeouts, the root cause is Oryx detecting `"build": "tsc"` in `package.json` and trying to rebuild on the server. The fix is `WEBSITE_RUN_FROM_PACKAGE=1` which mounts your pre-built ZIP directly, skipping all server-side builds. See Step 6 in the Azure App Service deployment section.

> **Container Exit Code 1:** If the container starts but immediately exits with code 1, check for conflicting app settings from previous deployment attempts. Settings like `CUSTOM_BUILD_COMMAND`, `PRE_BUILD_COMMAND`, or `POST_BUILD_COMMAND` can interfere with `WEBSITE_RUN_FROM_PACKAGE`. Remove them and restart the app.

### Debug Mode

**Bash:**
```bash
# Run with debug logging
DEBUG=* npm start

# Or set environment variable
export DEBUG=mcp:*
npm start
```

**PowerShell:**
```powershell
# Run with debug logging
$env:DEBUG="*"; npm start

# Or set environment variable
$env:DEBUG="mcp:*"
npm start
```

### Check Logs

**Bash:**
```bash
# PM2
pm2 logs ms-release-planner-mcp

# Docker
docker logs ms-release-planner-mcp

# systemd
journalctl -u mcp-server -f

# Azure App Service
az webapp log tail --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg
```

**PowerShell:**
```powershell
# PM2
pm2 logs ms-release-planner-mcp

# Docker
docker logs ms-release-planner-mcp

# Azure App Service
az webapp log tail --name rel-planner-mcp-server --resource-group rel-planner-mcp-server-rg
```

---

## Summary

| Deployment Option | Best For | Complexity |
|------------------|----------|------------|
| **Azure App Service** | Production, Easy CI/CD | Low |
| **Azure Container Apps** | Containerized, Auto-scaling | Medium |
| **Local Node.js** | Development, Testing | Very Low |
| **PM2** | Local Production | Low |
| **Docker** | Consistent environments | Medium |
| **systemd/launchd** | Server deployment | Medium |

---

## Next Steps

1. **Add Authentication**: Implement API keys or OAuth
2. **Add Logging**: Use Winston or Pino for structured logging
3. **Add Monitoring**: Integrate with Application Insights or Prometheus
4. **Add Tests**: Create unit and integration tests
5. **CI/CD**: Set up GitHub Actions or Azure DevOps pipelines

For more information, refer to:
- [MCP Protocol Specification](https://modelcontextprotocol.io/)
- [Azure App Service Documentation](https://docs.microsoft.com/en-us/azure/app-service/)
- [Node.js Best Practices](https://nodejs.org/en/docs/guides/)
