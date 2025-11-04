#!/bin/bash

echo "=== Creating test pod for internal testing ==="

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create test pod
kubectl apply -f "$SCRIPT_DIR/test-pod.yaml"

# Wait for pod to be ready
echo "Waiting for test pod to be ready..."
kubectl wait --for=condition=ready pod/test-client -n trustid-issuer --timeout=60s

# Get the internal IP of the load balancer
INTERNAL_IP=$(kubectl get svc issuer-ingress-ingress-nginx-controller -n trustid-issuer -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Internal Load Balancer IP: $INTERNAL_IP"

# Check if it's actually internal (should be in private range)
if [[ $INTERNAL_IP =~ ^10\.|^172\.(1[6-9]|2[0-9]|3[0-1])\.|^192\.168\. ]]; then
    echo "✅ CONFIRMED: Load balancer is INTERNAL (private IP range)"
else
    echo "❌ WARNING: Load balancer appears to be EXTERNAL (public IP)"
fi

echo ""
echo "=== Testing from inside the cluster ==="

# Test API endpoint with Host header
echo "Testing API endpoint..."
kubectl exec -n trustid-issuer test-client -- curl -k -v \
    -H "Host: api-issuer.internal.trustid.life" \
    https://$INTERNAL_IP/status

echo ""
echo "Testing UI endpoint..."
kubectl exec -n trustid-issuer test-client -- curl -k -I \
    -H "Host: ui-issuer.internal.trustid.life" \
    https://$INTERNAL_IP/

echo ""
echo "=== Certificate Information ==="
echo "The TLS certificate is automatically attached via the ingress-rules.yaml"
echo "Certificate secret: internal-wildcard-tls (Let's Encrypt, valid for *.internal.trustid.life)"

echo ""
echo "=== Testing without Host header (should fail/redirect) ==="
kubectl exec -n trustid-issuer test-client -- curl -k -I https://$INTERNAL_IP/

echo ""
echo "=== Cleanup ==="
echo "To remove test pod: kubectl delete pod test-client -n trustid-issuer"