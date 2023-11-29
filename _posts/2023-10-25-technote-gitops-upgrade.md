---
title: Upgrading OpenShift GitOps from OCP 4.12 to OCP 4.13
excerpt: Big features, big deprecations
category:
  - technote
tags:
  - kubernetes
  - gitops
  - openshift
toc: false
classes: wide
---

[I started looking into OpenShift Container Platform 4.13](https://github.com/IBM/cloudpak-gitops/issues/288) and this summary of findings regarding OpenShift GitOps operator changes may interest a wider audience.

## GitOps 1.5 (stable) is gone

1. The `stable` channel for [OpenShift GitOps](https://docs.openshift.com/gitops/1.10/release_notes/gitops-release-notes.html) is [**REMOVED**](https://docs.openshift.com/gitops/1.10/release_notes/gitops-release-notes.html#GitOps-compatibility-support-matrix_gitops-release-notes) in OCP 4.13. Starting with OCP 4.13, you need to pick a specific channel  (`gitops-1.8` - `gitops-1.10` as of today) or `latest`.
1. The removed `stable` channel maps to the `gitops-1.5` version of the operator in OCP 4.12. That version is not available in OCP 4.13, so you must upgrade to a more recent version of the operator in OCP 4.13. The minimum version is `gitops-1.8` (Even though OCP 4.13 currently allows the selection of operator versions 1.6 and 1.7, the [support matrix](https://docs.openshift.com/gitops/1.10/release_notes/gitops-release-notes.html#GitOps-compatibility-support-matrix_gitops-release-notes) says 1.8 is the minimum.)

Note that the [compatibility matrix in the OCP lifecycle page](https://access.redhat.com/support/policy/updates/openshift#gitops) differs ever so slightly from the compatibility matrix in the [OpenShift GitOps docs](https://docs.openshift.com/gitops/1.10/release_notes/gitops-release-notes.html#GitOps-compatibility-support-matrix_gitops-release-notes).

For example, the OCP lifecycle page says GitOps 1.8 is incompatible with OCP 4.13, while the GitOps compatibility matrix says GitOps 1.8 works on OCP 4.13 (and it does.) In doubt, I prefer to trust the GitOps Docs.

## Deprecations for Resource Customizations in 1.7

This is the most disruptive change we are taking into account as we move from GitOps 1.5 to a more recent version:

- [OpenShift GitOps 1.7](https://docs.openshift.com/gitops/1.9/release_notes/gitops-release-notes.html#new-features-1-7-0_gitops-release-notes) [deprecates resource customizations](https://issues.redhat.com/browse/GITOPS-2890) in favor of a new format. In other words, custom health checks [like this](https://github.com/IBM/cloudpak-gitops/blob/d889f56524a73b9a0f958a00b40c8d72aea8abb0/config/argocd/templates/0200-argocd.yaml#L89C3-L89C25) should be modified to look [like this](https://issues.redhat.com/browse/GITOPS-1561). I love that change. The old custom health checks were a giant block of YAML mapped into a string, while the new format groups the checks in an array of resource types.
- OpenShift GitOps 1.8 is the earliest version **to support OCP 4.13, while still supporting OCP 4.10** (yeah, yeah, OCP 4.10 clusters are out of maintenance, but they are still out there :- ) This release is my personal recommendation for the quickest and least disruptive upgrade choice with the best chance of allowing existing ArgoCD customizations to work unmodified across OCP 4.10-4.13.
- Don't stay on GitOps 1.8 for too long because [OpenShift GitOps 1.8 will go out of support as soon as 1.11 is released](https://access.redhat.com/support/policy/updates/openshift#gitops) (in a couple of months or so.) For my team, 1.8 will be a stop-gap to get things working on OCP 4.13 ASAP, while we make the deeper changes required in 1.9 (see below.)
- [OpenShift GitOps 1.9](https://docs.openshift.com/gitops/1.9/release_notes/gitops-release-notes.html#new-features-1-9-0_gitops-release-notes) REMOVES the resource customizations deprecated in 1.7. (Another good reason to make a stop at 1.8 first and ensure your updates to the ArgoCD CR still work.)

## Deployment Topology Change in GitOps 1.10

Looking ahead, after you get your repos to work on OCP 4.12 + 4.13, there is another disruptive change in the way the operator is deployed:

- OpenShift GitOps 1.10 (the latest release as of today) changes the deployment of the operator in a big way, **with the operator going to an operator-specific namespace (`openshift-gitops-operator`)** and each instance of ArgoCD still going to their own namespace (`openshift-gitops` is still the default namespace for the default instance).
