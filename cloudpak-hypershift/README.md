# Install Cloud Paks using hosted control planes
<!-- TOC -->

- [Install Cloud Paks using hosted control planes](#install-cloud-paks-using-hosted-control-planes)
  - [Overview](#overview)
  - [Prerequisites](#prerequisites)
  - [Account preparation](#account-preparation)
    - [Create AWS bucket](#create-aws-bucket)
    - [Create AWS user](#create-aws-user)
  - [Install RHACM](#install-rhacm)
  - [Enable HyperShift in the MultiClusterEngine](#enable-hypershift-in-the-multiclusterengine)
  - [Configure the hosting service cluster](#configure-the-hosting-service-cluster)
    - [Create a cloud provider secret](#create-a-cloud-provider-secret)
  - [Deploy a hosted cluster](#deploy-a-hosted-cluster)
  - [Deploy a Cloud Pak](#deploy-a-cloud-pak)
    - [Issues](#issues)

<!-- /TOC -->

## Overview

Hosted Control Planes is a new OpenShift feature that allows the separation of OpenShift control planes from the workloads running in OpenShift.

This feature is based on [project HyperShift](https://github.com/openshift/hypershift), aiming at hosting OpenShift control planes at scale, reducing runtime costs and time to provision.

Quoting from [Red Hat's announcement the feature recently](https://cloud.redhat.com/blog/hosted-control-planes-is-here-as-tech-preview):

> Hosted control planes for Red Hat OpenShift decouples the control plane from the data plane (workers), separates network domains, and provides a shared interface through which administrators and Site Reliability Engineers (SREs) can easily operate a fleet of clusters.

The [announcement blog](https://cloud.redhat.com/blog/hosted-control-planes-is-here-as-tech-preview) does a great job of explaining the concepts and how to get started with the technology, but here is a recap of the most relevant aspects for Cloud Paks:

<< Figure >>

- Hosted cluster. An OpenShift cluster with worker nodes only. The control plane runs remotely, in the hosting cluster. This is where we will install the Cloud Paks.
- Hosting Cluster. An OpenShift cluster running the control plane for all hosted clusters.
- Multicluster Engine. The middleware component running in the hosting cluster, responsible for managing the control planes.
- Red Hat Advanced Cluster Manager for Kubernetes. Responsible for managing both hosting cluster and hosted clusters. It may be colocated with the hosting cluster.

Note that hosted control planes is a technology preview currently only available in AWS, though it will eventually cover other Cloud providers.

## Prerequisites

- An OpenShift cluster version 4.10 or above, with RHACM installed.
- Administrative access to an AWS account

## Account preparation

### Create AWS bucket

### Create AWS user

```sh
aws iam create-user --user-name hypershift-demo && \
aws iam create-access-key --user-name hypershift-demo
```

## Install RHACM

Install RHACM following the [Red Hat documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/install/index)

For demonstration purposes, you can speed the installation of RHACM by cloning this repository and running the following commands:

```sh
git clone ...
cd cloudpak-hypershift

echo "Creates the project for the RHACM operator" && \
oc new-project open-cluster-management && \
oc apply -f templates/0100-rhacm-operator-group.yaml && \
echo "Creates the RHACM operator and waits for it to be ready" && \
oc apply -f templates/0100-rhacm-subscription.yaml && \
oc wait subscription.operators.coreos.com/advanced-cluster-management \
    --namespace open-cluster-management \
    --for=condition=CatalogSourcesUnhealthy=False && \
oc wait subscription.operators.coreos.com/advanced-cluster-management \
    --namespace open-cluster-management \
    --for=jsonpath='{.status.state}'=AtLatestKnown
```

After the previous commands return successfully, you can complete the creation of the RHACM cluster hub with the following commands (note that it may take several minutes for the cluster hub to be available):

```sh
oc apply -f templates/0150-multi-cluster-hub.yaml && \
oc wait multiclusterhub.operator.open-cluster-management.io/multiclusterhub \
    --namespace open-cluster-management \
    --for=condition=Complete=True \
    --timeout=900s
oc wait multiclusterhub.operator.open-cluster-management.io/multiclusterhub \
    --namespace open-cluster-management \
    --for=jsonpath='{.status.phase}'=Running \
    --timeout=120s
```

If you plan on attempting this installation in an actual production environment, then refer to the [formal Red Hat documentation for installing the multicluster engine operator](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/multicluster_engine/multicluster_engine_overview#mce-intro)

## Enable HyperShift in the MultiClusterEngine

The RHACM documentation covers the [configuration of the HyperShift add-on to the RHACM cluster](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/multicluster_engine/multicluster_engine_overview#hypershift-addon-intro), which consists of checking whether the resource is created and ensuring the `hypershift-preview` feature is enabled as follows:

```sh
oc get MultiClusterEngine --namespace open-cluster-management

mce=$(oc get MultiClusterEngine --namespace open-cluster-management -o name)
oc patch "${mce:?}" \
    --namespace open-cluster-management \
    --type=json \
    -p='[{"op": "add", "path": "/spec/overrides/components/-","value":{"name":"hypershift-preview","enabled":true}}]'
```

## Configure the hosting service cluster

The next step is to configure the cluster running the MultiClusterEngine operator to enable a cluster to act as a hosting cluster. You can use the same cluster running the MultiClusterEngine operator to host the control planes or you can designate a remote cluster.

For simplicity in this article, we will use the same cluster, but you can read more advanced instructions in the [RHACM documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/multicluster_engine/multicluster_engine_overview#hosting-service-cluster).

```sh
if [ ! -f ${HOME}/.aws/credentials ]; then
    mkdir -p ${HOME}/.aws
    cat << EOF > ${HOME}/.aws/credentials
[default]
aws_access_key_id = ${AWS_ACCESS_KEY_ID:?}
aws_secret_access_key = ${AWS_SECRET_ACCESS_KEY:?}
region = ${AWS_REGION:?}
EOF
    chmod 600 ${HOME}/.aws/credentials
fi

oc create secret generic hypershift-operator-oidc-provider-s3-credentials \
    --namespace local-cluster \
    --from-file=credentials=${HOME}/.aws/credentials \
    --from-literal=bucket=${BUCKET_NAME:?} \
    --from-literal=region=${AWS_REGION:?}
```

Now install the HyperShift add-on, which is responsible for installing the HyperShift operator on managed clusters.

```sh
oc apply -f templates/0200-hypershift-add-on.yaml && \
oc wait managedclusteraddons hypershift-addon \
    --namespace local-cluster \
    --for=condition=Available=True
```

### Create a cloud provider secret

The hosting service cluster needs credentials and DNS domain information to create hosted clusters, which is described in detail in the [RHACM documentation](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/multicluster_engine/multicluster_engine_overview#hosted-deploy-cluster).

You can use the instruction below if you have used the previous commands in this article. Your AWS account must own the DNS domain and you can download your Red Hat pull secret from [https://console.redhat.com/openshift/downloads#tool-pull-secret].

```sh
export DNS_DOMAIN=<Existing AWS DNS domain for the hosted clusters>
export RED_HAT_PULL_SECRET=<pull secret downloaded from https://console.redhat.com/openshift/downloads#tool-pull-secret>

oc new-project clusters && \
oc create secret generic aws-hosted-clusters \
    --namespace clusters  \
    --from-literal=baseDomain=${DNS_DOMAIN:?} \
    --from-literal=aws_access_key_id=${AWS_ACCESS_KEY_ID:?} \
    --from-literal=aws_secret_access_key=${AWS_SECRET_ACCESS_KEY:?} \
    --from-literal=pullSecret=${RED_HAT_PULL_SECRET:?}
```

## Deploy a hosted cluster

With the hosting cluster fully configured, it is time to create a hosted cluster.

The default hosted cluster configuration is optimized for small deployments, with a few small nodes with limited CPU and memory.

For Cloud Pak installation, we need to modify some of these parameters, which is documented in the [RHACM manual](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6/html/multicluster_engine/multicluster_engine_overview#hosted-deploy-cluster-customize).

The following example illustrates the customizations required to create a hosted cluster suited for the deployment of a Cloud Pak:

```yml
---
apiVersion: cluster.open-cluster-management.io/v1alpha1
kind: HypershiftDeployment
metadata:
  name: cloudpak-cluster
  namespace: clusters
spec:
  hostingCluster: local-cluster
  hostingNamespace: clusters
  hostedClusterSpec:
    networking:
      machineCIDR: 10.0.0.0/16    # Default
      networkType: OVNKubernetes
      podCIDR: 10.132.0.0/14      # Default
      serviceCIDR: 172.31.0.0/16  # Default
    platform:
      type: AWS
    pullSecret:
      name: cloudpak-cluster-pull-secret    # This secret is created by the controller
    release:
      # CUSTOMIZATION FOR CLOUD PAKS
      # The default OCP release is 4.11, which is currently not supported by Cloud Paks
      image: quay.io/openshift-release-dev/ocp-release:4.10.40-x86_64  
    services:
    - service: APIServer
      servicePublishingStrategy:
        type: LoadBalancer
    - service: OAuthServer
      servicePublishingStrategy:
        type: Route
    - service: Konnectivity
      servicePublishingStrategy:
        type: Route
    - service: Ignition
      servicePublishingStrategy:
        type: Route
    sshKey: {}
  nodePools:
  - name: cloudpak-cluster-us-east-1a
    spec:
      # autoScaling:
      #   min: 3
      #   max: 6
      clusterName: cloudpak-cluster
      management:
        autoRepair: false
        replace:
          rollingUpdate:
            maxSurge: 1
            maxUnavailable: 0
          strategy: RollingUpdate
        upgradeType: Replace
      platform:
        aws:
          # CUSTOMIZATION FOR CLOUD PAKS
          # The default instance type and root volumes need to be increased.
          instanceType: m5.4xlarge
          rootVolume:
            iops: 2000
            size: 100
            type: io1
        type: AWS
      release:
        # CUSTOMIZATION FOR CLOUD PAKS
        # The default OCP release is 4.11, which is currently not supported by Cloud Paks
        image: quay.io/openshift-release-dev/ocp-release:4.10.40-x86_64
      replicas: 6
  infrastructure:
    cloudProvider:
      name: aws-hosted-clusters
    configure: True
    platform:
      aws:
        region: us-east-1
```

Customize the `HyperShiftDeployment` resource to match your specific needs and apply it to the hosting cluster.

You can monitor the progress of the deployment with this command:

```sh
 oc wait \
    hypershiftdeployment.cluster.open-cluster-management.io cloudpak-cluster \
    --for=condition=NodePool=True \
    --namespace clusters \
    --timeout=1200s && \
oc wait \
    managedcluster.cluster.open-cluster-management.io cloudpak-cluster \
    --for=condition=HubAcceptedManagedCluster=True \
    --timeout=900s && \
oc wait \
    managedcluster.cluster.open-cluster-management.io cloudpak-cluster \
    --for=condition=ManagedClusterConditionAvailable=True \
    --timeout=900s

oc get secret  kubeadmin-password  -n cloudpak-cluster -o jsonpath={.data.password} \
| base64 -d

```

## Deploy a Cloud Pak

A HyperShift cluster exposes the same Kubernetes APIs as a regular OpenShift cluster and there is no specific adjustment required to install a Cloud Pak.

Use the regular Cloud Pak documentation to proceed.

### Issues

- HyperShift API endpoint missing SAN in certificate

  Common Services IAM operator fails to start with the following message:

  `"error":"Get \"https://kubernetes.default:443/.well-known/oauth-authorization-server\": x509: certificate is valid for localhost, kubernetes, kubernetes.default.svc, kubernetes.default.svc.cluster.local, kube-apiserver, kube-apiserver.clusters-cloudpak-cluster.svc, kube-apiserver.clusters-cloudpak-cluster.svc.cluster.local, a3a4f6cc0bfea4575a61a80cf0b9fe98-b9734199dd876d74.elb.us-east-1.amazonaws.com, api.cloudpak-cluster.hypershift.local, not kubernetes.default"`

  The entire essage is:

  `{"level":"error","ts":1668809412.032726,"logger":"controller-runtime.manager.controller.authentication-controller","msg":"Reconciler error","name":"example-authentication","namespace":"ibm-common-services","error":"Get \"https://kubernetes.default:443/.well-known/oauth-authorization-server\": x509: certificate is valid for localhost, kubernetes, kubernetes.default.svc, kubernetes.default.svc.cluster.local, kube-apiserver, kube-apiserver.clusters-cloudpak-cluster.svc, kube-apiserver.clusters-cloudpak-cluster.svc.cluster.local, a3a4f6cc0bfea4575a61a80cf0b9fe98-b9734199dd876d74.elb.us-east-1.amazonaws.com, api.cloudpak-cluster.hypershift.local, not kubernetes.default","stacktrace":"github.com/go-logr/zapr.(*zapLogger).Error\n\t/home/prow/go/pkg/mod/github.com/go-logr/zapr@v0.2.0/zapr.go:132\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).reconcileHandler\n\t/home/prow/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:297\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).processNextWorkItem\n\t/home/prow/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:248\nsigs.k8s.io/controller-runtime/pkg/internal/controller.(*Controller).Start.func1.1\n\t/home/prow/go/pkg/mod/sigs.k8s.io/controller-runtime@v0.8.0/pkg/internal/controller/controller.go:211\nk8s.io/apimachinery/pkg/util/wait.JitterUntilWithContext.func1\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:185\nk8s.io/apimachinery/pkg/util/wait.BackoffUntil.func1\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:155\nk8s.io/apimachinery/pkg/util/wait.BackoffUntil\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:156\nk8s.io/apimachinery/pkg/util/wait.JitterUntil\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:133\nk8s.io/apimachinery/pkg/util/wait.JitterUntilWithContext\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:185\nk8s.io/apimachinery/pkg/util/wait.UntilWithContext\n\t/home/prow/go/pkg/mod/k8s.io/apimachinery@v0.19.10/pkg/util/wait/wait.go:99"}`

  The Red Hat team was notified on 11/28.

