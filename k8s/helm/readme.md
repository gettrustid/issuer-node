# Overview

This is a helm chart for deploying Privado ID issuer node on Kubernetes.
To learn more about Privado ID issuer, see [this](https://0xpolygonid.github.io/tutorials/issuer/issuer-overview).

## Installation

### Prerequisites

#### Set up command-line tools

Make sure you have these tools installed.

- [kubectl](https://kubernetes.io/docs/reference/kubectl/overview/)
- [helm](https://helm.sh/)

### Setup Ingress

The first step is update and modify the ingress chart (`charts/ingress`) according to your requirements. The issuer node works over HTTPS, so you need to provide a valid certificate. Certificate Installation sample [here](charts/ingress/certs/README.md)

### Setup volumes

How the volumes are set up depends on the cloud provider you are using, so you need to set up the volumes according to your cloud provider. Please, take a look at the [volumes](https://kubernetes.io/docs/concepts/storage/volumes/) documentation. You have to set up the volumes in the [vault pvc](charts/vault/templates/pvc.yaml) and [postgres pvc](charts/postgres/templates/pvc.yaml) file.

### Configure the app

To set up the app, you need to configure the following environment variables.
The ISSUER_RESOLVER_FILE is a base64 encoded string of the resolver file. You can take a look at the resolver file [here](../../resolvers_settings_sample.yaml)

```shell
export APP_INSTANCE_NAME=trustid-issuernode           # Sample name for the application
export NAMESPACE=identity                             # Namespace where you want to deploy the application
export UI_DOMAIN=ui.example.com                         # Domain for the UI.
export API_DOMAIN=api.example.com                       # Domain for the API.
export PRIVATE_KEY='YOUR PRIVATE KEY'                   # Private key of the wallet (Ethereum private key wallet).
export UIPASSWORD="my ui password"                      # Password for user: ui-user. This password is used when the user visit the ui.
export UI_INSECURE=true                                 # Set as true if the ui doesn't require basic auth. If this value true UIPASSWORD can be blank
export ISSUERNAME="My Issuer"                           # Issuer Name. This value is shown in the UI
export VAULT_PWD=password                               # Vault password to anable issuer node to connect with vault. Put the password you want to use.
export ISSUER_RESOLVER_FILE="cG9XYZ0K+"                 # Base64 encoded string of the resolver file. You can take a look at the resolver file [here](../../resolvers_settings_sample.yaml)
```

## Encode Resolver File

* Run encode_resolver.sh, can test default included sample matches Base64 encoding above
* Set base64 value as value for ISSUER_RESOLVER_FILE

## Pre-Populate Vault
* Use set_vault_secrets.sh , modify script as needed. This will populate the keyvault with secrets necessary for issuer


## App ACR Deployment 
Script
* Go to the project root and run `sh deploy-acr.sh`

Manual
* API - at root of project run 
```bash
docker build -t issuer.azurecr.io/issuernode-api:latest -f ./Dockerfile .

docker push issuer.azurecr.io/issuernode-api:latest
```

* UI - From within ui/ folder (separate dockerfile) run:
```bash
docker build -t issuer.azurecr.io/issuernode-ui:latest -f ./Dockerfile .

docker push issuer.azurecr.io/issuernode-ui:latest 

```




#### Install TrustId Issuer

```bash
helm install trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml \
  -f values.secrets.yaml
```
#### Upgrade
```bash
helm upgrade trustid-issuer . \
  --namespace trustid-issuer \
  -f values.yaml \
  -f values.secrets.yaml
```
```bash
helm uninstall trustid-issuer --namespace trustid-issuer
```
## Ingress 
* /ingress is default with cloudflare since the original stack was public 
* using /ingress-nginx instead
* run ingress-deploy.sh to deploy it to cluster

## Acme DNS - SSL
* We have an acme dns server running on our primary cluster prod_apps (20.157.88.74)
* This cluster will point to that server for DNS-01 challenges and cert management
* We use a **wildcard certificate** (`*.internal.trustid.life`) to cover all subdomains

### Setup Instructions

1. **Create your acmedns.json from the sample:**
   ```bash
   cp k8s/helm/charts/ingress-nginx/acmedns.json.sample k8s/helm/charts/ingress-nginx/acmedns.json
   ```

2. **Fill in credentials** - Get these from your primary cluster's ACME DNS server
   - You only need entries for `*.internal.trustid.life` and `internal.trustid.life`
   - No need to add specific subdomains if using the wildcard certificate approach

3. **Create the Kubernetes secret:**
   ```bash
   kubectl create secret generic acmedns-credentials \
     --from-file=k8s/helm/charts/ingress-nginx/acmedns.json \
     --namespace=cert-manager \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

### Key Configuration Files

- **ClusterIssuer:** `k8s/helm/charts/ingress-nginx/clusterissuer-acmedns.yaml` - Points to ACME DNS at 20.157.88.74
- **Wildcard Cert:** `k8s/helm/charts/ingress-nginx/certificate-wildcard-internal.yaml` - Creates `*.internal.trustid.life` cert
- **Ingress Rules:** `k8s/helm/charts/ingress-nginx/templates/ingress-rules.yaml` - **NOTE:** The `cert-manager.io/cluster-issuer` annotation should be commented out to use the standalone wildcard certificate

### Updating ACME DNS Credentials

If you need to update the acmedns.json (e.g., for a new cluster):

```bash
# 1. Update the secret
kubectl create secret generic acmedns-credentials \
  --from-file=k8s/helm/charts/ingress-nginx/acmedns.json \
  --namespace=cert-manager \
  --dry-run=client -o yaml | kubectl apply -f -

# 2. Restart cert-manager to pick up new credentials
kubectl rollout restart deployment cert-manager -n cert-manager

# 3. Force certificate renewal
kubectl delete certificate internal-wildcard-tls -n trustid-issuer
kubectl apply -f k8s/helm/charts/ingress-nginx/certificate-wildcard-internal.yaml

# 4. Watch certificate status (should be Ready in 1-5 minutes)
kubectl get certificate internal-wildcard-tls -n trustid-issuer -w
```

### cert-manager DNS Resolution

cert-manager is configured to use public DNS (`8.8.8.8`, `1.1.1.1`) for ACME DNS-01 challenge verification via `k8s/helm/charts/cert-manager-values.yaml`. This is required because the Azure Private DNS zone for `internal.trustid.life` has a wildcard A record (`*.internal.trustid.life → 10.3.0.10`) that intercepts `_acme-challenge` queries inside the cluster, preventing the CNAME from resolving to the acmeDNS server.

**Install cert-manager with these values:**
```bash
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true \
  -f k8s/helm/charts/cert-manager-values.yaml
```

**Upgrade existing cert-manager:**
```bash
helm upgrade cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  -f k8s/helm/charts/cert-manager-values.yaml
```

### Troubleshooting

- Check certificate status: `kubectl describe certificate internal-wildcard-tls -n trustid-issuer`
- Check challenges: `kubectl get challenges -n trustid-issuer`
- Check cert-manager logs: `kubectl logs -n cert-manager -l app=cert-manager --tail=50`
- Verify secret exists: `kubectl get secret internal-wildcard-tls -n trustid-issuer`


- Create simple curl pod `kubectl run curl-test --image=curlimages/curl:latest -it --rm -- /bin/sh`
- send curl request in pod to test `curl -k https://api-issuer.internal.trustid.life/status`