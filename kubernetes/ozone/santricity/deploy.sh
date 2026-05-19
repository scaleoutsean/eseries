#!/usr/bin/env bash
set -e

NAMESPACE=${NAMESPACE:-""}
STORAGE_CLASS=${STORAGE_CLASS:-""}
PVC_SIZE=${PVC_SIZE:-"2Gi"}
OZONE_IMAGE=${OZONE_IMAGE:-"apache/ozone:2.1.0"}

echo "Deploying Ozone..."
if [ -n "$NAMESPACE" ]; then echo "Namespace: $NAMESPACE"; else echo "Namespace: default"; fi
echo "Ozone Image: $OZONE_IMAGE"
echo "Storage Class: ${STORAGE_CLASS:-default}"
echo "PVC Size: $PVC_SIZE"

TMP_DIR=$(mktemp -d)
cp -r ./* "$TMP_DIR/"

SC_YAML=""
if [ -n "$STORAGE_CLASS" ]; then SC_YAML="storageClassName: $STORAGE_CLASS"; fi

if [ -n "$NAMESPACE" ]; then
cat <<B > "$TMP_DIR/namespace.yaml"
apiVersion: v1
kind: Namespace
metadata:
  name: $NAMESPACE
B
  echo "namespace: $NAMESPACE" >> "$TMP_DIR/kustomization.yaml"
  if ! grep -q "^resources:" "$TMP_DIR/kustomization.yaml"; then echo "resources:" >> "$TMP_DIR/kustomization.yaml"; fi
  sed -i '/^resources:/a \- namespace.yaml' "$TMP_DIR/kustomization.yaml"
fi

# Replace placeholder image directly
sed -i "s|'@docker.image@'|$OZONE_IMAGE|g" "$TMP_DIR"/*.yaml

cat <<B >> "$TMP_DIR/kustomization.yaml"

patches:
  - target:
      kind: StatefulSet
    patch: |-
      apiVersion: apps/v1
      kind: StatefulSet
      metadata:
        name: .*
      spec:
        template:
          spec:
            volumes:
              - \$patch: delete
                name: data
        volumeClaimTemplates:
          - metadata:
              name: data
            spec:
              accessModes: [ "ReadWriteOnce" ]
              $SC_YAML
              resources:
                requests:
                  storage: $PVC_SIZE
B

kubectl apply -k "$TMP_DIR"
sleep 5
echo "Waiting for all PVCs to be bound..."

if [ -n "$NAMESPACE" ]; then
  kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc -l app=ozone,component=datanode -n "$NAMESPACE" --timeout=30s || { echo "Warning: PVCs took longer than 30s to bind. Ensure your backend storage and CSI driver are functioning properly."; }
else
  kubectl wait --for=jsonpath='{.status.phase}'=Bound pvc -l app=ozone,component=datanode --timeout=30s || { echo "Warning: PVCs took longer than 30s to bind. Ensure your backend storage and CSI driver are functioning properly."; }
fi

rm -rf "$TMP_DIR"
echo "Ozone deployment applied successfully!"
