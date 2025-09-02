---
title: Accident-Proofing Argo CD Deployments
excerpt: Pressing the Wrong Button Should Not Erase Your Cloud
header:
  teaser: /assets/images/argocd-deletion/main.png
category:
 - technote
tags:
 - kubernetes
 - gitops
 - argocd
 - technology
toc: false
classes: wide
---

## GitOps Principle vs. Practice: The Cost of Accidental Deletions

This article explores the Argo CD mechanisms that help prevent accidental deletion of costly system resources.

A declarative system with a single source of truth is a core principle of any GitOps practice.

But we live in a world of cascading dependencies, inhabited by [CustomResourceDefinitions](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/), [Kubernetes Operators](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/), and IaaS abstractions such as [CrossPlane](https://www.crossplane.io/).

In that world, Kubernetes resources represent far more than entries in an [etcd database](https://kubernetes.io/docs/concepts/architecture/#etcd). They can be as complex as a [PostgreSQL instance](https://cloudnative-pg.io/), as load-bearing as an [S3 bucket](https://doc.crds.dev/github.com/crossplane/provider-aws/s3.aws.crossplane.io/Bucket/v1beta1@v0.20.2) storing terabytes of audit logs, or as foundational as a [ Kubernetes cluster](https://doc.crds.dev/github.com/crossplane/provider-aws/eks.aws.crossplane.io/Cluster/v1beta1@v0.20.2).

## Argo CD and Synchronization Policies

On top of that complex world, Argo CD introduces additional abstractions to represent the grouping of those resources:

- [Applications](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#applications) are collections of Kubernetes resources deployed to a cluster.
- [ApplicationSets](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/) represent collections of Applications.

When you combine all those layers, the accidental deletion of resources in a Git repository has the potential for triggering cascading deletions across the infrastructure, which I list below in ascending order of impact:

1. Delete a custom resource representing an IaaS resource, such as an S3 bucket? There goes the S3 bucket and all of its data.
2. Delete a [CustomResourceDefinition](https://kubernetes.io/docs/tasks/extend-kubernetes/custom-resources/custom-resource-definitions/#delete-a-customresourcedefinition)? There goes _all_ Kubernetes resources matching the definition, along with all corresponding resources in the infrastructure.
3. Delete an Argo CD Application? There goes every managed resource in that Application. If one of the resources is a CustomResourceDefinition, you can do the math with the previous item.

4. Delete an ArgoCD ApplicationSet? There goes every Application generated from the ApplicationSet.

The following sections cover the Argo CD mechanisms for preventing troubled Git merges from accidentally deprovisioning large swaths of your infrastructure.

These mechanisms range from requests for human confirmation to directives that instruct Argo CD to ignore deletion requests.

It is important to note that vendors may also offer their own protection mechanisms, such as [Kubernetes reclaim policies for persistent volumes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#reclaiming) and CrossPlane's deletion policy for "Cluster" resources.

### 1. ApplicationSet syncPolicy: Preventing Application deletions

An ApplicationSet owns the `Application` resources it [generates](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators/).

The [default policy](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Controlling-Resource-Modification/#managed-applications-modification-policies) is governed by the ApplicationSet ["syncPolicy"](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Controlling-Resource-Modification/#managed-applications-modification-policies) field. The default value for application synchronization (`sync`) adheres to the principle of a single source of truth:

1. If the ApplicationSet is deleted, all generated Applications are deleted.
2. If the generator no longer generates one of the applications it previously generated, that `Application` resource is deleted.

Something as simple as a typo in the target revision in a [Git generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Git/) may result in an empty set of matching Applications. The default Argo CD configuration may cause the deletion of all Applications generated from that ApplicationSet, which in turn triggers a cascading deletion of all resources created downstream from that ApplicationSet.

If an ApplicationSet contains Applications representing expensive resources, that may be a costly mistake, so you may want to consider customizing the `applicationsSync` parameter of such ApplicationSets

These are the options and respective explanations:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
...
spec:
  syncPolicy:
    # (default) Applications strictly reflect the output of the generator.
    # applicationsSync: sync

    # Prevents ApplicationSet controller from modifying or deleting Applications
    applicationsSync: create-only

    # Prevents ApplicationSet controller from deleting Applications. Update is allowed
    # applicationsSync: create-update

    # Prevents ApplicationSet controller from modifying Applications. Delete is allowed.
    # applicationsSync: create-delete
```

**Note**: The `applicationsSync` setting is only observed in Argo CD installations that are configured to accept policy overrides in the ApplicationSets. [See this Argo CD document page for more details](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Controlling-Resource-Modification/#managed-applications-modification-policies).

**Reference**: <https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/applicationset-specification/>

### 2. ApplicationSet preserveResourcesOnDeletion: Preventing Application resource deletions

Overriding ApplicationSet `applicationsSync` parameters may lead to confusion about which Applications are still valid.

After all, you may lose track of which Application resources are still being generated and which ones are orphaned by an `applicationSync` policy of `create-update`.

In such cases, you may prefer to have Argo CD delete the `Application` resources but use a non-cascading deletion policy for those Applications.

In other words, you can instruct the applicationset controller to remove the `Application` resource from the cluster without applying the cascading deletion to all resources managed by that `Application`.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
...
spec:
    # Prevent an Application's child resources from being deleted when the parent Application is deleted
    preserveResourcesOnDeletion: true
```

**Reference**: <https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/applicationset-specification/>

### 3. Application non-cascading deletion

An Application resource may be created directly in a cluster, without being generated by an ApplicationSet.

There are valid reasons for wanting an Application resource removed from a cluster without triggering the deletion of resources contained in the Application.

In those circumstances, you can use the `cascade=false` parameter in the command-line interface or the `Non-cascading` option when deleting the application from the Argo CD user interface.

```sh
argocd app delete APPNAME --cascade=false
```

**Reference**: <https://argo-cd.readthedocs.io/en/latest/user-guide/app_deletion/>

### 4. Application syncPolicy prune: Preventing mass pruning of resources

Total deletion of an Application, covered in the previous sections, is only one of the ways an expensive resource may be deleted. There are cases where accidental deletion originates from the deletion of an individual resource in the Git repository.

In such cases, the resources deleted from the source Git repository may be removed from the system during the next synchronization operation.

By default, the pruning policy for resources is set to `false`, which marks an unusual deviation from the principle of a single source of truth. In other words, by default, Argo CD does not delete resources from a cluster when the resource is deleted from the source Git repository.

Regardless of its default value, this pruning policy can be overridden by setting it to `true`. I wanted to highlight this as a separate section in this article to establish the context for the following sections.

```yaml
spec:
  syncPolicy:
    automated:
      ...
      prune: true       # Specifies if resources should be pruned during auto-syncing ( false by default ).
      ...
```

**Reference**: <https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/#automatic-pruning>

### 5. Resource Prune sync-option: Prevent individual pruning of resources

Assuming an Application pruning policy is set to `true`, there may be cases where you still want to prevent specific resources from being deleted from the system after they are removed from the source Git repository.

In those cases, you can use the `Prune` annotation in the resource, like this:

```yaml
apiVersion: your_resource_group
kind: your_resource_type

metadata:
  annotations:
    argocd.argoproj.io/sync-options: Prune=false|confirm
```

**Note 1**: You can also set this synchronization policy for an entire class of resources at [the server level](https://argo-cd.readthedocs.io/en/stable/user-guide/diffing/#system-level-configuration).
**Note 2**: The `confirm` option was introduced in Argo CD 2.14.

**Reference**: <https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#no-prune-resources>

### 6. Resource Delete sync-option: Prevent individual deletion of resources

The "Delete" option can add an extra layer of protection by preventing the deletion of the resource when the parent Application is deleted.

```yaml
apiVersion: your_resource_group
kind: your_resource_type

metadata:
  annotations:
    argocd.argoproj.io/sync-options: Delete=false|confirm
```

**Note**: The `confirm` option was introduced in Argo CD 2.14.

**Reference**: <https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/#no-resource-deletion>

### AppProject syncWindows: Honorable Mention

Per Argo CD documentation for [AppProject synchronization windows](https://argo-cd.readthedocs.io/en/stable/user-guide/sync_windows/):

> Sync windows are configurable windows of time where syncs will either be blocked or allowed. These are defined by a kind, which can be either allow or deny, a schedule in cron format and a duration along with one or more of either applications, namespaces and clusters.

With synchronization windows in place, system administrators can retain automated sync policies at the Application level, trusting that changes to the system due to Application changes will only happen at designated times and on designated systems.

In other words, this feature does not prevent accidental deletions, but may give system administrators additional time to examine diff changes and spot undesirable changes before the maintenance window starts.

## Summary

A healthy GitOps practice requires some thinking about which resources can be managed according to a strict principle of a single source of truth.

The more resources you can manage that way, the less manual intervention you will need to clean up orphaned resources or manage drift between Git repos and the target environments.

If your GitOps practice is based on Argo CD, you can use this article as a guide to make informed decisions on where to implement the deviations and how to implement them.

The following table summarizes the different sections, their scope, and the pros and cons of adopting each approach:

| Policy                                | Goal                                         | Trade-offs | Reference |
|--------------------------------------|----------------------------------------------|------------|-----------|
| [1. ApplicationSet syncPolicy](#1-applicationset-syncpolicy-preventing-application-deletions) | Control creation, update, and deletion of generated Applications | + Fine-grained lifecycle control; prevents costly deletions.<br>– Overrides may not be enabled; risk of misconfiguration. | [Docs: ApplicationSet spec](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/applicationset-specification/) |
| [2. ApplicationSet preserveResourcesOnDeletion](#2-applicationset-preserveresourcesondeletion-preventing-application-resource-deletions) | Prevent cascading deletion of Application-managed resources | + Avoids mass resource deletion when Applications are removed.<br>– May leave orphaned resources requiring manual cleanup. | [Docs: ApplicationSet spec](https://argo-cd.readthedocs.io/en/latest/operator-manual/applicationset/applicationset-specification/) |
| [3. Application non-cascading deletion](#3-application-non-cascading-deletion) | Prevent cascading deletion when removing an Application resource | + Safely remove Applications while retaining workloads.<br>– Risk of drift; manual cleanup needed later. | [Docs: App deletion](https://argo-cd.readthedocs.io/en/latest/user-guide/app_deletion/) |
| [4. Application syncPolicy prune](#4-application-syncpolicy-prune-preventing-mass-pruning-of-resources) | Prevent mass-pruning of resources in an Application | + Ensures Git is the single source of truth.<br>– Misuse can cause accidental deletions from Git mistakes. | [Docs: Auto-sync pruning](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/#automatic-pruning) |
| [5. Resource Prune sync-option](#5-resource-prune-sync-option-prevent-individual-pruning-of-resources) | Prevent pruning of specific resources in an Application | + Granular protection for critical resources.<br>– Adds complexity; can be overridden by authorized users. | [Docs: Sync-options prune](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#no-prune-resources) |
| [6. Resource Delete sync-option](#6-resource-delete-sync-option-prevent-individual-deletion-of-resources) | Prevent deletion of specific resources in an Application | + Strongest safeguard; fully blocks deletion.<br>– May cause drift or block intentional cleanup. | [Docs: Sync-options delete](https://argo-cd.readthedocs.io/en/latest/user-guide/sync-options/#no-resource-deletion) |
