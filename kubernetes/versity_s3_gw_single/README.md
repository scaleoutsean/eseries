# Single-Node Versity S3 Gateway (VGW) Deployment

This directory provides everything you need to stand up a single-host Versity S3 Gateway for testing on an existing Kubernetes cluster. It is configured to use POSIX backend storage on a `ReadWriteOnce` Local/Persistent Volume Claim.

You have two options for deployment: **Standalone Monolithic YAML** or **Helm**. You can just choose whichever you prefer, as they achieve the exact same configuration.

## 1. Quick Start: Monolithic YAML

This approach requires no Helm installation and allows absolute control.
1. Optionally edit `versitygw.yaml` to specify your `storageClassName` and storage sizes.
2. Apply the manifest:
   ```bash
   kubectl apply -f versitygw.yaml
   ```

## 2. Quick Start: Helm Deployment

This approach leverages the upstream Versity Helm Chart.
1. Optionally edit `helm-values.yaml` to change credentials, storage classes, or sizes.
2. Run the deployment script:
   ```bash
   ./deploy-helm.sh
   ```

---

## 3. Creating Buckets

Both deployment methods provide the S3 gateway on port `7070` as `ClusterIP` with the default root credentials `admin` and `password`.

### Using the Bucket Creation Script

You can run `create-buckets.sh` to initialize your buckets (`backup`, `velero`, `ai`). Use port-forwarding locally to reach the cluster first:

1. Forward traffic from your local machine to the Versity GW service:
   ```bash
   kubectl port-forward -n versitygw svc/versitygw 7070:7070
   ```

2. In a separate terminal, run the script:
   ```bash
   ./create-buckets.sh
   # It requires the 'aws' CLI to be installed on your system.
   ```
   
If you need an Ingress or TLS (e.g. for Velero), you can eventually either configure a reverse proxy via NGINX Gateway Fabric routing to port 7070, or update the `helm-values.yaml` later to natively enable `tls.enabled=true` with a TLS cert secret.

## 4. CSI driver

You can pick a non-HA driver (e.g. TopoLVM), an HA driver ([SANtricity CSI](https://scaleoutsean.github.io/2026/01/19/netapp-eseries-santricity-csi.html), [IBM Block CSI with SANtricity Patch](https://scaleoutsean.github.io/2026/04/16/ibm-block-storage-csi-driver-santricity-1-13-1.html)), or something else (e.g. BeeGFS CSI if you need a scale-out Versity S3 Gateway service).

An overview of main CSI driver choices for E-Series can be found [here](https://scaleoutsean.github.io/2026/01/20/kubernetes-netapp-eseries-santricity-csi.html).

