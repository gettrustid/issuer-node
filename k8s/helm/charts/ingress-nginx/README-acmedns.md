# ACME DNS Secret Setup

## Setup Instructions

1. **Copy the sample file:**
   ```bash
   cp acmedns.json.sample acmedns.json
   ```

2. **Fill in your ACME DNS credentials** in `acmedns.json`

3. **Create the secret in cert-manager namespace:**
   ```bash
   kubectl create secret generic acmedns-credentials \
     --from-file=acmedns.json \
     --namespace=cert-manager \
     --dry-run=client -o yaml | kubectl apply -f -
   ```

## Verify

```bash
kubectl get secret acmedns-credentials -n cert-manager
kubectl describe secret acmedns-credentials -n cert-manager
```

## Notes

- `acmedns.json` is gitignored and should never be committed
- The ClusterIssuer references this secret for DNS-01 challenges
- Credentials are shared with the primary cluster's ACME DNS server
