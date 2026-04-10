#!/usr/bin/env node
// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
//
// DISCLAIMER: This code is provided as sample/reference code for educational
// and demonstration purposes only. It is provided "as-is" without warranty of
// any kind. Microsoft does not operate or support deployments created with this
// code. You are responsible for reviewing, testing, and securing any
// resources deployed in your own environment.

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  Tool,
} from "@modelcontextprotocol/sdk/types.js";

import {
  SearchReleasePlansInputSchema,
  GetFeatureDetailsInputSchema,
  ListProductsInputSchema,
  GetReleaseWaveSummaryInputSchema,
  SearchReleasePlansInput,
  GetFeatureDetailsInput,
  ListProductsInput,
  GetReleaseWaveSummaryInput,
} from "./types.js";

import {
  fetchAllReleasePlans,
  filterFeatures,
  findFeatureById,
  getUniqueProducts,
  getWaveSummary,
} from "./utils/api.js";

// Create server instance
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

// Define tools
const TOOLS: Tool[] = [
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
          description: "Keyword to search in feature names and descriptions"
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
      }
    }
  },
  {
    name: "get_feature_details",
    description: "Get detailed information about a specific feature by its Release Plan ID",
    inputSchema: {
      type: "object",
      properties: {
        featureId: {
          type: "string",
          description: "Release Plan ID of the feature"
        }
      },
      required: ["featureId"]
    }
  },
  {
    name: "list_products",
    description: "List all products available in the Release Planner with optional feature counts",
    inputSchema: {
      type: "object",
      properties: {
        includeCount: {
          type: "boolean",
          description: "Include feature count per product",
          default: false
        }
      }
    }
  },
  {
    name: "get_release_wave_summary",
    description: "Get a summary of a specific release wave including feature counts by product and investment area",
    inputSchema: {
      type: "object",
      properties: {
        releaseWave: {
          type: "string",
          description: "Release wave name (e.g., '2025 release wave 1')"
        }
      },
      required: ["releaseWave"]
    }
  }
];

// Handle list_tools request
server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: TOOLS };
});

// Handle call_tool request
server.setRequestHandler(CallToolRequestSchema, async (request) => {
  try {
    const { name, arguments: args } = request.params;

    switch (name) {
      case "search_release_plans": {
        const input = SearchReleasePlansInputSchema.parse(args);
        const allFeatures = await fetchAllReleasePlans();
        const filtered = filterFeatures(allFeatures, input);
        const limited = filtered.slice(0, input.limit || 20);

        const response = limited.map(f => ({
          "Release Plan ID": f["Release Plan ID"],
          "Product": f["Product name"],
          "Feature": f["Feature name"],
          "Investment Area": f["Investment area"],
          "GA Date": f["GA date"] || "Not set",
          "Preview Date": f["Public preview date"] || "Not set",
          "Early Access Date": f["Early access date"] || "Not set",
          "GA Release Wave": f["GA Release Wave"] || "Not set",
          "Preview Release Wave": f["Public Preview Release Wave"] || "Not set"
        }));

        return {
          content: [
            {
              type: "text",
              text: `Found ${filtered.length} features (showing ${limited.length}):\n\n${JSON.stringify(response, null, 2)}`
            }
          ]
        };
      }

      case "get_feature_details": {
        const input = GetFeatureDetailsInputSchema.parse(args);
        const allFeatures = await fetchAllReleasePlans();
        const feature = findFeatureById(allFeatures, input.featureId);

        if (!feature) {
          return {
            content: [
              {
                type: "text",
                text: `Feature with ID ${input.featureId} not found.`
              }
            ],
            isError: true
          };
        }

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(feature, null, 2)
            }
          ]
        };
      }

      case "list_products": {
        const input = ListProductsInputSchema.parse(args);
        const allFeatures = await fetchAllReleasePlans();
        const products = getUniqueProducts(allFeatures);

        const response = input.includeCount
          ? products
          : products.map(p => ({ name: p.name }));

        return {
          content: [
            {
              type: "text",
              text: `Total Products: ${products.length}\n\n${JSON.stringify(response, null, 2)}`
            }
          ]
        };
      }

      case "get_release_wave_summary": {
        const input = GetReleaseWaveSummaryInputSchema.parse(args);
        const allFeatures = await fetchAllReleasePlans();
        const summary = getWaveSummary(allFeatures, input.releaseWave);

        return {
          content: [
            {
              type: "text",
              text: JSON.stringify(summary, null, 2)
            }
          ]
        };
      }

      default:
        return {
          content: [
            {
              type: "text",
              text: `Unknown tool: ${name}`
            }
          ],
          isError: true
        };
    }
  } catch (error) {
    return {
      content: [
        {
          type: "text",
          text: `Error: ${error instanceof Error ? error.message : String(error)}`
        }
      ],
      isError: true
    };
  }
});

// Start server
async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
  console.error("Microsoft Release Planner MCP Server running on stdio");
}

main().catch((error) => {
  console.error("Fatal error in main():", error);
  process.exit(1);
});
