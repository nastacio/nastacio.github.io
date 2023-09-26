---
title: Pod Disruption Budgets and Single-Instance Stateful Applications
excerpt: Identifying budget allocations that require administrative intervention
category:
  - technote
tags:
  - technology
  - kubernetes
  - cloud
  - availability
toc: false
classes: wide
---

Kubernetes allows application developers to set up [disruption budgets](https://kubernetes.io/docs/tasks/run-application/configure-pdb/) for application workloads, represented with the "PodDisruptionBudget" (PDB) custom resource.

A disruption budget can indicate the minimum number of available instances for an application or the maximum number of replicas that can be down simultaneously.

Some single-instance stateful applications may have a disruption budget with a minimum availability of one pod. While that may be a conscious design decision, the cluster cannot terminate the application pod in situations like [draining a node](https://kubernetes.io/docs/tasks/administer-cluster/safely-drain-node/) during a cluster upgrade.

That also means cluster administrators must be directly involved in handling each PDB, deleting the PDB at the beginning of the maintenance window and recreating it at the end.

Unless such an arrangement is necessary, it can pose a disproportionate burden on the system administrator performing the maintenance, especially in the presence of multiple PDBs in effect. Manual procedures may be even more cumbersome if the PDBs are managed by [operator-based](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/) software, which may recreate a deleted PDB before the cluster has a chance to stop the matching pod.

If you are preparing for maintenance windows where cluster nodes need to be restarted, it is best to be prepared and aware of strict PDBs in the cluster. You can locate all those PDBs in the cluster using the following command while logged in as a cluster administrator:

```sh
kubectl get poddisruptionbudgets \
    --all-namespaces \
    -o jsonpath="{range .items[?(@.spec.minAvailable==@.status.expectedPods)]}{.metadata.namespace}/{.metadata.name}{'\n'}{end}"
```

Example output:

```txt
ns1/pod-abc
ns1/pod-def
ns2/pod-postgresql-primary
ns2/pod-edb-primary
```
