#!/bin/bash

set -euo pipefail

KEYVAULT_NAME="issuer-kv"
ISSUER_RESOLVER_FILE="" # enter in manually but don't check in the value

read -p "Enter VAULT_PWD: " VAULT_PWD
read -p "Enter UIPASSWORD: " UIPASSWORD
read -p "Enter ISSUERNAME: " ISSUERNAME
read -p "Enter PRIVATE_KEY: " PRIVATE_KEY
read -p "Enter ISSUER_DB_USER: " ISSUER_DB_USER
read -p "Enter ISSUER_DB_PASSWORD: " ISSUER_DB_PASSWORD
read -p "Enter ISSUER_DB_PORT: " ISSUER_DB_PORT
read -p "Enter ISSUER_DB_NAME: " ISSUER_DB_NAME
read -p "Enter ISSUER_API_AUTH_PASSWORD: " ISSUER_API_AUTH_PASSWORD
read -p "Enter ISSUER_KEY_STORE_PORT: " ISSUER_KEY_STORE_PORT
read -p "Enter METAKEEP_BJJ_APP_API_KEY: " METAKEEP_BJJ_APP_API_KEY
read -p "Enter METAKEEP_BJJ_APP_API_SECRET: " METAKEEP_BJJ_APP_API_SECRET

echo "Uploading secrets to Azure Key Vault: $KEYVAULT_NAME..."

if [[ -n "${VAULT_PWD:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name VAULT-PWD --value "$VAULT_PWD"
fi
if [[ -n "${UIPASSWORD:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name UI-PASSWORD --value "$UIPASSWORD"
fi
if [[ -n "${ISSUERNAME:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-NAME --value "$ISSUERNAME"
fi
if [[ -n "${PRIVATE_KEY:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name PRIVATE-KEY --value "$PRIVATE_KEY"
fi
if [[ -n "${ISSUER_RESOLVER_FILE:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-RESOLVER-FILE --value "$ISSUER_RESOLVER_FILE"
fi
if [[ -n "${ISSUER_DB_USER:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-DB-USER --value "$ISSUER_DB_USER"
fi
if [[ -n "${ISSUER_DB_PASSWORD:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-DB-PASSWORD --value "$ISSUER_DB_PASSWORD"
fi
if [[ -n "${ISSUER_DB_PORT:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-DB-PORT --value "$ISSUER_DB_PORT"
fi
if [[ -n "${ISSUER_DB_NAME:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-DB-NAME --value "$ISSUER_DB_NAME"
fi
if [[ -n "${ISSUER_API_AUTH_PASSWORD:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-API-AUTH-PASSWORD --value "$ISSUER_API_AUTH_PASSWORD"
fi
if [[ -n "${ISSUER_KEY_STORE_PORT:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name ISSUER-KEY-STORE-PORT --value "$ISSUER_KEY_STORE_PORT"
fi
if [[ -n "${METAKEEP_BJJ_APP_API_KEY:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name METAKEEP-BJJ-APP-API-KEY --value "$METAKEEP_BJJ_APP_API_KEY"
fi
if [[ -n "${METAKEEP_BJJ_APP_API_SECRET:-}" ]]; then
    az keyvault secret set --vault-name "$KEYVAULT_NAME" --name METAKEEP-BJJ-APP-API-SECRET --value "$METAKEEP_BJJ_APP_API_SECRET"
fi


echo "All secrets uploaded successfully to Azure Key Vault: $KEYVAULT_NAME"
