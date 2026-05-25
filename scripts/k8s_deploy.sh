#!/usr/bin/env bash
# scripts/k8s_deploy.sh
# One-command Kubernetes deployment.
# Usage: ./scripts/k8s_deploy.sh <image-tag>

set -euo pipefail

TAG="${1:-latest}"
NAMESPACE="${NAMESPACE:-default}"

echo "🚀 Deploying fampay services (tag: ${TAG}) to namespace ${NAMESPACE}"

# Apply network policies first
kubectl apply -f k8s/network-policy.yaml -n "${NAMESPACE}"

# Deploy hodor
kubectl apply -f k8s/hodor/configmap.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/hodor/deployment.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/hodor/service.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/hodor/hpa.yaml -n "${NAMESPACE}"
kubectl apply -f k8s/hodor/pdb.yaml -n "${NAMESPACE}"

# Update hodor image tag
kubectl set image deployment/hodor hodor=fampay/hodor:"${TAG}" -n "${NAMESPACE}"

# Deploy bran
kubectl apply -f k8s/bran/bran-all.yaml -n "${NAMESPACE}"
kubectl set image deployment/bran bran=fampay/bran:"${TAG}" -n "${NAMESPACE}"

# Apply ingress
kubectl apply -f k8s/nginx/ingress.yaml -n "${NAMESPACE}"

# Wait for rollout
echo "⏳ Waiting for rollout..."
kubectl rollout status deployment/hodor -n "${NAMESPACE}" --timeout=5m
kubectl rollout status deployment/bran -n "${NAMESPACE}" --timeout=5m

echo ""
echo "✅ Deployment complete!"
kubectl get pods -n "${NAMESPACE}" -l 'app in (hodor,bran)'
