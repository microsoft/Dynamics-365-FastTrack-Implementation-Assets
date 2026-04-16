// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
//
// DISCLAIMER: This code is provided as sample/reference code for educational
// and demonstration purposes only. It is provided "as-is" without warranty of
// any kind. Microsoft does not operate or support deployments created with this
// code. You are responsible for reviewing, testing, and securing any
// resources deployed in your own environment.

import express, { Request, Response } from 'express';
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/streamableHttp.js";
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

// Factory: creates a new MCP Server instance with all handlers registered.
// A fresh instance is created per HTTP request to avoid state leaks from
// calling server.connect() on a singleton.
function createMcpServer(): Server {
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

  // Handler: List available tools
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

// Handler: Call tool
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    if (name === "search_release_plans") {
      console.log('🔍 Searching release plans:', args);

      const input = SearchReleasePlansInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const filtered = filterFeatures(allFeatures, input);
      const limited = filtered.slice(0, input.limit || 20);

      // Build simple text response
      let resultText = `Found ${filtered.length} matching features:\n\n`;

      limited.forEach((feature, idx) => {
        resultText += `${idx + 1}. ${feature["Product name"]}: ${feature["Feature name"]}\n`;
        resultText += `   Status: GA ${feature["GA date"] || "TBD"}, Preview ${feature["Public preview date"] || "TBD"}\n`;
        resultText += `   Wave: ${feature["GA Release Wave"] || "Not specified"}\n`;
        resultText += `   Area: ${feature["Investment area"]}\n\n`;
      });

      console.log(`✅ Retrieved ${limited.length} features`);

      return {
        content: [
          {
            type: "text",
            text: resultText,
          },
        ],
      };
    }

    if (name === "list_products") {
      console.log('🔍 Listing products');

      const input = ListProductsInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const products = getUniqueProducts(allFeatures);

      const productList = input.includeCount
        ? products.map((p) => `${p.name} (${p.count} features)`).join("\n")
        : products.map((p) => p.name).join("\n");

      console.log(`✅ Retrieved ${products.length} products`);

      return {
        content: [
          {
            type: "text",
            text: `Total Products: ${products.length}\n\n${productList}`,
          },
        ],
      };
    }

    if (name === "get_release_wave_summary") {
      console.log('🔍 Getting release wave summary:', args);

      const input = GetReleaseWaveSummaryInputSchema.parse(args);
      const allFeatures = await fetchAllReleasePlans();
      const summary = getWaveSummary(allFeatures, input.releaseWave);

      const summaryText = formatWaveSummary(summary);

      console.log(`✅ Retrieved summary for ${input.releaseWave}`);

      return {
        content: [
          {
            type: "text",
            text: summaryText,
          },
        ],
      };
    }

    throw new Error(`Unknown tool: ${name}`);

  } catch (error) {
    console.error('❌ Error:', error);
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error instanceof Error ? error.message : 'Unknown error'}`,
        },
      ],
      isError: true,
    };
  }
});

  return server;
}

// Helper function to format wave summary
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

// Handle MCP requests — create a fresh server instance per request
app.post('/mcp', async (req: Request, res: Response) => {
  try {
    const server = createMcpServer();
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
  console.log(`🚀 Microsoft Release Planner MCP Server running on http://localhost:${PORT}/mcp`);
}).on('error', error => {
  console.error('Server error:', error);
  process.exit(1);
});
