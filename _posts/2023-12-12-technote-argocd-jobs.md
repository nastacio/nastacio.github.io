---
title: Ensuring Execution of ArgoCD Resource Hooks Responsible for Configuration Changes
excerpt: Not all ArgoCD resource hooks can wait until the next synchronization cycle
category:
  - technote
tags:
  - gitops
  - argocd
  - jobs
toc: false
classes: wide
---

## Context

[ArgoCD](https://argo-cd.readthedocs.io/en/stable/) has comprehensive mechanisms to orchestrate the synchronization of a Git repository toward a cluster, namely [synchronization phases and waves](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/).

The phases are divided into "before," "during," and "after" synchronization. One can write [resource hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/) associated with one of those three phases. All resource hooks associated with a phase must be executed and completed before the next phase can start.

In case there are multiple resource hooks for the same phase, one can further annotate the hooks with a synchronization wave and customize them with [synchronization options](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/).

Combine all these features, and this is how one can add a resource hook to a Git repository to execute the container "config" before the synchronization phase of that Git repo.

```yml
---
apiVersion: batch/v1
kind: Job
metadata:
  name: my-hook
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/sync-wave: "50"
  namespace: my-namespace
spec:
  template:
    spec:
      containers:
        - name: config
          image: my-image
          env:
            - name: STORAGE_CLASS_OVERRIDE_RWO
              value: {% raw %}{{ .Values.storageclass.rwo.override }}{% endraw %}
            - name: STORAGE_CLASS_OVERRIDE_RWX
              value: {% raw %}{{ .Values.storageclass.rwx.override }}{% endraw %}
```

## Resource Hooks Can't Drift. Drift Something Else

ArgoCD does not monitor Job definitions for configuration drift because Jobs are not configuration state.

If a resource hook's sole function is to bookend the main synchronization phase, it may be expected that they only run if the repository resources drift from the current cluster state.

However, suppose a resource hook is meant to apply configuration changes to the cluster, and those changes are parameters in an `Application`. In that case, we want the resource hook to run once something (or someone) alters those parameters.

The problem in the previous example of a resource hook is that a change to those two values in the `value` fields would not be considered a configuration drift unless they were mentioned elsewhere in the repository. If they are not, the workaround is to create another resource in the repository referencing those values.

A dummy `ConfigMap` containing the configuration values is the obvious workaround:

```yml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: gitops-dummy
  namespace: my-namespace
data:
  storage_class_override_rwo: {% raw %}{{ .Values.storageclass.rwo.override }}{% endraw %}
  storage_class_override_rwx: {% raw %}{{ .Values.storageclass.rwx.override }}{% endraw %}
```

With this new resource added to the Git repository path under the same `Application`, future changes to the `Application` parameters will be detected by ArgoCD as a configuration drift, ensuring the resource hook is eventually executed.

```sh
argocd app set my-app \
         --helm-set-string storageclass.rwo.override= "myfs-block" \
         --helm-set-string storageclass.rwx.override= "myfs-file"
```
