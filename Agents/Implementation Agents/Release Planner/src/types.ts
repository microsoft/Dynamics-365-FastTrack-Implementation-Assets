// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
//
// DISCLAIMER: This code is provided as sample/reference code for educational
// and demonstration purposes only. It is provided "as-is" without warranty of
// any kind. Microsoft does not operate or support deployments created with this
// code. You are responsible for reviewing, testing, and securing any
// resources deployed in your own environment.

import { z } from "zod";

// Release Plan Feature Schema
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

// API Response Schema
export const ReleasePlanResponseSchema = z.object({
  morerecords: z.boolean(),
  "paging-cookie-encoded": z.string(),
  totalrecords: z.string(),
  results: z.array(ReleasePlanFeatureSchema)
});

export type ReleasePlanResponse = z.infer<typeof ReleasePlanResponseSchema>;

// Tool Input Schemas
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
