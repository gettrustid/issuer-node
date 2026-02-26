# Dev Issuer Instance Setup

This document outlines the steps required to deploy a separate dev issuer-node instance alongside the existing prod instance in the same AKS cluster.

## Overview

| Environment | Namespace | API Domain | UI Domain |
|-------------|-----------|------------|-----------|
| Prod | `trustid-issuer-prod` | `api-issuer.internal.trustid.life` | `ui-issuer.internal.trustid.life` |
| Dev | `trustid-issuer-dev` | `api-issuer.dev-internal.trustid.life` | `ui-issuer.dev-internal.trustid.life` |

---

## Infrastructure Required

### 1. Azure Key Vault (Dev)

Create a new Key Vault for dev secrets:

```bash
az keyvault create \
  --name kv-issuer-dev \
  --resource-group <resource-group> \
  --location <location>
```

**Required secrets (copy structure from prod with dev values):**

| Secret Name | Description |
|-------------|-------------|
| `PRIVATE-KEY` | Blockchain private key |
| `VAULT-PWD` | HashiCorp Vault password |
| `UI-PASSWORD` | UI authentication password |
| `ISSUER-NAME` | Issuer display name |
| `ISSUER-RESOLVER-FILE` | Resolver configuration |
| `ISSUER-DB-USER` | Postgres username |
| `ISSUER-DB-PASSWORD` | Postgres password |
| `ISSUER-DB-PORT` | Postgres port (5432) |
| `ISSUER-DB-NAME` | Database name |
| `ISSUER-API-AUTH-PASSWORD` | API authentication password |
| `ISSUER-KEY-STORE-PORT` | Vault port (8200) |
| `METAKEEP-BJJ-APP-API-KEY` | MetaKeep API key |
| `METAKEEP-BJJ-APP-API-SECRET` | MetaKeep API secret |

---

### 2. Managed Identity

Grant the AKS managed identity access to the new Key Vault:

```bash
# Get AKS managed identity
az aks show \
  --resource-group <resource-group> \
  --name <aks-cluster-name> \
  --query identityProfile.kubeletidentity.clientId -o tsv

# Grant access to Key Vault
az keyvault set-policy \
  --name kv-issuer-dev \
  --object-id <managed-identity-object-id> \
  --secret-permissions get list
```

---

### 3. TLS Certificate

Issue a wildcard certificate for `*.dev-internal.trustid.life`:

**Option A: ACME with Cloudflare DNS**
```bash
# Use existing cert-manager setup with new DNS zone
# Create certificate resource for *.dev-internal.trustid.life
```

**Option B: Self-signed (dev only)**
```bash
# Generate self-signed cert
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout dev-internal.key \
  -out dev-internal.crt \
  -subj "/CN=*.dev-internal.trustid.life"

# Create Kubernetes secret
kubectl create secret tls internal-wildcard-tls \
  --cert=dev-internal.crt \
  --key=dev-internal.key \
  -n trustid-issuer-dev
```

---

### 4. Private DNS Records

In Azure Private DNS zone `dev-internal.trustid.life`:

| Record | Type | Value |
|--------|------|-------|
| `api-issuer` | A | `<ingress-controller-internal-ip>` |
| `ui-issuer` | A | `<ingress-controller-internal-ip>` |

**Verify VNet link exists:**
```bash
az network private-dns link vnet list \
  --zone-name dev-internal.trustid.life \
  --resource-group <resource-group>
```

---

## Helm Configuration

### 5. Create values-dev.yaml

Create `k8s/helm/values-dev.yaml`:

```yaml
global:
  uidomain: ui-issuer.dev-internal.trustid.life
  apidomain: api-issuer.dev-internal.trustid.life

namespace: trustid-issuer-dev

# Azure Key Vault configuration
azure:
  managedIdentityClientId: "<dev-managed-identity-client-id>"
  tenantId: "<azure-tenant-id>"
  keyVaultName: "kv-issuer-dev"

# Optional: Override image tags for dev
# issuernode_repository_tag: dev-latest

# Optional: Dev-specific config
apiIssuerNode:
  configMap:
    issuerLogLevel: "-4"  # Debug level for dev
    issuerDeepLinkServerUrl: "https://dev.trustid.life/api"
```

---

### 6. Deploy Dev Instance

```bash
# Update helm dependencies
cd k8s/helm
helm dependency update

# Deploy dev issuer
helm upgrade --install issuer-node-dev . \
  -f values.yaml \
  -f values-dev.yaml \
  -n trustid-issuer-dev 
  # --create-namespace

# Verify deployment
kubectl get pods -n trustid-issuer-dev
kubectl get ingress -n trustid-issuer-dev
```

---

## Deployed Components (per namespace)

The helm chart deploys these components automatically:

| Component | Service Name | Port |
|-----------|--------------|------|
| API Server | `api-issuer-node-svc` | 3001 |
| UI Server | `ui-issuer-node-svc` | 8080 |
| Postgres | `postgres-issuer-node-svc` | 5432 |
| Redis | `redis-issuer-node-svc` | 6379 |
| Vault (HashiCorp) | `vault-issuer-node-svc` | 8200 |

---

## Shared Components (no changes needed)

| Component | Notes |
|-----------|-------|
| Ingress Controller | Shared `network-nginx` ingress class |
| ACR Images | Same container registry and images |
| AKS Cluster | Same cluster, different namespaces |

---

## Verification

### Test DNS resolution (from inside cluster):
```bash
kubectl run -it --rm debug --image=alpine -n trustid-issuer-dev -- sh
nslookup api-issuer.dev-internal.trustid.life
```

### Test API endpoint:
```bash
curl -k https://api-issuer.dev-internal.trustid.life/status
```

### Check logs:
```bash
kubectl logs -f deployment/api-issuer-node -n trustid-issuer-dev
```

---

## Update identity-ws-go

After dev issuer is deployed, update the identity-ws-go service:

```bash
kubectl set env deployment/<identity-ws-deployment> \
  -n dev \
  ISSUER_URL=https://api-issuer.dev-internal.trustid.life
```

Or update helm values for identity-ws-go to use the dev issuer URL.

---

## Checklist

- [ ] Azure Key Vault created with all secrets
- [ ] Managed Identity has access to Key Vault
- [ ] TLS certificate issued for `*.dev-internal.trustid.life`
- [ ] TLS secret created in `trustid-issuer-dev` namespace
- [ ] DNS A records created in `dev-internal.trustid.life` zone
- [ ] VNet linked to private DNS zone
- [ ] `values-dev.yaml` created with correct configuration
- [ ] Helm chart deployed to `trustid-issuer-dev` namespace
- [ ] All pods running successfully
- [ ] API endpoint accessible from cluster
- [ ] identity-ws-go updated to use dev issuer URL
