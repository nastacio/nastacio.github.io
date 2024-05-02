---
title: Merging Cluster Contents Into Argo CD Applications
excerpt: When Git is not the only source of truth
category:
 - technote
tags:
 - argocd
 - gitops
toc: false
classes: wide
---

## Context

In a perfect GitOps world, the desired state for a corner of the system is contained in the Git repository.

In the real world, some aspects of the system are not designed to be represented as declarative state.

For example, from a situation we handled this week, suppose you have two resources in a Git repository: "A" and "B."

The spec for resource "B" indicates that one of its fields has to match the value of another field in resource "A." However, that field in "A" is assigned dynamically by a controller only after "A" has been created.

In other words, there is no way to put that field in the Git repository containing resources "A" and "B," which makes it seemingly impossible to use GitOps for deploying "B."

## The Resource

Let's assume the definition of these two resources in the repository:

```yml
apiVersion: mygroup
kind: A
metadata:
  name: aname
spec:
  # myfield: value set by cluster after deployment
```

```yml
apiVersion: mygroup
kind: B
metadata:
  name: bname
spec:
  # myfield: must be identical to "myfield" in "aname"
```

At this point in the problem, the resource tree looks like this:

```txt
config
├── appsets
│   └── appset-tools.yaml
└── tool-1
    └── templates
        ├── a.yaml
        └── b.yaml
```

Luckily, the resource type "B" is a CRD managed by a Kubernetes operator, which allows us to explore the technique in this tech note: patch the resource with a [resource hook](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/).

## Step 1: Tell ArgoCD to Ignore the Field

That patched field in "B" is not in the git repository, so our first step is instructing the Argo CD `Application` to ignore that field. Otherwise, Argo CD will reverse the change and undo the patch.

```yml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: sretools-observability
spec:
  ...
  template:
    ...
    spec:
      ...
      ignoreDifferences:
        - jsonPointers:
            - /spec/myfield
          group: mygroup
          kind: B
```

## Step 2: Match the Waves Between Resource and Sync Hook

The patch must happen after the resource is created, but we cannot use a PostSync hook or a higher wave in a Sync hook. Although that seems counterintuitive, there is a subtle aspect here: the lack of the patched field in "B" may prevent the resource from ever becoming ready, blocking argo from progressing the synchronization operation to the point where those higher waves, or a post synchronization hook, are ever reached.

For that reason, we need to ensure both the resource and the resource hook containing the patch code are in the same [phase and wave of the ArgoCD synchronization process](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-waves/).

In concrete Argo terms, we need to use the same value of `argocd.argoproj.io/sync-wave` for the resource and the resource hook.

```yml
apiVersion: mygroup
kind: B
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "200"
  name: bname
spec:
  # myfield: value unknown before deployment
```

Note that the synchronization phase has to be `Sync`, so that the hook is launched in parallel with the resource being applied:

```yml
---
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/sync-wave: "200"
  name: sync-value
spec:
...
```

Resource A has to be synchronized in an earlier wave so that the source value of the field is available when the synchronization hook runs. Leaving out the `sync-wave` effectively means wave "0", so there is no need to change "A."

## Step 3: Address the Race Condition in the Synchronization Hook

With resource B and the synchronization hook starting in parallel, we must handle a racing condition in Argo CD where the synchronization hook code may be executed before B is created.

In other words, the synchronization hook has to sit in a while loop, checking for the resource's presence before attempting to patch it.

```yml
---
apiVersion: batch/v1
kind: Job
metadata:
  annotations:
    argocd.argoproj.io/hook: Sync
    argocd.argoproj.io/sync-wave: "200"
  name: sync-value
spec:
  template:
    spec:
      containers:
        - name: config

          # This is a Kubernetes image with the CLI for my distro, but
          # you can use a more generic image, such as https://hub.docker.com/r/bitnami/kubectl/
          image: registry.redhat.io/openshift4/ose-cli:latest

          imagePullPolicy: IfNotPresent
          command:
            - /bin/sh
            - -c
            - |
              set -eo pipefail
              set -x

              result=0
              
              myfieldvalue=$(kubectl get A aname -jsonpath '{.spec.myfield}') \
              || result=1

              if [ ${result} -eq 1 ]; then
                  echo "ERROR: Unable to determine the field value."
                  exit 1
              fi

              while [ $SECONDS -lt 600 ]
              do
                  echo "INFO: Waiting for B."
                  if kubectl get B bname 2> /dev/null; then
                      break
                  fi
                  sleep 10
              done

              echo "INFO: Patching B." \
              && kubectl patch B bname \
                  --patch "{\"spec\":{\"myfield\": $myfieldvalue}}" \
                  --type merge \
              && echo "INFO: Resource patched successfully." \
              || result=1

              if [ ${result} -eq 1 ]; then
                  echo "ERROR: Unable to patch B."
              fi

              exit ${result}
      restartPolicy: Never
      serviceAccountName: sretool-install-service-account
```

## Step 4: Grant Permissions to the Service Account Behind the Synchronization Hook

Notice the `serviceAccountName` field in the resource hook. That service account needs permission to read resource "A" and patch resource "B" as follows:

```yml
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sretool-install-service-account
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: sretool-install-sa-role
rules:
  - apiGroups: ["mygroup"]
    resources: ["a"]
    verbs: ["get"]
  - apiGroups: ["mygroup"]
    resources: ["b"]
    verbs: ["get", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sretool-install-sa-binding
roleRef:
  name: sretool-install-sa-role
  apiGroup: rbac.authorization.k8s.io
  kind: Role
subjects:
  - kind: ServiceAccount
    name: sretool-install-service-account
```

## The Modified Resource Tree

With all these resources created in their respective resource file and adding a name prefix to reflect the synchronization wave for each resource, the Git repository has the following structure:

```txt
config
├── appsets
│   └── appset-tools.yaml
└── tool-1
    └── templates
        ├── 0000-role-binding.yaml
        ├── 0000-role.yaml
        ├── 0000-service-account.yaml
        ├── 0000-a.yaml
        ├── 0200-b.yaml
        └── 0200-sync-b.yaml
```

## Conclusion

Ideally, vendors should design their software installation with [GitOps principles](https://opengitops.dev/) in mind - I wish resource "B" had not been designed that way. In reality, some procedural aspects are always left here and there, requiring adaptation to GitOps principles.

This technique is valuable for bridging gaps with the least deviation from a declarative approach, moving the workarounds to well-defined locations within the Git repository.
