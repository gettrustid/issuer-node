
#!/bin/bash

echo "[1/3] Updating"
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

echo "[2/3] Installing Ingress"
helm install issuer-ingress ingress-nginx/ingress-nginx \
    --namespace trustid-issuer \
    --set controller.ingressClassResource.name="network-nginx" \
    --set controller.ingressClassResource.controllerValue="k8s.io/network-ingress-nginx" \
    --set controller.replicaCount=1 \
    --set controller.nodeSelector."kubernetes\.io/os"=linux \
    --set defaultBackend.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.admissionWebhooks.patch.nodeSelector."kubernetes\.io/os"=linux \
    --set controller.service.externalTrafficPolicy=Local \
    --set controller.allowSnippetAnnotations=true \
    --set controller.config.annotations-risk-level=Critical 

echo "[3/3] Applying Route Rules"
kubectl apply -f ./ingress-rules.yml

echo "Completed Ingress Setup"