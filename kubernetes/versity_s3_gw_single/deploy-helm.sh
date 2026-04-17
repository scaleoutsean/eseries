#!/usr/bin/env bash

# Helper script to deploy Versity GW using the upstream Helm chart and our helm-values.yaml

NAMESPACE="versitygw"
RELEASE_NAME="versitygw"
CHART_URL="oci://ghcr.io/versity/versitygw/charts/versitygw"

echo "Creating namespace $NAMESPACE..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

echo "Deploying Versity GW using Helm..."
helm upgrade --install "$RELEASE_NAME" "$CHART_URL" \
    --namespace "$NAMESPACE" \
    --values helm-values.yaml

echo "Done! The service is a ClusterIP by default, reachable inside the cluster."
