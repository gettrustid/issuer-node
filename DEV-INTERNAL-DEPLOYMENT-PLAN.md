# Dev-Internal Issuer Deployment Plan

## Context

Deploy a separate dev instance of issuer-node within the same AKS cluster using `dev-internal` certificates. This internal-only service will be consumed by services in another cluster (running identity-ws-go) that uses certbot + Azure Private DNS for internal services and Cloudflare for external.

### Confirmed Prerequisites
- ✅ **acmeDNS Access**: Can register `dev-internal.trustid.life` zone with acmeDNS server
- ✅ **VNet Peering**: Clusters already peered - DNS resolution will work once zone is linked
- ✅ **TLS Trust**: identity-ws-go already trusts Let's Encrypt certs (Azure CA bundle)

### Current State
| Component | Production | Planned Dev |
|-----------|-----------|-------------|
| Namespace | `trustid-issuer` | `trustid-issuer-dev` |
| API Domain | `api-issuer.internal.trustid.life` | `api-issuer.dev-internal.trustid.life` |
| UI Domain | `ui-issuer.internal.trustid.life` | `ui-issuer.dev-internal.trustid.life` |
| Key Vault | `issuer-kv` | `kv-issuer-dev` |
| Certificate | `*.internal.trustid.life` | `*.dev-internal.trustid.life` (Let's Encrypt via acmeDNS) |

---

## Architecture Analysis

### Certificate Infrastructure (Current)

**ClusterIssuer `le-prod-acmedns`** (`k8s/helm/charts/ingress-nginx/clusterissuer-acmedns.yaml`):
- ACME v2 with custom acmeDNS server at `http://20.157.88.74`
- Supports DNS zones: `internal.trustid.life`, `external.trustid.life`, `trustid.life`
- Uses secret `acmedns-credentials` with registration credentials

**Key Insight**: The acmeDNS server must be configured to support `dev-internal.trustid.life` zone.

### Cross-Cluster Communication Flow

```
┌─────────────────────────────────┐     ┌──────────────────────────────────────┐
│  Other Cluster                  │     │  Issuer Cluster (this repo)          │
│  ┌──────────────────────┐       │     │  ┌────────────────────────────────┐  │
│  │  identity-ws-go      │       │     │  │  trustid-issuer-dev namespace  │  │
│  │  (certbot + cloudflare)     │────────▶│  api-issuer.dev-internal...     │  │
│  └──────────────────────┘       │     │  │  (cert-manager + acmeDNS)       │  │
│                                 │     │  └────────────────────────────────┘  │
│  Azure Private DNS resolution   │     │                                      │
└─────────────────────────────────┘     └──────────────────────────────────────┘
          │                                           │
          └───────────── VNet Peering ────────────────┘
                    (shared DNS resolution)
```

---

## Implementation Plan

### Phase 1: DNS Infrastructure

**1.1 Create Azure Private DNS Zone**
```bash
az network private-dns zone create \
  --resource-group <resource-group> \
  --name dev-internal.trustid.life
```

**1.2 Link VNet to DNS Zone (Issuer Cluster)**
```bash
az network private-dns link vnet create \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --name issuer-cluster-link \
  --virtual-network <issuer-vnet-name> \
  --registration-enabled false
```

**1.3 Link VNet to DNS Zone (Other Cluster)** - Critical for cross-cluster resolution
```bash
az network private-dns link vnet create \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --name other-cluster-link \
  --virtual-network <other-cluster-vnet-name> \
  --registration-enabled false
```

**1.4 Create DNS A Records**
```bash
# Get internal ingress IP
INGRESS_IP=$(kubectl get svc issuer-ingress-ingress-nginx-controller \
  -n trustid-issuer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

# API record
az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --record-set-name api-issuer \
  --ipv4-address $INGRESS_IP

# UI record
az network private-dns record-set a add-record \
  --resource-group <resource-group> \
  --zone-name dev-internal.trustid.life \
  --record-set-name ui-issuer \
  --ipv4-address $INGRESS_IP
```

---

### Phase 2: Certificate Configuration (Let's Encrypt via acmeDNS)

**2.1 Register Zone with acmeDNS Server**

On your acmeDNS server (20.157.88.74), register the new zone:

```bash
# SSH to acmeDNS server or use API
curl -X POST http://20.157.88.74/register \
  -d '{"allowfrom": ["<your-cert-manager-pod-ip-range>"]}' \
  -H "Content-Type: application/json"

# Save the returned credentials to update acmedns.json
```

Update `acmedns.json` with the new zone credentials (add entry for `dev-internal.trustid.life`).

**2.2 Update ClusterIssuer**

Modify `k8s/helm/charts/ingress-nginx/clusterissuer-acmedns.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: le-prod-acmedns
spec:
  acme:
    email: mona@tracerlabs.com
    server: https://acme-v02.api.letsencrypt.org/directory
    privateKeySecretRef:
      name: le-prod-account-key
    solvers:
      - selector:
          dnsZones:
            - internal.trustid.life
            - external.trustid.life
            - trustid.life
            - dev-internal.trustid.life  # ADD THIS LINE
        dns01:
          acmeDNS:
            host: http://20.157.88.74
            accountSecretRef:
              name: acmedns-credentials
              key: acmedns.json
```

**2.3 Update acmeDNS Credentials Secret**

```bash
# Update the secret with new zone credentials
kubectl create secret generic acmedns-credentials \
  --from-file=acmedns.json \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -
```

**2.4 Create Certificate Resource**

Create `k8s/helm/charts/ingress-nginx/certificate-wildcard-dev-internal.yaml`:

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: dev-internal-wildcard-tls
  namespace: trustid-issuer-dev
spec:
  secretName: dev-internal-wildcard-tls
  issuerRef:
    name: le-prod-acmedns
    kind: ClusterIssuer
    group: cert-manager.io
  dnsNames:
    - '*.dev-internal.trustid.life'
```

**2.5 Apply Certificate (after namespace creation)**

```bash
kubectl create namespace trustid-issuer-dev
kubectl apply -f k8s/helm/charts/ingress-nginx/certificate-wildcard-dev-internal.yaml
```

Since VNets are already peered and identity-ws-go trusts Let's Encrypt certs, no additional trust configuration is needed.

---

### Phase 3: Azure Key Vault Setup

**3.1 Create Dev Key Vault**
```bash
az keyvault create \
  --name kv-issuer-dev \
  --resource-group <resource-group> \
  --location <location>
```

**3.2 Grant AKS Managed Identity Access**
```bash
# Get kubelet identity
IDENTITY=$(az aks show \
  --resource-group <resource-group> \
  --name <aks-cluster-name> \
  --query identityProfile.kubeletidentity.objectId -o tsv)

az keyvault set-policy \
  --name kv-issuer-dev \
  --object-id $IDENTITY \
  --secret-permissions get list
```

**3.3 Populate Required Secrets**

| Secret Name | Description |
|-------------|-------------|
| `PRIVATE-KEY` | Blockchain private key (dev account) |
| `VAULT-PWD` | HashiCorp Vault password |
| `UI-PASSWORD` | UI authentication password |
| `ISSUER-NAME` | Dev issuer display name |
| `ISSUER-RESOLVER-FILE` | Resolver configuration |
| `ISSUER-DB-USER` | Postgres username |
| `ISSUER-DB-PASSWORD` | Postgres password |
| `ISSUER-DB-PORT` | `5432` |
| `ISSUER-DB-NAME` | Database name |
| `ISSUER-API-AUTH-PASSWORD` | API auth password |
| `ISSUER-KEY-STORE-PORT` | `8200` |
| `METAKEEP-BJJ-APP-API-KEY` | MetaKeep API key |
| `METAKEEP-BJJ-APP-API-SECRET` | MetaKeep API secret |

---

### Phase 4: Helm Configuration

**4.1 Create `k8s/helm/values-dev.yaml`**

```yaml
global:
  uidomain: ui-issuer.dev-internal.trustid.life
  apidomain: api-issuer.dev-internal.trustid.life

namespace: trustid-issuer-dev

# Use dev Key Vault
azure:
  managedIdentityClientId: "<dev-managed-identity-client-id>"
  tenantId: "acace14a-32db-405c-bdc1-a0caab828c76"
  keyVaultName: "kv-issuer-dev"

# Dev-specific configuration
apiIssuerNode:
  configMap:
    issuerLogLevel: "-4"  # Debug logging
    issuerDeepLinkServerUrl: "https://dev.trustid.life/api"

# TLS secret for dev-internal domain
ingress-nginx:
  enabled: true
  tlsSecretName: dev-internal-wildcard-tls
```

**4.2 Update Ingress Template** (if needed)

The ingress template at `k8s/helm/charts/ingress-nginx/templates/ingress-rules.yaml` uses `.Values.global.apidomain` and `.Values.global.uidomain`, so it should work automatically. However, verify the TLS secret name is configurable:

```yaml
# Verify this supports override or create a new template
tls:
- hosts:
  - {{ .Values.global.apidomain }}
  - {{ .Values.global.uidomain }}
  secretName: {{ .Values.tlsSecretName | default "internal-wildcard-tls" }}
```

---

### Phase 5: Deployment

**5.1 Deploy Dev Instance**
```bash
cd k8s/helm

# Update dependencies
helm dependency update

# Deploy to dev namespace
helm upgrade --install issuer-node-dev . \
  -f values.yaml \
  -f values-dev.yaml \
  -n trustid-issuer-dev \
  --create-namespace

# Verify deployment
kubectl get pods -n trustid-issuer-dev
kubectl get ingress -n trustid-issuer-dev
kubectl get certificate -n trustid-issuer-dev
```

**5.2 Verify Certificate Status**
```bash
# Check certificate is issued
kubectl describe certificate dev-internal-wildcard-tls -n trustid-issuer-dev

# Check secret exists
kubectl get secret dev-internal-wildcard-tls -n trustid-issuer-dev
```

---

### Phase 6: Cross-Cluster Connectivity

**6.1 Test DNS Resolution from Other Cluster**
```bash
# From a pod in the other cluster
kubectl run -it --rm debug --image=alpine -n dev -- sh
nslookup api-issuer.dev-internal.trustid.life
```

**6.2 Test API Connectivity**
```bash
# From other cluster
curl -k https://api-issuer.dev-internal.trustid.life/status
```

**6.3 Update identity-ws-go Configuration**
```bash
# In the other cluster
kubectl set env deployment/<identity-ws-deployment> \
  -n dev \
  ISSUER_URL=https://api-issuer.dev-internal.trustid.life
```

---

## Files to Create/Modify

| File | Action | Purpose |
|------|--------|---------|
| `k8s/helm/values-dev.yaml` | Create | Dev environment overrides |
| `k8s/helm/charts/ingress-nginx/certificate-wildcard-dev-internal.yaml` | Create | Dev wildcard certificate |
| `k8s/helm/charts/ingress-nginx/clusterissuer-acmedns.yaml` | Modify | Add dev-internal zone |
| `k8s/helm/charts/ingress-nginx/templates/ingress-rules.yaml` | Modify | Make TLS secret configurable |

---

## Verification Checklist

- [ ] Azure Private DNS zone `dev-internal.trustid.life` created
- [ ] VNet links created for both clusters
- [ ] DNS A records point to ingress controller IP
- [ ] Dev Key Vault created with all secrets
- [ ] AKS managed identity has Key Vault access
- [ ] acmeDNS zone registered
- [ ] Certificate resource created
- [ ] Certificate successfully issued (check `kubectl describe certificate`)
- [ ] TLS secret exists in `trustid-issuer-dev` namespace
- [ ] All pods running in `trustid-issuer-dev`
- [ ] API endpoint accessible from within cluster
- [ ] API endpoint accessible from other cluster
- [ ] identity-ws-go updated and connecting successfully

---

## Key Considerations

### Shared Ingress Controller

Both prod and dev use the same nginx ingress controller (class: `network-nginx`). The dev ingress will:
- Use different hostnames (dev-internal vs internal)
- Reference a different TLS secret (`dev-internal-wildcard-tls`)
- Route to services in `trustid-issuer-dev` namespace

This is safe because routing is based on hostname, not namespace.

### Database Isolation

Each namespace gets its own:
- PostgreSQL instance (`postgres-issuer-node-svc`)
- Redis instance (`redis-issuer-node-svc`)
- Vault instance (`vault-issuer-node-svc`)

The Helm chart deploys these as subcharts per namespace, so no data collision.

### Cross-Cluster DNS Flow

```
identity-ws-go (other cluster)
    │
    ├─── DNS query: api-issuer.dev-internal.trustid.life
    │
    ▼
Azure Private DNS (dev-internal.trustid.life zone)
    │
    ├─── VNet link to both clusters ✅
    │
    ▼
Returns: <ingress-controller-internal-ip>
    │
    ▼
TLS handshake (Let's Encrypt cert trusted ✅)
    │
    ▼
nginx ingress → api-issuer-node-svc (trustid-issuer-dev)
```

### Rollback Strategy

If issues occur, the dev deployment is isolated:
```bash
# Remove dev deployment (does not affect prod)
helm uninstall issuer-node-dev -n trustid-issuer-dev
kubectl delete namespace trustid-issuer-dev
```

### Monitoring

Consider adding dev-specific labels to distinguish metrics:
```yaml
# In values-dev.yaml
apiIssuerNode:
  deployment:
    labels:
      environment: dev
```
