---
title: Building Applications with OCP BuildConfig
excerpt: A convenient way of creating container images for Kubernetes workloads
category:
  - technote
tags:
  - technology
  - kubernetes
  - build
  - cicd
  - openshift
toc: false
classes: wide
---

I often see [OpenShift Container Platform](https://www.redhat.com/en/technologies/cloud-computing/openshift/container-platform) described as a Kubernetes distribution.

There are significant [additions](https://www.redhat.com/en/technologies/cloud-computing/openshift/red-hat-openshift-kubernetes) in OCP relative to the open-source distribution of Kubernetes. Still, one of my favorite features is development experience, where OpenShift offers an [entire range of CI/CD technologies](https://docs.openshift.com/container-platform/4.12/cicd/index.html).

An often overlooked feature in that CI/CD toolbelt, outside staples like Jenkins, Tekton, and ArgoCD, is the proprietary `BuildConfig` custom resource.

This is my favorite shortcut whenever someone hands me a Git repo with a Dockerfile for a development driver before they get the chance to publish the container image to an accessible image registry:

```yaml
---
kind: Secret
apiVersion: v1
metadata:
  name: git-repo-secret
  namespace: development
stringData:
  username: x-oauth-basic
  password: ....
type: kubernetes.io/basic-auth

---
kind: BuildConfig
apiVersion: build.openshift.io/v1
metadata:
  name: my-docker-build
  namespace: development
spec:
  source:
    type: Git
    git:
      uri: 'https://github.com/nastacio/myrepo'
      ref: some-pr-branch
    contextDir: myapp-folder
    sourceSecret:
      name: git-repo-secret
  strategy:
    type: Docker
    dockerStrategy:
      env:
        - name: EXAMPLE
          value: sample-app
  output:
    to:
      kind: DockerImage
      name: >-
        image-registry.openshift-image-registry.svc:5000/development/my-image:latest
```

This resource tells OpenShift to:

1. Clone the `some-pr-branch` branch of the [https://github.com/nastacio/myrepo](https://github.com/nastacio/myrepo) repository.
2. Build a container image named `my-image` using the Dockerfile in the `myapp-folder` folder.
3. Push the resulting image to the internal OCP registry, allowing one to reference the image `my-image` in pods running in the `development` namespace.

You also get a lot of other free goodies, like a secure webhook URL to add to the GitHub project to trigger automatic builds, UI-based access to build progress, observability, Kubernetes metrics, and much more.

For an actual production project, I would prefer something with broader adoption and more extension points, like GitHub actions or Tekton (extended as OpenShift Pipelines in OCP.) Still, a `BuildConfig` is hard to beat for this simple localized use case.

Going beyond simple container builds, there is also the (almost magical) [`oc new-app ...`](https://docs.openshift.com/container-platform/4.12/applications/creating_applications/creating-applications-using-cli.html) CLI invocation, which creates not only the `BuildConfig` custom resource, but also a [`DeploymentConfig`](https://docs.openshift.com/container-platform/4.12/applications/deployments/what-deployments-are.html) resource that deploys an application referencing the resulting image.

Once it all comes together, it is hard to go back to juggling `docker build ...` and `docker push ...` again.
