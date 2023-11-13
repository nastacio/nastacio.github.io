---
title: Grant Access Non-AWS Account Users Access to an EKS Cluster
excerpt: 
category:
  - technote
tags:
  - kubernetes
  - aws
  - eks
  - access
  - iam
toc: false
classes: wide
---

Authorized AWS account users can log in to an [Amazon EKS cluster](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html) using the `aws` CLI. However, there are many situations where you need to share access to the cluster without necessarily wanting to onboard the cluster user into the AWS account.

This tech note was extracted from my [AWS EKS notes](https://github.com/nastacio/aws-eks) with commands to configure the cluster with storage and load balancing.

## AWS Account Users

For an authorized AWS account user, the `aws eks` CLI is the easiest way to access an AWS EKS cluster:

```sh
cluster_name=# Insert EKS cluster name
cluster_region=# AWS region for the cluster, such as "us-west-2"

aws eks update-kubeconfig \
    --region "${cluster_region:?}" \
    --name "${cluster_name:?}" \

kubectl get namespaces
```

Example output

```txt
NAME              STATUS   AGE
default           Active   20m
kube-node-lease   Active   20m
kube-public       Active   20m
kube-system       Active   20m
```

## Non-AWS Account Users

This process allows an AWS account user with administration privileges to the cluster to generate a new `kubeconfig` file that can be handed to a non-AWS account user.

The other user must export the KUBECONFIG variable to point to this file.

The entire process is based on an existing administrator creating the new user in the cluster and then using [Kubernetes authentication](https://kubernetes.io/docs/reference/access-authn-authz/authentication/) commands to generate a bearer token for a new service account.

```sh
user=cluster-admin
export KUBECONFIG="${HOME}/.kube/config"
aws eks update-kubeconfig \
    --region "${cluster_region:?}" \
    --name "${cluster_name:?}" \
&& kubectl get namespaces

cluster_arn=$(aws eks describe-cluster \
    --region ${cluster_region:?} \
    --name ${cluster_name:?} \
    --query 'cluster.arn' \
    --output text)
cluster_endpoint=$(aws eks describe-cluster \
    --region ${cluster_region:?} \
    --name ${cluster_name:?} \
    --query 'cluster.endpoint' \
    --output text)

kubectl get serviceaccount "${user:?}" 2> /dev/null \
|| kubectl create serviceaccount "${user}"

kubectl get clusterrolebinding "${user}-binding" 2> /dev/null \
|| kubectl create clusterrolebinding "${user}-binding" \
  --clusterrole "${user}" \
  --serviceaccount default:cluster-admin

# The duration value should be treated as a suggestion. 
# The EKS service may return a token with a shorter duration. 
kube_token=$(kubectl create token "${user}" --duration=100h)

export KUBECONFIG="${HOME}/kubeconfig-${cluster_name:?}"
rm -rf "${KUBECONFIG:?}"

kubectl config set-cluster "${cluster_arn}" \
    --server "${cluster_endpoint}" \
    --insecure-skip-tls-verify=true

kubectl config set-context "${cluster_arn}" \
    --cluster  "${cluster_arn}" \
    --user cluster-admin

kubectl config use-context "${cluster_arn}"

kubectl config set-credentials cluster-admin --token="${kube_token}"
```

Now share the file in $KUBECONFIG with the non-AWS account user. Remember that this file contains an administrative bearer token to the cluster, so handle it with the same care as sharing any other credential or password.

After making a local copy of the file, that user should be able to export their local `KUBECONFIG` environment variable to match the file's full pathname and use the `kubectl` CLI to interact with the cluster.
