#!/bin/bash

echo "=== Setting up HTTPS Internal Access for Issuer Node ==="

# Remove existing nginx ingress if it exists
echo "[1/5] Removing existing ingress (if any)..."
helm uninstall nginx -n trustid-issuer 2>/dev/null || true
helm uninstall issuer-ingress -n trustid-issuer 2>/dev/null || true

# Wait a moment for cleanup
sleep 5

# Create TLS certificate
echo "[2/5] Creating TLS certificate..."
./create-tls-cert.sh

# Install nginx ingress with internal load balancer
echo "[3/5] Installing nginx ingress..."
./ingress-deploy.sh

# Wait for ingress controller to be ready
echo "[4/5] Waiting for ingress controller to be ready..."
kubectl wait --namespace trustid-issuer \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

# Get the internal IP
echo "[5/5] Getting ingress internal IP..."
kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer

echo ""
echo "=== Setup Complete! ==="
echo ""
echo "Next steps:"
echo "1. Get the EXTERNAL-IP from the service above"
echo "2. Set up Azure Private DNS with these records:"
echo "   - A record: api.issuernode.trustid.int.app -> <EXTERNAL-IP>"
echo "   - A record: ui.issuernode.trustid.int.app -> <EXTERNAL-IP>"
echo ""
echo "3. Access your application at:"
echo "   - API: https://api.issuernode.trustid.int.app"
echo "   - UI:  https://ui.issuernode.trustid.int.app"
echo ""