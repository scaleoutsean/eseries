#!/usr/bin/env bash

# Deploy Qdrant to Kubernetes with CSI parameterization

STORAGE_CLASS=${1:-"standard"}

echo "Using Storage Class: $STORAGE_CLASS"

# Create namespace
kubectl create namespace qdrant --dry-run=client -o yaml | kubectl apply -f -

# Create ConfigMap from local config file
echo "Creating ConfigMap from config/local.yaml..."
kubectl create configmap qdrant-config \
    --namespace qdrant \
    --from-file=local.yaml=./config/local.yaml \
    -o yaml --dry-run=client | kubectl apply -f -

# Render and apply main manifest with the chosen StorageClass
echo "Deploying Qdrant..."
sed "s/storageClassName: qdrant-sc/storageClassName: $STORAGE_CLASS/g" qdrant.yaml | kubectl apply -f -

echo "=========================================================="
echo "Qdrant deployed successfully to 'qdrant' namespace."
echo "Wait for the pod to be ready:"
echo "  kubectl get pods -n qdrant -w"
echo ""
echo "Access Qdrant (HTTP) via NodePort on port 30333."
echo "Access Qdrant (Web UI) via NodePort on port 30333 and path /dashboard."
echo "Access Qdrant (gRPC) via NodePort on port 30334."
