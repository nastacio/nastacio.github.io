---
title: Argo CD Synchronization Strategies Versus Kubernetes Merge Strategies
excerpt: The Default Argo CD Synchronization Strategy Is Still the Best, but It  May Blindside You
category:
 - technote
tags:
 - argocd
 - gitops
 - devops
 - technology
toc: false
classes: wide
---

## Context

We have a GitOps repository that deploys the [Grafana Helm chart](https://github.com/grafana/helm-charts) and a few data sources introduced as secrets via [sidecar datasources](https://github.com/grafana/helm-charts/blob/main/charts/grafana/README.md#sidecar-for-datasources).

The structure of the secrets requires a string value key to contain the data source definition. That key name has no special significance as long as it is matched in the sidecar pod.

For example, here is a snippet exemplifying one of such secrets:

```yml
apiVersion: v1
kind: Secret
metadata:
  name: grafana-datasource
  labels:
    grafana_datasource: 'true'
stringData:
  # The name of this key can be anything
  object.yaml: |-
    apiVersion: 1
    datasources:
    - name: My datasource
  ...
```

## Kubectl Apply versus Key Maps

We use Argo CD as our GitOps framework, which uses the equivalent of the "[kubectl apply](https://kubernetes.io/docs/reference/kubectl/generated/kubectl_apply/)" command unless instructed otherwise.

You can override that default behavior, instructing Argo CD to [replace resources instead of applying them](https://argo-cd.readthedocs.io/en/stable/user-guide/sync-options/#replace-resource-instead-of-applying-changes).

In one particular update to the repository, after making multiple changes to the Secret, including the URL of the data source, we decided to replace the key name inside the data source secret - for reasons outside the context of this entry - so the new resource  **in the repository** looked like this:

```yml
# Desired resource contents, pre-Argo CD sync
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-datasource
  labels:
    grafana_datasource: 'true'
stringData:
  # We changed the key name from "object.yaml" to "prometheus.yaml"
  prometheus.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus datasource
  ...
```

We initiated the synchronization, and Argo CD completed it successfully, with no resources indicated as out-of-sync. In other words, the Secret had a nice green checkmark next to it.

![Argo CD reporting the secret being synchronized successfully](/assets/images/technote-argocd-apply-replace/argocd-sync.png)

However, Grafana still presented the old data source URL in the UI, which posed a bit of a mystery and triggered a round of troubleshooting and investigation.

Later, we learned that we still needed to restart the Grafana pods and clear out a couple of persistent volumes, but what intrigued us while troubleshooting the issue is that the live secret **in the cluster** now had the _two_ keys, old and new:

```yml
# Live resource in the cluster, post Argo CD sync
---
apiVersion: v1
kind: Secret
metadata:
  name: grafana-datasource
  labels:
    grafana_datasource: 'true'
stringData:
  # Old secret data key, no longer in the Git repository
  object.yaml: |-
    apiVersion: 1
    datasources:
    - name: My datasource
  ...
  # New secret data key. The only one in the Git repository
  prometheus.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus datasource
  ...
```

As mentioned earlier, Argo CD was perfectly happy to show the resource as synchronized.

The mystery ended once we went back to Kubernetes documentation to understand the [Kubernetes algorithm for processing "kubectl apply" requests](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/).

In essence, "kubectl apply" merges the input resource (the new Secret in this example) with the live resource (the Secret already created in the cluster), using [different strategies for different types of fields](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#how-different-types-of-fields-are-merged).

> - _primitive_: A field of type string, integer, or boolean. For example, image and replicas are primitive fields. **Action**: Replace.
>
> - _map_, also called object: A field of type map or a complex type that contains subfields. For example, labels, annotations, spec and metadata are all maps. **Action**: Merge elements or subfields.
>
> - _list_: A field containing a list of items that can be either primitive types or maps. For example, containers, ports, and args are lists. **Action**: Varies.

Since we changed a field name on a map, the expected behavior is "Merge" rather than "Replace."

Mystery solved.

## Different Content, No Drift?

I mentioned earlier that Argo CD synchronization was completed successfully and showed a green check "Synced" icon next to the resource.

It turns out that Argo CD did a great job considering the Kubernetes specification for "kubectl apply," even though the literal content of the Secret in the live system was not the same as the content of the Secret in the git repository.

![Screenshot of Argo CD UI showing two seemingly different versions of a resource as being synced](/assets/images/technote-argocd-apply-replace/main.png)

In other words, Argo CD only cared that the Secret `data` map had a key with the desired name ("prometheus.yaml") and ignored the extraneous key ("object.yaml").

Well done, Argo CD.

## The Solution

Our use case called for that Secret in the cluster to be identical to the one in the Git repository, so we annotated the resource, instructing Argo CD to replace the resource (equivalent to invoking "kubectl replace") instead of using the default "kubectl apply" behavior:

```yml
# New resource contents in the Git repository
---
apiVersion: v1
kind: Secret
metadata:
  annotations:
    # Instruct Argo CD to replace the live resource
    argocd.argoproj.io/sync-options: Replace=true
  name: grafana-datasource
  labels:
    grafana_datasource: 'true'
stringData:
  prometheus.yaml: |-
    apiVersion: 1
    datasources:
    - name: Prometheus datasource
  ...
```

## "I heard you. I still don't believe you."

Renaming keys on a Kubernetes resource is not the most common of operations, so a few people dealing with this situation wanted to run a small example using the `kubectl` CLI before they were ready to believe their eyes.

If you are also skeptical or if you need some backing to explain the issue to other people without having an entire Argo CD setup on hand, here is the snippet using only the CLI:

```sh
cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: apply-merge-example
  namespace: default
stringData:
  object.yaml: |
    apiVersion: 1
EOF

cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name:  apply-merge-example
  namespace: default
stringData:
  prometheus.yaml: |
    apiVersion: 1
EOF
```

Now you can execute the following command to list the contents of the secret:

```sh
kubectl get Secret apply-merge-example -n default -o yaml
```

You will see the output with the two keys in the Secret:

```yaml
apiVersion: v1
data:
  object.yaml: ...
  prometheus.yaml: ...
kind: Secret
metadata:
  annotations:
    kubectl.kubernetes.io/last-applied-configuration: | ...
  name: apply-merge-example
  namespace: default
type: Opaque
```

## Conclusion

Ultimately, the mystery stemmed from me letting my guard down with Argo CD's great choice of default behavior for synchronization operations.

Using "Apply" strategies is the right approach for most situations. It allows you to co-manage resource contents with other sources — a [necessity in the Kubernetes ecosystem](https://kubernetes.io/docs/reference/using-api/server-side-apply/) — while also effectively producing results that are indistinguishable from the "replace" behavior—unless you are making certain types of changes to lists and maps (like the one we did).

Case in point, it was not the default "apply" behavior that caused our configuration problem. However, I can imagine different situations where an extraneous map key in a Secret or ConfigMap could cause problems, such as being processed by poorly written code that assumed the Secret had a single key or by code that used introspection of map keys to drive further actions.

I also acknowledge that the "replace" strategy poses problems in some cases. There may be cases where you don't want Argo CD to come in and delete resource contents created by other sources. So, make sure you are not adding "replace" annotations to resources potentially co-managed by different sources (or, worse, manually).

Regardless of how you configure the synchronization strategy for Argo CD, either in the entire application or in individual resources, it pays to brush up on [Kubernetes merge strategies](https://kubernetes.io/docs/tasks/manage-kubernetes-objects/declarative-config/#how-different-types-of-fields-are-merged) and carefully consider when to use the synchronization method most adequate to the use case at hand.
