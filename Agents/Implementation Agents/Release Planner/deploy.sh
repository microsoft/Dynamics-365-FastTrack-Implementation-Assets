#!/bin/bash
# Copyright (c) Microsoft Corporation.
# Licensed under the MIT License.
#
# DISCLAIMER: This script is provided as sample/reference code for educational
# and demonstration purposes only. It is provided "as-is" without warranty of
# any kind. Microsoft does not operate or support deployments created with this
# script. You are responsible for reviewing, testing, and securing any
# resources deployed in your own environment.
#
# deploy.sh - Azure App Service Deployment Script
# Deploys the MCP server using WEBSITE_RUN_FROM_PACKAGE (bypasses Oryx build)
#
# Usage:
#   ./deploy.sh                                            # Deploy with defaults
#   ./deploy.sh --app-name my-app --resource-group my-rg   # Custom names
#   ./deploy.sh --setup                                    # First-time Azure setup + deploy

set -e

APP_NAME="rel-planner-mcp-server"
RESOURCE_GROUP="rel-planner-mcp-server-rg"
SETUP=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --app-name) APP_NAME="$2"; shift 2 ;;
        --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
        --setup) SETUP=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

echo ""
echo "================================================"
echo "  MCP Server - Azure Deployment"
echo "================================================"
echo ""

# One-time Azure setup
if [ "$SETUP" = true ]; then
    echo "[1/3] Removing conflicting settings..."
    az webapp config appsettings delete \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --setting-names CUSTOM_BUILD_COMMAND PRE_BUILD_COMMAND POST_BUILD_COMMAND WEBSITE_NODE_DEFAULT_VERSION 2>/dev/null || true

    echo "[2/3] Configuring Azure App Settings..."
    az webapp config appsettings set \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --settings WEBSITE_RUN_FROM_PACKAGE=1 SCM_DO_BUILD_DURING_DEPLOYMENT=false

    echo "[3/3] Setting startup command..."
    az webapp config set \
        --name "$APP_NAME" \
        --resource-group "$RESOURCE_GROUP" \
        --startup-file "node build/index-mcp.js"

    echo ""
    echo "Azure setup complete."
    echo ""
fi

# Step 1: Build TypeScript
echo "[Step 1/5] Building TypeScript..."
npm run build
echo "  Build complete."

# Step 2: Create staging directory
echo "[Step 2/5] Creating staging directory..."
rm -rf deploy-staging
mkdir -p deploy-staging
cp -r build deploy-staging/
cp package.json deploy-staging/
cp package-lock.json deploy-staging/
echo "  Staging directory created."

# Step 3: Install production dependencies only
echo "[Step 3/5] Installing production dependencies..."
cd deploy-staging
npm ci --omit=dev --silent
cd ..
echo "  Production dependencies installed."

# Step 4: Create ZIP
echo "[Step 4/5] Creating deployment package..."
rm -f deploy.zip
cd deploy-staging
zip -r ../deploy.zip . -q
cd ..
ZIP_SIZE=$(du -sh deploy.zip | cut -f1)
echo "  Package created: deploy.zip ($ZIP_SIZE)"

# Step 5: Deploy to Azure
echo "[Step 5/5] Deploying to Azure..."
az webapp deploy \
    --name "$APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --src-path deploy.zip \
    --type zip

# Cleanup
echo ""
echo "Cleaning up..."
rm -rf deploy-staging
rm -f deploy.zip

# Verify
HOSTNAME=$(az webapp show --name "$APP_NAME" --resource-group "$RESOURCE_GROUP" --query defaultHostName --output tsv)

echo ""
echo "Waiting for app to start..."
HEALTHY=false
for i in 1 2 3 4 5 6; do
    sleep 10
    if curl -sf "https://$HOSTNAME/health" > /dev/null 2>&1; then
        HEALTHY=true
        break
    fi
    echo "  Retry $i/6..."
done

echo ""
echo "================================================"
echo "  Deployment Complete!"
echo "================================================"
echo ""
echo "  MCP Endpoint:  https://$HOSTNAME/mcp"
echo "  Health Check:  https://$HOSTNAME/health"
if [ "$HEALTHY" = true ]; then
    echo "  Status:        HEALTHY"
else
    echo "  Status:        NOT YET RESPONDING (may still be starting)"
fi
echo ""
