#!/bin/bash

echo "Building Issuer API..."
docker build -t issuer.azurecr.io/issuernode-api:latest -f ./Dockerfile .
echo "Build Completed."

echo "Building Issuer UI..."
docker build -t issuer.azurecr.io/issuernode-ui:latest -f ./Dockerfile .
echo "Build Completed."

echo "Pushing Issuer API to ACR..."
docker push issuer.azurecr.io/issuernode-api:latest

echo "Pushing Issuer UI to ACR..."
docker push issuer.azurecr.io/issuernode-ui:latest

echo "done."
