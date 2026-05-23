# Rook on PVC with NetApp E-Series

## About

- This example uses standard Rook-on-PVC deployment backed by an E-Series-friendly CSI driver with Block mode support or even static PVC
  - IBM Block CSI with SANtricity patch 1.13.2 (supports Block mode)
  - SANtricity CSI (Block mode is currently still a TODO item, but may add support soon)
  - TopoLVM (supports Block mode)

Alternatively, static PVCs, provisioned with Ansible or Terraform Provider SANtricity, could be used as well, but that would be more involved and isn't covered by this example.

## Deploy

### One-shot deployment

For local/lab testing using a single-node cluster (and PVCs backed by NVMe-RoCE or other block storage), you can use the provided `deploy-cluster-on-pvc.sh` script. It automates applying the baseline CRDs/operators, waits for the operator to be ready, patches `allowMultiplePerNode` to `true` (so OSDs, MONs, and MGRs can schedule on 1 lab node), and sets the `StorageClass` for the PVCs dynamically.

```sh
# Set to your SANtricity/NVMe-RoCE CSI storage class (defaults to "standard")
# I use the demo SC name from IBM Block CSI with SANtricity patches (R6 on DDP)
export STORAGE_CLASS="demo-storageclass-santricity"
./deploy-cluster-on-pvc.sh
```

Install Rook Ceph tools to check with `ceph status`:

```
$ kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- bash
bash-5.1$ ceph status
  cluster:
    id:     25b673a0-c9d5-499e-bb8c-072b77bf89f2
    health: HEALTH_OK

  services:
    mon: 3 daemons, quorum a,b,c (age 2m) [leader: a]
    mgr: a(active, since 95s), standbys: b
    osd: 3 osds: 3 up (since 106s), 3 in (since 119s)

  data:
    pools:   1 pools, 1 pgs
    objects: 2 objects, 577 KiB
    usage:   82 MiB used, 30 GiB / 30 GiB avail
    pgs:     1 active+clean
```

### Manual Deployment

This is in more detail, but has not been verified as one-shot deployment worked fine for me.

Using SANtricity CSI as an exmaple:

- Use Helm to deploy SANtricity CSI and create a Storage Class
  - For a multi-tiered SSD approach (metadata, Hot Tier, etc.), create two storage classes on a DDP pool (one "ultra-fast" RAID 1-based, and another regular RAID 6-based) or even different pools (HDD, SSD)
- Use "Rook on PVC" deployment that consumes the SANtricity Storage Class(es). Block mode must be supported by SC, and Ceph will consume it automatically

```sh
kubectl create namespace rook-ceph
# clone Rook 1.19.5 to this subdirectory for local access to Rook example YAML manifests
git clone --single-branch --branch v1.19.5 https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl create -f crds.yaml -f common.yaml -f csi-operator.yaml -f operator.yaml
# https://github.com/rook/rook/blob/release-1.19/deploy/examples/cluster-on-pvc.yaml
kubectl create -f cluster-on-pvc.yaml
# Verify pods and dashboard
kubectl -n rook-ceph get service
# get credentials for the Rook dashboard (username: admin)
kubectl -n rook-ceph get secret rook-ceph-dashboard-password -o jsonpath="{['data']['password']}" | base64 --decode && echo
```

- Enable dashboard if not enabled with `kubectl create -f dashboard-external-https.yaml`
- Create CephFS with RF2, considering we use PVCs on protected storage with `kubectl create -f filesystem.yaml`:
```sh
apiVersion: ceph.rook.io/v1
kind: CephFilesystem
metadata:
  name: myfs
  namespace: rook-ceph
spec:
  metadataPool:
    replicated:
      size: 3
  dataPools:
    - name: replicated
      replicated:
        size: 2
  preserveFilesystemOnDelete: true
  metadataServer:
    activeCount: 1
    activeStandby: true
```
- Create a Ceph-backed Storage Class with `kubectl create -f deploy/examples/csi/cephfs/storageclass.yaml`:
```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: rook-cephfs
# Change "rook-ceph" provisioner prefix to match the operator namespace if needed
provisioner: rook-ceph.cephfs.csi.ceph.com
parameters:
  # clusterID is the namespace where the rook cluster is running
  # If you change this namespace, also change the namespace below where the secret namespaces are defined
  clusterID: rook-ceph

  # CephFS filesystem name into which the volume shall be created
  fsName: myfs

  # Ceph pool into which the volume shall be created
  # Required for provisionVolume: "true"
  pool: myfs-replicated

  # The secrets contain Ceph admin credentials. These are generated automatically by the operator
  # in the same namespace as the cluster.
  csi.storage.k8s.io/provisioner-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/provisioner-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-expand-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-expand-secret-namespace: rook-ceph
  csi.storage.k8s.io/controller-publish-secret-name: rook-csi-cephfs-provisioner
  csi.storage.k8s.io/controller-publish-secret-namespace: rook-ceph
  csi.storage.k8s.io/node-stage-secret-name: rook-csi-cephfs-node
  csi.storage.k8s.io/node-stage-secret-namespace: rook-ceph

reclaimPolicy: Delete
```
- Create a PVC to test the CS and Ceph (`kubectl apply -f ceph-pvc.yaml`):
```yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: base-pvc
  namespace: first-namespace
spec:
  accessModes:
    - ReadWriteMany
  resources:
    requests:
      storage: 100Gi
  storageClassName: rook-cephfs
  volumeMode: Filesystem

```
- Check the Rook documentation on how to enable the Rook toolbox module (how to start it is explained above)
```sh
ceph mgr module enable rook
ceph mgr module enable nfs
ceph orch set backend rook
# Crete CephFS-backed NFS 4.1 share
ceph nfs export create cephfs my-nfs /test myfs
# List to check
ceph nfs export ls my-nfs
```

**Note** 
- Erasure-coded Ceph on SANtricity is possible, but it requires multiple workers (see https://rook.io/docs/rook/latest-release/CRDs/Shared-Filesystem/ceph-filesystem-crd/#erasure-coded).

## Remove Rook Ceph

```sh
# uninstall operator
kubectl delte rook-ceph
```

If the PVCs are `Retain`, remove the discarded PVs as well.

```sh
kubectl get pv | grep Released
```

