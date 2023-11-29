---
title: Propagating Secrets to Managed Clusters With RHACM
excerpt: Using secret managers is good, but who propagates the master key?
category:
  - technote
tags:
  - kubernetes
  - gitops
  - openshift
  - rhacm
toc: false
classes: wide
---

As a user of [Red Hat Advanced Cluster Management](https://www.redhat.com/en/technologies/management/advanced-cluster-management) (RHACM,) I appreciate how it can prime newly created OpenShift or Kubernetes clusters with standard configuration.

This technote explores the role of RHACM policies in pushing secret store master keys to select clusters in a hybrid setup.

Note that for environments using a single IaaS, something at the IaaS layer is a more secure option, such as [Secrets Manager in IBM Cloud](https://cloud.ibm.com/docs/containers?topic=containers-secrets-mgr) and the [Kubernetes Secrets Store CSI Driver in AWS EKS](https://docs.aws.amazon.com/secretsmanager/latest/userguide/integrating_csi_driver.html).

## OpenShift GitOps

As long as the Argo instance is deployed at the cluster scope (the default out-of-the-box configuration when installing the OpenShift GitOps operator,) any cluster configuration can be placed on a Git repository and synchronized into the cluster.

The OpenShift documentation has a [good primer on using an Argo CD instance to manage cluster-scoped resources](https://access.redhat.com/documentation/en-us/red_hat_openshift_gitops/1.10/html/declarative_cluster_configuration/configuring-an-openshift-cluster-by-deploying-an-application-with-cluster-configurations#doc-wrapper).

There is one limitation when it comes to priming the cluster with secrets since [using sealed secrets in a GitOps repo is a questionable concept](https://medium.com/better-programming/why-you-should-avoid-sealed-secrets-in-your-gitops-deployment-e50131d360dd). I like the idea of using something like the [External Secrets operator](https://external-secrets.io/latest/). However, one still needs to set the master key for its secret store. That is where using a RHACM policy can help.

## RHACM Policies

[Governance](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/governance/index) is a central feature in RHACM.

In oversimplified terms, a policy describes what a system administrator wants (or doesn't want) to have in a cluster.

There are [different types of policies](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/governance/index#configuration-policy-sample-table), such as requiring that all pods in a namespace have memory requests or that all clusters have an nginx pod running on port 80 in its default namespace.

For the specific purpose of this technote, I wrote a Policy to copy over a master key from a Secret in the hub cluster to a Secret in a managed cluster.

This policy creates a new secret using the [copySecretData template function](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html-single/governance/index#copysecretdata-function). It creates the secret named `main-secret` in the namespace `cloud-keys` of the managed cluster, using as source the values stored in a secret called `secret-store-key` in the `cloud-keys` namespace of the hub cluster.

```yml
---
apiVersion: policy.open-cluster-management.io/v1
kind: Policy
metadata:
  name: secret-store-key
  namespace: cloud-keys
  annotations:
    policy.open-cluster-management.io/categories: CM Configuration Management
    policy.open-cluster-management.io/controls: CM-2 Baseline Configuration
    policy.open-cluster-management.io/standards: NIST SP 800-53
spec:
  disabled: false
  policy-templates:
    - objectDefinition:
        apiVersion: policy.open-cluster-management.io/v1
        kind: ConfigurationPolicy
        metadata:
          name: policy-entkey
        spec:
          object-templates:
            - complianceType: musthave
              objectDefinition:
                apiVersion: v1
{% raw %}                data:  '{{ "{{hub copySecretData \"cloud-keys\" \"secret-store-key\" hub}}" }}'{% endraw %}
                kind: Secret
                metadata:
                  name: main-secret
                  namespace: cloud-keys
                type: Opaque
          remediationAction: inform
          severity: low
  remediationAction: enforce
```

## Honorable Mention: Ansible Automation Platform

Using Ansible playbooks suits shops already invested in [Ansible Automation Platform](https://www.redhat.com/en/technologies/management/ansible).

One can manage all their Ansible Playbooks from a central location, then [run those automations on managed clusters](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8/html/clusters/cluster_mce_overview#ansible-config-cluster).

For shops without prior investment in Ansible, OpenShift GitOps and RHACM policies require less setup and are better aligned with Kubernetes extension APIs.
