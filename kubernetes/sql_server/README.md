# Microsoft SQL Server for Linux (StatefulSet approach) on Kubernetes

- Load-balancer if you need convenient external connectivity (I had MetalLB in place)
- Create namespace `sales` - this follows Microsoft's example (or otherwise edit the manifest)
- Edit the manifest to specify storage class to use
- Secret (see in deploy.yaml) is `NetApp123$`; change it if you want

Basically, as long as you're using a test cluster where that namespace is available:

```sh
kubectl get sc # get your storage class
kubectl create ns sales
kubectl apply -f deploy.yaml
```

There's more [here](https://scaleoutsean.github.io/2026/05/29/microsoft-sql-server-kubernetes-netapp-eseries.html).

