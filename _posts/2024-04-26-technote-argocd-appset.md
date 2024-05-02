---
title: Mapping 3 data sources to ApplicationSet Matrix Generators in ArgoCD
excerpt: Because sometimes only 2 data sources are not enough
category:
 - technote
tags:
 - argocd
 - gitops
toc: false
classes: wide
---

## Context

We have a set of observability tools that we need to be deployed to a fleet of Kubernetes clusters.

That set includes tools such as Grafana, Prometheus, [Instana](https://www.ibm.com/products/instana), and [Turbonomic](https://www.ibm.com/products/turbonomic).

We have multiple service providers to be monitored by those tools, each deployed to their individual Kubernetes namespace.

As a matter of topology within the cluster, we deploy the observability stack to each namespace. I know, _"Why not deploy a global stack for the entire cluster and leverage a multi-tenancy schema?"_. Regulations and separation of duties, but that is beside the point of the technote.

As such, we have three data sources for the deployment:

1. Target cluster for the deployments
2. Service Provider to run in each cluster
3. Observability stack for each service provider

| ![Component and deployment diagram for using an Argo CD ApplicationSet to create all permutations of Applications over 3 different data sources](/assets/images/technote-argocd-appset/main.svg) |
|:--:|
| Permutations of Applications for each combination of observability stack and service provider being monitored. |

While ArgoCD can use a [matrix generator](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-Matrix/) to create permutations of data sources, matrix generators only allow two data sources.

There are multiple ways of creating three or more levels of permutations. Still, this one worked well for us, at the expense of a single workaround that remains very visible in an `ApplicationSet`.

## The matrix generator

This entry is not a primer on matrix generators. Still, in simple terms, it works as a 2x2 matrix where one dimension comes from a fixed source, and the other can also come from a fixed source OR be dynamically generated.

This technote uses the combination of a fixed source and a dynamic source:
1. A [Git Generator](https://argocd-applicationset.readthedocs.io/en/stable/Generators-Git/) that locates all "cluster-config.yaml" files under a path in a Git repository.
2. A list iterator for an array of elements found in a "cluster-config.yaml" file.

The structure for each cluster-config.yaml file:

```yml
region: ...
cluster:
  id: my-first-dev-cluster
  url: https://api.myserver.com:6443
labels:
  cloud: ...
  environment: dev

# The source list for the list iterator in the matrix generator
sretools:
  - sretool: turbonomic-myfirstproduct
  - sretool: turbonomic-mysecondproduct
  ...
```

### Issue 16578

[Issue 16578](https://github.com/argoproj/argo-cd/issues/16578) is critical here because it touches upon a workaround multiple ArgoCD users have had in trying to use [dynamically generated elements](https://argo-cd.readthedocs.io/en/stable/operator-manual/applicationset/Generators-List/#dynamically-generated-elements) following the ArgoCD manual.

As of today, trying to use this `list` element in an ApplicationSet is rejected by Kubernetes due to the `list` missing the `elements` entry.

One of the users in that GitHub thread found a clever workaround in placing an empty `elements` array under `list` and only then, defining the `elementsYaml` item like this:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: sretools-observability
spec:
  goTemplate: true
  goTemplateOptions:
    - missingkey=error
  generators:
    - matrix:
        generators:
          - git:
              files:
                - path: >-
                    resources/configurations/my-dev/**/cluster-config.yaml
              repoURL: 'https://github.com/myorg/myrepo'
              revision: main
          - list:
              # https://github.com/argoproj/argo-cd/issues/16578
              elements: []
              elementsYaml: "{% raw %}{{ .sretools | toJson }}{% endraw %}"
```

That arrangement will iterate over each `cluster-config.yaml` file found in the repo and, for each cluster, iterate over the list of elements in the `sretools` array in the file.

**IMPORTANT**: As [I noted in the issue](https://github.com/argoproj/argo-cd/issues/16578#issuecomment-2080923271), and at least as of ArgoCD v2.10.2, you must have the source list for the list iterator **as a top element** in the cluster-config.yaml. If you put the list under another element in the YAML file, the `ApplicationSet` will report that it cannot find the list.

## Two dimensions in one

Algebra and all, if you have three dimensions and can only express them in two dimensions, you must project two of them onto a single dimension.

In this entry, I chose to map the observability tool and product provider dimensions in the `sretools`, as you probably already noticed from the cluster-config.yaml sample earlier in the tech note:

```yml
sretools:
  - sretool: <tool 1>-<serviceprovider 1>
  - sretool: <tool 1>-<serviceprovider 2>
  - sretool: <tool 1>-<serviceprovider 3>
  ...
  - sretool: <tool 1>-<serviceprovider N>
  ...
  - sretool: <tool 2>-<serviceprovider 1>
  - sretool: <tool 2>-<serviceprovider 2>
  - sretool: <tool 2>-<serviceprovider 3>
  ...
  - sretool: <tool 2>-<serviceprovider N>
```

### Breaking up list elements inside the ApplicationSet

So we need to deal with these strings containing the two dimensions by splitting them inside the `ApplicationSet`. Fortunately, using the `split` Helm function is a simple matter.

For example, the snippet below will split the `sretool` variable using the `-` character as a separator, then return the first element of the split. The YAML example below maps to the observability tool.

`{% raw %}{{ (split "-" .sretool)._0 }}{% endraw %}`

It follows that the snippet below returns the service provider:

`{% raw %}{{ (split "-" .sretool)._1 }}{% endraw %}`

Putting all this together, we can reuse those snippets wherever we need the name of the observability tool or the product names:

```yml
  template:
    metadata:
      labels:
        cloud: '{% raw %}{{ .labels.cloud }}{% endraw %}'
        environment: '{% raw %}{{ .labels.environment }}{% endraw %}'
        region: '{% raw %}{{ .region }}{% endraw %}'
        sretool: '{% raw %}{{ (split "-" .sretool)._0 }}{% endraw %}'
      name: 'sretool-{% raw %}{{ (split "-" .sretool)._0 }}{% endraw %}-{% raw %}{{ (split "-" .sretool)._1 }}{% endraw %}-{% raw %}{{ .cluster.id }}{% endraw %}'
    spec:
      destination:
        namespace: 'sretools-{% raw %}{{ (split "-" .sretool)._1 }}{% endraw %}'
        server: '.cluster.url'
      project: sretools-project
      source:
        ...
```

## Conclusion

With the entire `ApplicationSet` put together with these adjustments and techniques, you should end up with a new `Application` for each permutation of clusters, observability tools, and service providers found under that `resources/configurations/my-dev` folder in the Git repository.
