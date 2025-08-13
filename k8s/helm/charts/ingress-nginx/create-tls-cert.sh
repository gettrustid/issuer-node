#!/bin/bash

echo "Creating TLS certificate for internal domains..."

# Generate self-signed certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/tls.key -out /tmp/tls.crt \
  -subj "/CN=trustid.int.app/O=TrustID Internal" \
  -addext "subjectAltName=DNS:*.trustid.int.app,DNS:trustid.int.app,DNS:api.issuernode.trustid.int.app,DNS:ui.issuernode.trustid.int.app"

echo "Certificate generated successfully!"

# Delete existing secret if it exists (ignore errors)
kubectl delete secret issuer-tls-cert -n trustid-issuer 2>/dev/null || true

# Create Kubernetes secret
kubectl create secret tls issuer-tls-cert \
  --key /tmp/tls.key --cert /tmp/tls.crt \
  -n trustid-issuer

echo "TLS secret created successfully!"

# Clean up temporary files
rm -f /tmp/tls.key /tmp/tls.crt

echo "Certificate setup completed!"