# Azure Private DNS Setup Instructions

After running the setup script, you need to configure Azure Private DNS for internal domain resolution.

## 1. Create Private DNS Zone

```bash
# Create Private DNS Zone
az network private-dns zone create \
  --resource-group <your-resource-group> \
  --name trustid.int.app

# Link to your VNet (replace with your actual VNet name)
az network private-dns link vnet create \
  --resource-group <your-resource-group> \
  --zone-name trustid.int.app \
  --name trustid-link \
  --virtual-network <your-vnet-name> \
  --registration-enabled false
```

## 2. Get Ingress Internal IP

```bash
# Get the internal IP of your ingress controller
kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer -o jsonpath='{.status.loadBalancer.ingress[0].ip}'
```

## 3. Create DNS A Records

Replace `<INTERNAL-IP>` with the IP from step 2:

```bash
# API subdomain
az network private-dns record-set a add-record \
  --resource-group <your-resource-group> \
  --zone-name trustid.int.app \
  --record-set-name api.issuernode \
  --ipv4-address <INTERNAL-IP>

# UI subdomain  
az network private-dns record-set a add-record \
  --resource-group <your-resource-group> \
  --zone-name trustid.int.app \
  --record-set-name ui.issuernode \
  --ipv4-address <INTERNAL-IP>
```

## 4. Test Access

From a VM or machine within your VNet:

```bash
# Test DNS resolution
nslookup api.issuernode.internal.trustid.life
nslookup ui.issuernode.internal.trustid.life

# Test HTTPS access
curl -k https://api.issuernode.internal.trustid.life/status
curl -k https://ui.issuernode.internal.trustid.life
```

## 5. Add Certificate to Trust Store (Optional)

For production use, you may want to add the self-signed certificate to your organization's trust store to avoid certificate warnings.

The certificate can be extracted from the Kubernetes secret:

```bash
kubectl get secret issuer-tls-cert -n trustid-issuer -o jsonpath='{.data.tls\.crt}' | base64 -d > issuer-cert.crt
```