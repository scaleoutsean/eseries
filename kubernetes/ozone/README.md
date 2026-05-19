# Apache Ozone on SANtricity CSI 

This example deploys an Apache Ozone cluster using a Storage Class from [SANtricity CSI README](https://github.com/scaleoutsean/santricity-go/blob/master/csi/README.md).

## Deploy

- It is suggested to create a dedicated namespace for evaluation and testing
- Make sure you have 50GiB of disk space and 12 GiB of RAM. Not all volumes have to be 7GiB, but some do and there's half a dozen of them

```sh
cd ./kubernetes/ozone/santricity
NAMESPACE="ozone-test" STORAGE_CLASS="santricity-iscsi-raid6" PVC_SIZE="7Gi" ./deploy.sh
```

If you do not override these variables, the script uses default namespace, default storage class and 2Gi PVCs.

For testing, you may want to create a non-default storage class like this:

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: santricity-iscsi-raid6
  annotations:
    storageclass.kubernetes.io/is-default-class: "false"
provisioner: santricity.scaleoutsean.github.io
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Delete # CHANGE TO 'Retain' FOR PRODUCTION!
allowVolumeExpansion: true
parameters:
  # E-Series specific parameters (Pool, etc.) go here
  # storagePool: "ozone_pool" 
  poolID: "" # Your DDP ID
  raidLevel: "raid6"
```

The same should work with my other CSI driver ([IBM Block CSI with SANtricity patch](https://github.com/scaleoutsean/ibm-block-csi-driver/tree/santricity/santricity)) or even TopoLVM CSI, but `provisioner` should be changed. For NVMe/RoCE, I'd recommend SANtricity CSI (SAN-style) or TopoLVM (DAS-style).

Once all services come up, OM (Ozone Manager) should be reachable on the node at http://nodeIp:32109 (this time):

```sh
$ kubectl get svc om-public -n ozone-test
NAME              TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)           AGE
om-public         NodePort    10.101.133.170   <none>        9874:32109/TCP    32m

```

You should be able to scale data nodes to desired replica count.

```sh
kubectl scale statefulsets datanode --replicas 2 -n ozone-test
```

### Delete

Because the `deploy.sh` wrapper dynamically generates the namespace and modifies the YAML on the fly inside a temporary directory, running a raw `kubectl delete -k .` locally will look in the `default` namespace and fail to find the resources.

The easiest and cleanest way to tear down the environment is to simply delete the dedicated namespace you created:

```sh
kubectl delete namespace ozone-test
```

## Why Ozone with E-Series?

- Fast block devices and the ability to create hybrid configuration let Ozone users optimize cost and price/performance by easily creating multi-tiered Ozone deployments
- Protected and reliable block devices let you create reliable RF2 and "narrow" EC schemas and save rack space by avoiding data node bloat
  - RS-6-3 requires 10 datanodes (20U with NL-SAS), but you can get the same with just 100 HDDs in 10 RAID 6 disk groups on E-Series (4U for storage and 6RU for six servers)
- Multiple DDP or classic RAID groups still allow physical storage disk pool isolation if desired
- DAS- and SAN-style deployments possible

Ozone on Kubernetes is one way to use Ozone with E-Series, but other viable approaches are available, too.

Another viable approach is bare metal servers or VMs with DAS-storage attachment using my Terraform Provider SANtricity. I [blogged about those approaches](https://scaleoutsean.github.io/2022/07/06/apache-ozone-netapp-eseries.html) so I won't repeat that here.

## License and copyright 

- Ozone deployment examples: see the Ozone project
- deploy.sh script: MIT License
