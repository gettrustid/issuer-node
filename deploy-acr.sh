#!/bin/bash

# ACR Deployment Script
# Builds and pushes both API and UI containers to Azure Container Registry

set -e  # Exit on any error

# Configuration
ACR_REGISTRY="issuer.azurecr.io"
API_IMAGE="${ACR_REGISTRY}/issuernode-api:latest"
UI_IMAGE="${ACR_REGISTRY}/issuernode-ui:latest"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting ACR deployment...${NC}"

# Check if we're in the project root
if [ ! -f "Dockerfile" ]; then
    echo -e "${RED}Error: Dockerfile not found in current directory. Please run from project root.${NC}"
    exit 1
fi

# Check if ui directory exists
if [ ! -d "ui" ]; then
    echo -e "${RED}Error: ui directory not found. Please run from project root.${NC}"
    exit 1
fi

# Build and push API
echo -e "${YELLOW}Building API container...${NC}"
docker build -t "${API_IMAGE}" -f ./Dockerfile .

echo -e "${YELLOW}Pushing API container to ACR...${NC}"
docker push "${API_IMAGE}"

echo -e "${GREEN}✓ API container deployed successfully${NC}"

# Build and push UI
echo -e "${YELLOW}Building UI container...${NC}"
cd ui
docker build -t "${UI_IMAGE}" -f ./Dockerfile .

echo -e "${YELLOW}Pushing UI container to ACR...${NC}"
docker push "${UI_IMAGE}"

echo -e "${GREEN}✓ UI container deployed successfully${NC}"

# Return to project root
cd ..

echo -e "${GREEN}✓ All containers deployed successfully to ${ACR_REGISTRY}${NC}"
echo -e "${YELLOW}Images deployed:${NC}"
echo -e "  - ${API_IMAGE}"
echo -e "  - ${UI_IMAGE}"