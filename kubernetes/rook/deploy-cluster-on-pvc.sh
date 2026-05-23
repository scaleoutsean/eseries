#!/bin/bash
set -eo pipefail

ROOK_DIR="rook_repo/deploy/examples"
# Allow overriding the storage class, defaults to "standard" if not provided
STORAGE_CLASS=${STORAGE_CLASS:-"standard"}

echo "============================================================"
echo "Deploying Rook-Ceph on PVCs"
echo "Target StorageClass: ${STORAGE_CLASS}"
echo "Warning: Configuring for single-node lab deployment."
echo "============================================================"

# Ensure namespace exists
kubectl create namespace rook-ceph 2>/dev/null || true

echo "[1/4] Applying CRDs and common definitions..."
kubectl apply -f "${ROOK_DIR}/crds.yaml"
kubectl apply -f "${ROOK_DIR}/common.yaml"

# Apply CSI operator if it exists in the repo version
if [[ -f "${ROOK_DIR}/csi-operator.yaml" ]]; then
    kubectl apply -f "${ROOK_DIR}/csi-operator.yaml"
fi

echo "[2/4] Patching and applying operator..."
# Disable CSIAddons which defaults to true in recent Rook charts
# but fails if the csiaddons.openshift.io CRD is missing
OP_TMP=$(mktemp)
cp "${ROOK_DIR}/operator.yaml" "${OP_TMP}"
sed -i "s/deployCsiAddons: true/deployCsiAddons: false/g" "${OP_TMP}"
kubectl apply -f "${OP_TMP}"
rm -f "${OP_TMP}"

echo "[3/4] Waiting for rook-ceph-operator to be ready..."
kubectl -n rook-ceph wait --for=condition=ready pod -l app=rook-ceph-operator --timeout=300s

echo "[4/4] Preparing and applying cluster-on-pvc.yaml..."
# Copy the original file to manipulate it for a local single-node cluster
TEMP_YAML=$(mktemp)
cp "${ROOK_DIR}/cluster-on-pvc.yaml" "${TEMP_YAML}"

# Patch the file:
# 1. Change the default AWS storageclass 'gp2-csi' to the intended one
# 2. Allow mons, mgrs, and osds to run on a single node (allowMultiplePerNode: true)
# 3. Relax topologySpreadConstraints for osd-prepare pods (to avoid Pending states on single-node)
sed -i "s/storageClassName: gp2-csi/storageClassName: ${STORAGE_CLASS}/g" "$TEMP_YAML"
sed -i "s/allowMultiplePerNode: false/allowMultiplePerNode: true/g" "$TEMP_YAML"
sed -i "s|topologyKey: topology.kubernetes.io/zone|topologyKey: kubernetes.io/hostname|g" "$TEMP_YAML"
sed -i "s/whenUnsatisfiable: DoNotSchedule/whenUnsatisfiable: ScheduleAnyway/g" "$TEMP_YAML"

echo "Applying patched cluster-on-pvc configuration..."
kubectl apply -R -f "${TEMP_YAML}"
rm -f "${TEMP_YAML}"

echo "============================================================"
echo "Deployment initiated! It may take 4-5 minutes. Check progress with:"
echo "  kubectl -n rook-ceph get pods -w"
echo ""
echo "If osd-prepare pods stay Pending, verify your StorageClass exists:"
echo "  kubectl get storageclass"
echo "  kubectl -n rook-ceph get pvc"
echo "============================================================"
