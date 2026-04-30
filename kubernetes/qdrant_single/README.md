# Qdrant Single Instance CSI Testing Deployment

This is a Kubernetes recipe for deploying a single-instance [Qdrant](https://qdrant.tech/) vector database, specifically designed and optimized for testing E-Series container storage interface (CSI) drivers: volume persistence, snapshotting, and performance characterization.

It implements several distinct `PersistentVolumeClaims` representing each of the distinct paths in Qdrant (such as snapshots, audit logs, regular logs, storage). This enables verifying discrete CSI features like snapshots applying only to individual mounts or testing how operations map onto your backend.

## Architecture

- Deployment: Recreate (Ensures robust `ReadWriteOnce` volume detach/attach during rolling restarts).
- Storage: Maps out to multiple isolated PVCs, using all Qdrant storage consumers (logging, audit, etc.).
- Network: Exposes Qdrant via `NodePort` mapping `30333` (HTTP) and `30334` (gRPC) by default.
- TLS: Explicitly disabled (perfect for lab environments without complex certificate handling).

## PVC Mount Topology

The deployment binds to several directories in the Qdrant container, matching the requests:

- `/qdrant/logs` - 10Gi
- `/qdrant/snapshots` - 10Gi
- `/qdrant/snapshots_temp` - 10Gi
- `/qdrant/storage` - 50Gi
- `/qdrant/audit` - 10Gi

## Prerequisites

- Active Kubernetes cluster
- Configured [CSI implementation](https://scaleoutsean.github.io/2026/01/20/kubernetes-netapp-eseries-santricity-csi.html) for your target NetApp E-Series storage system. Examples:
  - SANtricity CSI
  - IBM Block CSI with SANtricity patch
- Ensure you have tweaked `./config/local.yaml` as needed (it will be injected into Qdrant as a ConfigMap). 

## Running the Recipe

To deploy using your default or a specific CSI Storage Class, just run:

```bash
# Uses external CSI class (e.g., 'your-csi-storage-class')
./deploy.sh <STORAGE_CLASS_NAME>
```

If no storage class is provided, it defaults to `standard`.

### Validating Persistence & CSI Features

1. Run writes into Qdrant using port `30333` (HTTP) or `30334` (gRPC). The HTTP Web UI is at `host:30333/dashboard`. See [here](https://qdrant.tech/documentation/quickstart/) on how to create a collection, populate and query it. The impatient can "stress-test" with [bulk uploads](https://qdrant.tech/documentation/tutorials-develop/bulk-upload/).

2. Kill/restart the Pod:

```sh
kubectl rollout restart deployment/qdrant -n qdrant
```

3. Test that index collections are retained.

4. Try taking a backend VolumeSnapshot (using the applicable `VolumeSnapshotClass` targeting `qdrant-pvc-snapshots` or `qdrant-pvc-storage`) to ensure CSI compatibility.

