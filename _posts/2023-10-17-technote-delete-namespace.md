---
title: Delete Kubernetes Namespaces in Terminating Status
excerpt: A Last-Resort Approach to Removing Stubborn Namespaces
category:
  - technote
tags:
  - kubernetes
  - administration
  - resources
toc: false
classes: wide
---

## The Problem

Sometimes, a deleted Kubernetes namespace does not go away, staying in the cluster indefinitely with the `status.phase` field set to "Terminating."

You try and list events in the namespace with `kubectl get events --namespace ...` and nothing indicates any activity that might explain the hold-up.

Then you list the `status` field and see messages indicating that the namespace termination is waiting on a couple of [resource finalizers](https://kubernetes.io/docs/concepts/overview/working-with-objects/finalizers/) to complete, except that they never complete.

## The (Probable) Cause

Most of the time, this happens when the user attempts to delete the namespace without first deleting all resources in the namespace. In fairness, it may be tough to be certain one has deleted every resource in a namespace.

In that situation, Kubernetes attempts to delete everything in the namespace without following any particular order.

The lack of order in those deletions means it is possible for the component responsible for processing a resource finalizer to be deleted before the resource. Once the cluster gets to those resources and invokes their finalizer, there is nothing to process the request, and the whole process gets permanently stuck.

## The (Last-Resort) Workaround

Ideally, it would be best to try reinstalling the missing component responsible for processing the finalizer. However, that can be virtually impossible because the cluster will reject the request, indicating that the namespace is being deleted.

Assuming you have tried everything and your next stage of despair is to delete the whole cluster, you can use this workaround as a _last resort_, considering it may cause resource leaks in the infrastructure.

The following shell block sequentially iterates through all resources in a target namespace. It forcefully empties the `metadata.finalizers` block, allowing the cluster to delete the resource without waiting on anything else.

Once all resources holding up the namespace are gone, then the namespace will disappear from the cluster:

```sh
ns=#namespace to be deleted
while read -r resource_type
do
    echo "${resource_type}"
    while read -r resource
    do
        if [ -z "${resource}" ]; then
            continue
        fi
        echo "Deleting ${resource}"
        kubectl patch "${resource}" -n "${ns}" \
            --type=merge \
            --patch '{"metadata":{"finalizers":[]}}'
    done <<< "$(kubectl get "${resource_type}" -n "${ns}" -o name  | sort)"
done <<< "$(kubectl api-resources --namespaced=true -o name | sort)"
```

Note that iterating through all API resources in a cluster may take a long time, which may be wasteful when we consider only a handful of resources may be causing the problem.

As an optional step to speed up the deletion process, you may look at the `status` field of the namespace for messages indicating the specific resource types causing the problem, then filter for those resources in that last line of the code snippet, like this:

> done \<\<\< "$(kubectl api-resources \-\-namespaced=true -o name \| **_grep resourcetype_** \| sort)"
