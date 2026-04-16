// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.
//
// DISCLAIMER: This code is provided as sample/reference code for educational
// and demonstration purposes only. It is provided "as-is" without warranty of
// any kind. Microsoft does not operate or support deployments created with this
// code. You are responsible for reviewing, testing, and securing any
// resources deployed in your own environment.

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

    const rawText = await response.text();
    const sanitizedText = rawText.replace(/\\\\|\\(?!["\\/bfnrtu])/g, (m) => m === '\\\\' ? m : '\\\\');
    const data = JSON.parse(sanitizedText);
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
