#!/bin/bash

set -euo pipefail

KEYVAULT_NAME="issuer-kv"

read -p "Enter VAULT_PWD: " VAULT_PWD
read -p "Enter UIPASSWORD: " UIPASSWORD
read -p "Enter ISSUERNAME: " ISSUERNAME
read -p "Enter PRIVATE_KEY: " PRIVATE_KEY
read -p "Enter ISSUER_RESOLVER_FILE (base64 encoded): " ISSUER_RESOLVER_FILE
read -p "Enter ISSUER_DB_PASSWORD: " ISSUER_DB_PASSWORD
read -p "Enter PRIVATE_KEY: " ISSUER_API_AUTH_PASSWORD

echo "Uploading secrets to Azure Key Vault: $KEYVAULT_NAME..."

az keyvault secret set --vault-name "$KEYVAULT_NAME" --name VAULT-PWD --value "$VAULT_PWD"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name UI-PASSWORD --value "$UIPASSWORD"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-NAME --value "$ISSUERNAME"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name PRIVATE-KEY --value "$PRIVATE_KEY"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-RESOLVER-FILE --value "$ISSUER_RESOLVER_FILE"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-DB-PASSWORD --value "$ISSUER_DB_PASSWORD"
az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-API-AUTH-PASSWORD --value "$ISSUER_API_AUTH_PASSWORD"

echo "All secrets uploaded successfully to Azure Key Vault: $KEYVAULT_NAME"
