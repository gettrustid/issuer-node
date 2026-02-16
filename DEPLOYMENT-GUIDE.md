# TrustID Issuer Node - Deployment Guide

Complete deployment guide for the TrustID Issuer Node on AKS (Azure Kubernetes Service), covering both **prod** and **dev** environments.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Cluster Layout](#cluster-layout)
- [DNS Architecture](#dns-architecture)
- [SSL/TLS Certificate Architecture](#ssltls-certificate-architecture)
- [Prerequisites](#prerequisites)
- [Part 1: Shared Infrastructure](#part-1-shared-infrastructure)
- [Part 2: Prod Deployment](#part-2-prod-deployment)
- [Part 3: Dev Deployment](#part-3-dev-deployment)
- [Certificate Renewal and Troubleshooting](#certificate-renewal-and-troubleshooting)
- [Operational Runbook](#operational-runbook)
- [File Reference](#file-reference)

---

## Architecture Overview

The TrustID Issuer Node is a Privado ID (formerly Polygon ID) issuer deployed on Azure Kubernetes Service. It issues and manages verifiable credentials using zero-knowledge proofs on blockchain.

### Application Components (per environment)

Each environment deploys a complete, isolated stack:

| Component | Description | Port |
|-----------|-------------|------|
| **API Server** | Core issuer API (credential issuance, proof verification) | 3001 |
| **UI Server** | Web management interface | 8080 (→80) |
| **PostgreSQL** | Credential and state storage | 5432 |
| **Redis** | Caching and session management | 6379 |
| **Vault (HashiCorp)** | Key management (stores blockchain private keys, signing keys) | 8200 |
| **Notifications** | Background worker for push notifications | - |
| **Pending Publisher** | Background worker for on-chain state publishing | - |

### Key Management

- **BJJ Keys**: Managed by MetaKeep (cloud KMS) via `METAKEEP_BJJ_APP_API_KEY`
- **ETH Keys**: Managed by HashiCorp Vault (in-cluster)
- **Blockchain Private Key**: Stored in Azure Key Vault, mounted via CSI driver

---

## Cluster Layout

```
AKS Cluster (issuer-cluster)
├── Namespace: cert-manager
│   └── cert-manager (shared across all environments)
│
├── Namespace: trustid-issuer (PROD)
│   ├── api-issuer-node (Deployment)
│   ├── ui-issuer-node (Deployment)
│   ├── notifications-issuer-node (Deployment)
│   ├── pending-publisher-issuer-node (Deployment)
│   ├── postgres-issuer-node (Deployment + PVC)
│   ├── redis-issuer-node (Deployment)
│   ├── vault-issuer-node (Deployment + PVC)
│   ├── issuer-ingress (NGINX Ingress Controller)
│   ├── issuer-node-ingress (Ingress Rules)
│   └── internal-wildcard-tls (TLS Secret)
│
├── Namespace: trustid-issuer-dev (DEV)
│   ├── api-issuer-node (Deployment)
│   ├── ui-issuer-node (Deployment)
│   ├── notifications-issuer-node (Deployment)
│   ├── pending-publisher-issuer-node (Deployment)
│   ├── postgres-issuer-node (Deployment + PVC)
│   ├── redis-issuer-node (Deployment)
│   ├── vault-issuer-node (Deployment + PVC)
│   ├── issuer-node-ingress (Ingress Rules)
│   └── dev-internal-wildcard-tls (TLS Secret)
│
└── Shared Resources
    ├── StorageClass: managed-csi-retain
    └── IngressClass: network-nginx
```

### Multi-Cluster Context

There are **two AKS clusters** involved:

| Cluster | Purpose | Key Services |
|---------|---------|--------------|
| **prod_apps** (primary) | Runs production applications, ACME DNS server | ACME DNS at `20.157.88.74` (prod) and `20.157.88.70` (dev) |
| **issuer-cluster** (this repo) | Runs issuer node (prod + dev) | Issuer API, UI, Vault, Postgres, Redis |

The issuer cluster depends on the primary cluster for:
- ACME DNS server (certificate issuance via DNS-01 challenges)
- Cross-cluster routing via Azure Private DNS wildcard records

---

## DNS Architecture

### Domain Structure

| Environment | Base Domain | API | UI |
|-------------|-------------|-----|-----|
| **Prod** | `internal.trustid.life` | `api-issuer.internal.trustid.life` | `ui-issuer.internal.trustid.life` |
| **Dev** | `dev-internal.trustid.life` | `api-issuer.dev-internal.trustid.life` | `ui-issuer.dev-internal.trustid.life` |

### Azure Private DNS Zones

Two private DNS zones are linked to the cluster VNet:

**Zone: `internal.trustid.life`** (Prod)
| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `api-issuer` | A | `<issuer-ingress-internal-ip>` | Routes API traffic to issuer cluster |
| `ui-issuer` | A | `<issuer-ingress-internal-ip>` | Routes UI traffic to issuer cluster |
| `*` | A | `10.3.0.10` | Wildcard routes all other subdomains to the primary cluster |

**Zone: `dev-internal.trustid.life`** (Dev)
| Record | Type | Value | Purpose |
|--------|------|-------|---------|
| `api-issuer` | A | `<issuer-ingress-internal-ip>` | Routes dev API traffic |
| `ui-issuer` | A | `<issuer-ingress-internal-ip>` | Routes dev UI traffic |

### DNS Resolution Flow (Internal)

```
Pod in cluster → Azure Private DNS → Ingress Controller (internal LB) → Service → Pod
```

All traffic stays internal - the ingress controller uses an Azure Internal Load Balancer on `issuer-subnet`.

---

## SSL/TLS Certificate Architecture

### How Certificates Are Issued

```
┌─────────────────────────────────────────────────────────────────┐
│                    Certificate Issuance Flow                     │
│                                                                  │
│  cert-manager                                                    │
│       │                                                          │
│       ├── 1. Creates ACME order with Let's Encrypt               │
│       ├── 2. Gets challenge token                                │
│       ├── 3. Sends token to ACME DNS server                      │
│       │       │                                                  │
│       │       └── ACME DNS server (on primary cluster)           │
│       │           └── Creates TXT record:                        │
│       │               _acme-challenge.internal.trustid.life      │
│       │               → CNAME → <subdomain>.auth.trustid.life   │
│       │                                                          │
│       ├── 4. Verifies challenge via PUBLIC DNS (8.8.8.8/1.1.1.1)│
│       │       (bypasses Azure Private DNS wildcard)              │
│       │                                                          │
│       └── 5. Certificate issued, stored as K8s Secret            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

### Certificate Resources

| Environment | Certificate Name | Secret Name | Domain | ClusterIssuer | Namespace |
|-------------|-----------------|-------------|--------|---------------|-----------|
| **Prod** | `internal-wildcard-tls` | `internal-wildcard-tls` | `*.internal.trustid.life` | `le-prod-acmedns` | `trustid-issuer` |
| **Dev** | `dev-internal-wildcard-tls` | `dev-internal-wildcard-tls` | `*.dev-internal.trustid.life` | `le-dev-acmedns` | `trustid-issuer-dev` |

### ACME DNS Servers

| Environment | ACME DNS Host | ClusterIssuer |
|-------------|---------------|---------------|
| **Prod** | `http://20.157.88.74` | `le-prod-acmedns` |
| **Dev** | `http://20.157.88.70` | `le-dev-acmedns` |

### Critical: Public DNS for Challenge Verification

cert-manager is configured with `--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53` and `--dns01-recursive-nameservers-only` via `k8s/helm/charts/cert-manager-values.yaml`.

**Why this is required**: The Azure Private DNS zone for `internal.trustid.life` has a wildcard A record (`* → 10.3.0.10`). Without this setting, cert-manager tries to verify the ACME challenge TXT record using cluster-local DNS, which hits the wildcard and returns an IP address instead of following the CNAME to the ACME DNS server. Public DNS resolves the CNAME correctly because it doesn't see the private wildcard record.

```
WITHOUT fix:  _acme-challenge.internal.trustid.life → 10.3.0.10 (wildcard match, FAILS)
WITH fix:     _acme-challenge.internal.trustid.life → CNAME → acmeDNS TXT record (WORKS)
```

The dev environment (`dev-internal.trustid.life`) does not have a wildcard record in its private DNS zone, so it would work either way, but the setting applies globally to cert-manager and doesn't affect it negatively.

---

## Prerequisites

### Tools Required

- `kubectl` configured for the issuer AKS cluster
- `helm` v3+
- `az` CLI (authenticated with Azure subscription access)
- Access to Azure Key Vault(s)

### Azure Resources Required

| Resource | Prod | Dev |
|----------|------|-----|
| AKS Cluster | Shared | Shared |
| Azure Key Vault | `issuer-kv` | `issuer-dev-kv` |
| Managed Identity | Cluster kubelet identity with Key Vault access | Same identity, access to dev KV |
| Private DNS Zone | `internal.trustid.life` | `dev-internal.trustid.life` |
| VNet Link | DNS zone linked to cluster VNet | DNS zone linked to cluster VNet |

---

## Part 1: Shared Infrastructure

These steps are done **once** for the cluster, shared by both prod and dev.

### 1.1 Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm repo update

# Install with custom values for public DNS challenge verification
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.24/cert-manager.crds.yaml

kubectl create namespace cert-manager

# If installing fresh via Helm:
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --set installCRDs=true \
  -f k8s/helm/charts/cert-manager-values.yaml
```

**If cert-manager was installed via kubectl (not Helm)**, apply the DNS config via patch:

```bash
kubectl -n cert-manager patch deployment cert-manager --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53"},{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers-only"}]'
```

**Verify** the args are applied:

```bash
kubectl -n cert-manager get deployment cert-manager -o jsonpath='{.spec.template.spec.containers[0].args}' | jq .
```

### 1.2 Install NGINX Ingress Controller (Internal Load Balancer)

The ingress controller is shared across prod and dev via the `network-nginx` ingress class.

```bash
cd k8s/helm/charts/ingress-nginx
./ingress-deploy-internal.sh
```

This script:
1. Adds the `ingress-nginx` Helm repo
2. Installs with Azure Internal Load Balancer annotations (`service.beta.kubernetes.io/azure-load-balancer-internal: "true"`) on `issuer-subnet`
3. Sets ingress class to `network-nginx`
4. Enables SSL redirect and force-SSL

**Get the internal IP** (needed for DNS records):

```bash
kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

### 1.3 Create StorageClass

The Helm chart creates a `managed-csi-retain` StorageClass with `Retain` reclaim policy for Vault and Postgres PVCs. This is created automatically by the first `helm install` and skipped by subsequent environments (`skipStorageClass: true` in `values-dev.yaml`).

---

## Part 2: Prod Deployment

### 2.1 Azure Key Vault Secrets

Populate the prod Key Vault with all required secrets:

```bash
cd k8s/helm
./set_vault_secrets.sh
```

The script prompts for each secret value interactively. Required secrets:

| Secret Name | Description |
|-------------|-------------|
| `VAULT-PWD` | HashiCorp Vault password |
| `UI-PASSWORD` | UI login password |
| `ISSUER-NAME` | Display name for the issuer |
| `PRIVATE-KEY` | Blockchain wallet private key |
| `ISSUER-RESOLVER-FILE` | Base64-encoded resolver config |
| `ISSUER-DB-USER` | PostgreSQL username |
| `ISSUER-DB-PASSWORD` | PostgreSQL password |
| `ISSUER-DB-PORT` | PostgreSQL port (typically `5432`) |
| `ISSUER-DB-NAME` | Database name |
| `ISSUER-API-AUTH-PASSWORD` | API authentication password |
| `ISSUER-KEY-STORE-PORT` | Vault port (typically `8200`) |
| `METAKEEP-BJJ-APP-API-KEY` | MetaKeep KMS API key |
| `METAKEEP-BJJ-APP-API-SECRET` | MetaKeep KMS API secret |

### 2.2 Configure values.secrets.yaml

Copy the sample and fill in Azure identity values:

```bash
cp k8s/helm/values.secrets.sample.yaml k8s/helm/values.secrets.yaml
```

Edit `values.secrets.yaml` with:
- `keyVaultName`: Your prod Key Vault name
- `tenantId`: Azure tenant ID
- `clientId`: AKS kubelet managed identity client ID

### 2.3 Create ACME DNS Credentials

```bash
cd k8s/helm/charts/ingress-nginx

# Copy sample and fill in credentials from the ACME DNS server
cp acmedns.json.sample acmedns.json
# Edit acmedns.json with real credentials

# Create the K8s secret
kubectl create secret generic acmedns-credentials \
  --from-file=acmedns.json \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -
```

The `acmedns.json` file maps domains to ACME DNS registration credentials. It contains entries for `*.internal.trustid.life` and `internal.trustid.life`, each with a username, password, fulldomain, and subdomain from the ACME DNS server.

### 2.4 Create ClusterIssuer (Prod)

```bash
kubectl apply -f k8s/helm/charts/ingress-nginx/clusterissuer-acmedns.yaml
```

This creates ClusterIssuer `le-prod-acmedns` pointing to:
- Let's Encrypt production ACME server
- ACME DNS server at `http://20.157.88.74`
- Handles zones: `internal.trustid.life`, `external.trustid.life`, `trustid.life`

### 2.5 Issue Wildcard Certificate (Prod)

```bash
kubectl apply -f k8s/helm/charts/ingress-nginx/certificate-wildcard-internal.yaml
```

This creates a Certificate resource for `*.internal.trustid.life` in the `trustid-issuer` namespace. cert-manager will:
1. Create an ACME order with Let's Encrypt
2. Use ACME DNS for DNS-01 challenge
3. Verify via public DNS (8.8.8.8, 1.1.1.1)
4. Store the issued cert as secret `internal-wildcard-tls`

**Watch for issuance** (should complete in 2-5 minutes):

```bash
kubectl get certificate internal-wildcard-tls -n trustid-issuer -w
```

### 2.6 Azure Private DNS Records (Prod)

In the Azure Private DNS zone `internal.trustid.life`, create A records pointing to the ingress controller's internal IP:

```bash
INTERNAL_IP=$(kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name internal.trustid.life \
  --record-set-name api-issuer \
  --ipv4-address $INTERNAL_IP

az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name internal.trustid.life \
  --record-set-name ui-issuer \
  --ipv4-address $INTERNAL_IP
```

Ensure the DNS zone is linked to the cluster VNet:

```bash
az network private-dns link vnet create \
  --resource-group <resource-group> \
  --zone-name internal.trustid.life \
  --name issuer-cluster-link \
  --virtual-network <vnet-name> \
  --registration-enabled false
```

### 2.7 Deploy Prod Issuer

```bash
cd k8s/helm

helm install trustid-issuer . \
  --namespace trustid-issuer \
  --create-namespace \
  -f values.yaml \
  -f values.secrets.yaml
```

**Upgrade existing deployment:**

```bash
helm upgrade trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml \
  -f values.secrets.yaml
```

### 2.8 Verify Prod

```bash
# Check all pods are running
kubectl get pods -n trustid-issuer

# Check ingress
kubectl get ingress -n trustid-issuer

# Check certificate
kubectl get certificate -n trustid-issuer

# Test from inside the cluster
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never \
  -- curl -s https://api-issuer.internal.trustid.life/status
```

---

## Part 3: Dev Deployment

### 3.1 Azure Key Vault Secrets (Dev)

Create a separate Key Vault and populate with dev values:

```bash
az keyvault create \
  --name issuer-dev-kv \
  --resource-group <resource-group> \
  --location <location>

# Grant AKS managed identity access
az keyvault set-policy \
  --name issuer-dev-kv \
  --object-id <managed-identity-object-id> \
  --secret-permissions get list

# Populate secrets
cd k8s/helm
./set_vault_secrets_dev.sh
```

### 3.2 Configure values.secrets-dev.yaml

Create `k8s/helm/values.secrets-dev.yaml` with dev Azure identity values:

```yaml
global:
  azure:
    keyVaultName: issuer-dev-kv
    tenantId: <your-tenant-id>
    clientId: <your-managed-identity-client-id>
```

### 3.3 Create ACME DNS Credentials (Dev)

The dev environment uses a separate ACME DNS server. If the `acmedns.json` already contains entries for `*.dev-internal.trustid.life`, update the existing secret. Otherwise, create a separate credentials file with dev entries and apply:

```bash
kubectl create secret generic acmedns-credentials \
  --from-file=acmedns.json \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -
```

### 3.4 Create ClusterIssuer (Dev)

```bash
kubectl apply -f k8s/helm/charts/ingress-nginx/clusterissuer-acmedns-dev.yaml
```

This creates ClusterIssuer `le-dev-acmedns` pointing to:
- Let's Encrypt production ACME server
- ACME DNS server at `http://20.157.88.70` (different from prod)
- Handles zones: `dev-internal.trustid.life`, `dev-external.trustid.life`, `trustid.life`

### 3.5 Issue Wildcard Certificate (Dev)

```bash
kubectl apply -f k8s/helm/charts/ingress-nginx/certificate-wildcard-dev-internal.yaml
```

Creates a Certificate for `*.dev-internal.trustid.life` in the `trustid-issuer-dev` namespace, stored as secret `dev-internal-wildcard-tls`.

```bash
kubectl get certificate dev-internal-wildcard-tls -n trustid-issuer-dev -w
```

### 3.6 Azure Private DNS Records (Dev)

Create the `dev-internal.trustid.life` private DNS zone and records:

```bash
# Create zone (if not exists)
az network private-dns zone create \
  --resource-group <resource-group> \
  --name dev-internal.trustid.life

# Link to VNet
az network private-dns link vnet create \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --name issuer-cluster-link-dev \
  --virtual-network <vnet-name> \
  --registration-enabled false

# Create A records
INTERNAL_IP=$(kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --record-set-name api-issuer \
  --ipv4-address $INTERNAL_IP

az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --record-set-name ui-issuer \
  --ipv4-address $INTERNAL_IP
```

### 3.7 Deploy Dev Issuer

```bash
cd k8s/helm

helm upgrade --install issuer-node-dev . \
  --namespace trustid-issuer-dev \
  --create-namespace \
  -f values.yaml \
  -f values-dev.yaml \
  -f values.secrets-dev.yaml
```

Key differences from prod managed by `values-dev.yaml`:
- Namespace: `trustid-issuer-dev`
- Domains: `*.dev-internal.trustid.life`
- TLS secret: `dev-internal-wildcard-tls`
- `skipStorageClass: true` (uses the StorageClass created by prod)
- Environment labels on all deployments

### 3.8 Verify Dev

```bash
# Check all pods are running
kubectl get pods -n trustid-issuer-dev

# Check ingress
kubectl get ingress -n trustid-issuer-dev

# Check certificate
kubectl get certificate -n trustid-issuer-dev

# Test from inside the cluster
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never \
  -- curl -s https://api-issuer.dev-internal.trustid.life/status
```

---

## Certificate Renewal and Troubleshooting

### Automatic Renewal

cert-manager automatically renews certificates 30 days before expiry. No manual intervention should be needed under normal operation.

### The Wildcard DNS Problem (Feb 2026 Incident)

**Symptom**: Prod certificate renewal fails with:
```
Could not determine authoritative nameservers for "_acme-challenge.internal.trustid.life."
```

**Root cause**: The Azure Private DNS zone for `internal.trustid.life` has a wildcard A record (`* → 10.3.0.10`). When cert-manager tries to verify the DNS-01 challenge, it queries the cluster DNS, which hits the wildcard and returns an IP address instead of following the CNAME to the ACME DNS server.

**Why dev was unaffected**: The `dev-internal.trustid.life` zone has no wildcard record.

**Why it initially worked (Nov 2025)**: The wildcard record didn't exist yet when the certificate was first issued. It was added later to route cross-cluster traffic.

**Fix applied**: Added `--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53` and `--dns01-recursive-nameservers-only` to the cert-manager deployment. This tells cert-manager to verify ACME challenges via public DNS, which doesn't see the private wildcard record. All other cluster DNS resolution (pods, services, etc.) is unaffected.

**How the fix was applied**:

```bash
# Step 1: Patch cert-manager deployment (cert-manager was not installed via Helm)
kubectl -n cert-manager patch deployment cert-manager --type=json \
  -p='[{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers=8.8.8.8:53,1.1.1.1:53"},{"op":"add","path":"/spec/template/spec/containers/0/args/-","value":"--dns01-recursive-nameservers-only"}]'

# Step 2: Delete failed certificate and challenges
kubectl delete certificate internal-wildcard-tls -n trustid-issuer
kubectl delete challenges --all -n trustid-issuer

# Step 3: Recreate certificate
kubectl apply -f k8s/helm/charts/ingress-nginx/certificate-wildcard-internal.yaml

# Step 4: Verify (completed in ~3 minutes)
kubectl get certificate internal-wildcard-tls -n trustid-issuer
# NAME                    READY   SECRET                  AGE
# internal-wildcard-tls   True    internal-wildcard-tls   3m44s
```

**The fix is persisted** in `k8s/helm/charts/cert-manager-values.yaml` for future cert-manager installations.

### Manual Certificate Renewal

If a certificate needs to be manually renewed:

```bash
# Delete the certificate (cert-manager will re-issue)
kubectl delete certificate <cert-name> -n <namespace>
kubectl delete challenges --all -n <namespace>

# Recreate
kubectl apply -f k8s/helm/charts/ingress-nginx/<certificate-file>.yaml

# Watch for issuance
kubectl get certificate <cert-name> -n <namespace> -w
```

### Troubleshooting Checklist

```bash
# 1. Check certificate status
kubectl describe certificate <cert-name> -n <namespace>

# 2. Check challenges (should be empty if cert is issued)
kubectl get challenges -n <namespace>

# 3. Check challenge details (if stuck)
kubectl describe challenge -n <namespace>

# 4. Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager --since=10m | grep <domain>

# 5. Verify ACME DNS credentials exist
kubectl get secret acmedns-credentials -n cert-manager

# 6. Verify cert-manager has recursive nameserver args
kubectl -n cert-manager get deployment cert-manager \
  -o jsonpath='{.spec.template.spec.containers[0].args}' | jq .

# 7. Test DNS resolution from inside cluster
kubectl run dns-test --image=curlimages/curl:latest --rm -it --restart=Never \
  -- curl -s https://api-issuer.internal.trustid.life/status

# 8. Check TLS secret exists
kubectl get secret <secret-name> -n <namespace>
```

---

## Operational Runbook

### Updating Application Images

```bash
# Build and push to ACR
docker build -t issuer.azurecr.io/issuernode-api:latest -f ./Dockerfile .
docker push issuer.azurecr.io/issuernode-api:latest

docker build -t issuer.azurecr.io/issuernode-ui:latest -f ./Dockerfile ./ui/
docker push issuer.azurecr.io/issuernode-ui:latest

# Restart deployments to pull new images
kubectl rollout restart deployment api-issuer-node -n <namespace>
kubectl rollout restart deployment ui-issuer-node -n <namespace>
```

### Updating Configuration

```bash
# Prod
helm upgrade trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml \
  -f values.secrets.yaml

# Dev
helm upgrade issuer-node-dev . \
  --namespace trustid-issuer-dev \
  -f values.yaml \
  -f values-dev.yaml \
  -f values.secrets-dev.yaml
```

### Updating ACME DNS Credentials

```bash
# 1. Update acmedns.json with new credentials

# 2. Update the K8s secret
kubectl create secret generic acmedns-credentials \
  --from-file=k8s/helm/charts/ingress-nginx/acmedns.json \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -

# 3. Restart cert-manager
kubectl rollout restart deployment cert-manager -n cert-manager

# 4. Force certificate renewal (if needed)
kubectl delete certificate <cert-name> -n <namespace>
kubectl apply -f k8s/helm/charts/ingress-nginx/<certificate-file>.yaml
```

### Testing Connectivity (from inside cluster)

```bash
# Quick test - creates temporary pod, tests, cleans up
kubectl run curl-test --image=curlimages/curl:latest --rm -it --restart=Never \
  -- sh -c '
    echo "PROD:" && curl -s -o /dev/null -w "HTTP %{http_code}\n" https://api-issuer.internal.trustid.life/status &&
    echo "DEV:" && curl -s -o /dev/null -w "HTTP %{http_code}\n" https://api-issuer.dev-internal.trustid.life/status
  '
```

### Viewing Logs

```bash
# API logs
kubectl logs -f deployment/api-issuer-node -n <namespace>

# cert-manager logs (for certificate issues)
kubectl logs -n cert-manager deployment/cert-manager --since=10m

# Ingress controller logs
kubectl logs -n trustid-issuer deployment/issuer-ingress-ingress-nginx-controller
```

---

## File Reference

### Helm Chart Structure

```
k8s/helm/
├── Chart.yaml
├── values.yaml                    # Prod values (domains, config, images)
├── values-dev.yaml                # Dev overrides (domains, namespace, labels)
├── values.secrets.yaml            # Prod Azure identity (gitignored)
├── values.secrets-dev.yaml        # Dev Azure identity (gitignored)
├── values.secrets.sample.yaml     # Template for secrets files
├── set_vault_secrets.sh           # Script to populate prod Key Vault
├── set_vault_secrets_dev.sh       # Script to populate dev Key Vault
│
├── templates/                     # Main app templates
│   ├── issuer-node-api-deployment.yaml
│   ├── issuer-node-api-configmap.yaml
│   ├── issuer-node-api-service.yaml
│   ├── issuer-node-ui-deployment.yaml
│   ├── issuer-node-ui-configmap.yaml
│   ├── issuer-node-ui-service.yaml
│   ├── issuer-node-notifications.yaml
│   ├── issuer-node-pending-publisher.yaml
│   ├── issuer-node-service-account.yaml
│   ├── azure-secrets-provider-class.yaml
│   └── storage-class-retain.yaml
│
├── charts/
│   ├── cert-manager-values.yaml   # cert-manager config (recursive nameservers)
│   │
│   ├── ingress-nginx/
│   │   ├── values.yaml                              # Ingress controller values
│   │   ├── ingress-deploy.sh                        # External LB deploy script
│   │   ├── ingress-deploy-internal.sh               # Internal LB deploy script
│   │   ├── templates/ingress-rules.yaml             # Helm-managed ingress rules
│   │   ├── ingress-rules.yml                        # Static ingress rules (legacy)
│   │   ├── clusterissuer-acmedns.yaml               # Prod ClusterIssuer
│   │   ├── clusterissuer-acmedns-dev.yaml           # Dev ClusterIssuer
│   │   ├── certificate-wildcard-internal.yaml       # Prod wildcard cert
│   │   ├── certificate-wildcard-dev-internal.yaml   # Dev wildcard cert
│   │   ├── acmedns.json.sample                      # ACME DNS credential template
│   │   ├── acmedns.json                             # ACME DNS credentials (gitignored)
│   │   ├── test-internal.sh                         # Internal connectivity test
│   │   └── test-pod.yaml                            # Test pod manifest
│   │
│   ├── postgres/                  # PostgreSQL subchart
│   ├── redis/                     # Redis subchart
│   └── vault/                     # HashiCorp Vault subchart
```

### Environment Comparison

| Aspect | Prod | Dev |
|--------|------|-----|
| Namespace | `trustid-issuer` | `trustid-issuer-dev` |
| API Domain | `api-issuer.internal.trustid.life` | `api-issuer.dev-internal.trustid.life` |
| UI Domain | `ui-issuer.internal.trustid.life` | `ui-issuer.dev-internal.trustid.life` |
| Key Vault | `issuer-kv` | `issuer-dev-kv` |
| ClusterIssuer | `le-prod-acmedns` | `le-dev-acmedns` |
| ACME DNS Host | `http://20.157.88.74` | `http://20.157.88.70` |
| TLS Secret | `internal-wildcard-tls` | `dev-internal-wildcard-tls` |
| Certificate Name | `internal-wildcard-tls` | `dev-internal-wildcard-tls` |
| Private DNS Zone | `internal.trustid.life` | `dev-internal.trustid.life` |
| Has DNS Wildcard | Yes (`* → 10.3.0.10`) | No |
| Values Files | `values.yaml` + `values.secrets.yaml` | `values.yaml` + `values-dev.yaml` + `values.secrets-dev.yaml` |
| StorageClass | Creates `managed-csi-retain` | Skips (uses existing) |
| Helm Release Name | `trustid-issuer` | `issuer-node-dev` |

### Sensitive Files (gitignored)

| File | Purpose |
|------|---------|
| `k8s/helm/values.secrets.yaml` | Prod Azure identity config |
| `k8s/helm/values.secrets-dev.yaml` | Dev Azure identity config |
| `k8s/helm/charts/ingress-nginx/acmedns.json` | ACME DNS credentials |

---

## Security Notes

- All traffic is internal-only via Azure Internal Load Balancer
- No public endpoints are exposed
- Secrets are stored in Azure Key Vault and mounted via CSI driver
- TLS is enforced at the ingress level (`force-ssl-redirect: true`)
- Certificates are issued by Let's Encrypt (publicly trusted CA)
- cert-manager's public DNS queries (`8.8.8.8`, `1.1.1.1`) are outbound-only UDP to port 53 for ACME challenge verification - no inbound ports are opened
