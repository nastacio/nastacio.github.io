# Using Let's Encrypt certificates on managed clusters with OpenShift Hive

<!-- TOC -->

- [Using Let's Encrypt certificates on managed clusters with OpenShift Hive](#using-lets-encrypt-certificates-on-managed-clusters-with-openshift-hive)
  - [Overview](#overview)
  - [Signed API endpoint certificates](#signed-api-endpoint-certificates)
  - [Signing the API endpoint](#signing-the-api-endpoint)
  - [Updating Hive's configuration](#updating-hives-configuration)
  - [Conclusion](#conclusion)

<!-- /TOC -->

---

## Overview

[OpenShift Hive](https://github.com/openshift/hive/) is a Kubernetes cluster management platform for provisioning and configuring Kubernetes clusters at scale.

As a management platform, it can create new OpenShift clusters across all major Cloud providers and perform limited management operations on clusters it creates, such as hibernating clusters that are temporarily not in use.

![Diagram with OpenShift Hive on the left and three OpenShift managed clusters on the right. The OpenShift Hive cluster has an outgoing arrow connecting to each cluster on the right, and the arrow is labeled "Kubernetes API."](images/hive-ocp-api.svg "OpenShift Hive creates and manages Kubernetes clusters.")

**Note:** I use OpenShift Hive through [Red Hat Advanced Cluster Management for Kubernetes](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.6). I tried to generalize the writing and instructions so that they work when running OpenShift Hive in isolation, but have not validated the instructions using that environment.

---

## Signed API endpoint certificates

In a production environment, cluster clients need to trust that they are connecting to the actual API endpoint for the cluster and not to a system impersonating the cluster.

The straightforward way of enforcing that requirement is to sign the OpenShift API endpoint with a certificate authority that clients equally trust.

The challenge for using trusted certificates on managed clusters is two-fold:

1. Currently, OpenShift Hive does not expose APIs to sign (or apply signed) certificates for managed clusters
1. OpenShift Hibe is also a client to the managed clusters it creates, as it continuously interacts with the clusters to assess their health and perform management functions (such as the hibernation task mentioned earlier.)

Once you sign the API endpoint for the managed cluster, OpenShift Hive reports internal errors about not trusting that cluster's API endpoint, preventing it from managing the cluster.

![Diagram with OpenShift Hive on the left and three OpenShift managed clusters on the right. The OpenShift Hive cluster has an outgoing arrow connecting to each cluster on the right, and the arrow is labeled "Kubernetes API." The last cluster has the symbol of a key next to it, and the arrow connecting the OpenShift Hive cluster to that cluster has question marks next to it.](images/hive-ocp-api-signed.svg "OpenShift Hive cannot initially trust certificates added to existing managed clusters.")

The solution (credit to [Andrew Butcher](https://github.com/abutcher)) is to inform OpenShift Hive about the signing authority for the managed cluster, which can take place in two different ways:

1. If the signing authority is shared across all (or many clusters,) modify the CA (certificate authority) database for all clusters in the Hive configuration.
1. Modify the CA database for the individual managed cluster.

This article explores that second approach since there is no guarantee that a single [Let's Encrypt](https://letsencrypt.org/) intermediary signer is the same across multiple clusters. If you want to explore that configuration for other purposes (for example, if your organization owns the signing certificate,) then you must use the [`set-additional-ca.sh` script](https://github.com/openshift/hive/blob/master/hack/set-additional-ca.sh) to _replace_ the current CA database (if any) with a new one.

---

## Signing the API endpoint

The first step is to acquire the certificate using one of the various [ACME clients](https://letsencrypt.org/docs/client-options/).

For this article, I have a self-managed OpenShift cluster created in an AWS account so that we can use the ACME shell script client.

The following snippet assumes you have the [AWS CLI credentials in place](https://docs.aws.amazon.com/cli/latest/userguide/cli-chap-configure.html).

**Note**: The examples use Shell scripting and rely on the `:?` construct often to ensure that variables next to that symbol are actually defined. For example, `echo ${a:?}` fails if the variable named `a` is not defined or empty.

```sh
# Assuming AWS CLI logged in with an id authorized to interact 
# with AWS's Route 53 service

cluster_domain=# type the name of the cluster domain here, such as mycluster.mylabdomain.com

cluster_api=$(oc get Infrastructure cluster -o jsonpath='{.status.apiServerURL}')

# These two lines remove the preceding "https://" and 
# the ":port_nnumber" suffix from the URL
cluster_api="${cluster_api//*:\/\//}"
cluster_api="${cluster_api//\:*/}"

cert_dir=/tmp/certificates
mkdir -p "${cert_dir}"

git clone https://github.com/acmesh-official/acme.sh.git -b 3.0.0 --depth 1
cd acme.sh

# Note that the technique below was chosen for the simplicity of the example
# since the purpose of this tutorial is to explain how to interact 
# with the resulting cluster. It connects directly to AWS Route 53 
# with the provided credentials, so you should study the CLI 
# documentation for more secure alternatives.
./acme.sh \
    --issue \
    -d "*.apps.${cluster_domain:?}" \
    -d "api.${cluster_domain}" \
    --server letsencrypt \
    --dns dns_aws \
    --force

./acme.sh \
    --install-cert \
    -d "*.apps.${cluster_domain}" \
    -d "api.${cluster_domain}" \
    --cert-file ${cert_dir}/cert.pem \
    --key-file ${cert_dir}/key.pem \
    --fullchain-file ${cert_dir}/fullchain.pem \
    --ca-file ${cert_dir}/ca.cer
```

At this point, we have the following files:

| Certificate | File |
| ----------- | ---- |
| Server certificate | ${cert_dir}/cert.pem |
| Key for the server certificate | ${cert_dir}/key.pem |
| Full chain for the certificate authority | ${cert_dir}/fullchain.pem |
| Signing certificate for the server certificate (this is the most important file in the subsequent sections)) | ${cert_dir}/ca.cer |

Now execute the [OpenShift instructions to apply the new certificate to the managed cluster](https://docs.openshift.com/container-platform/4.11/security/certificates/api-server.html). You should be logged in as a cluster administrator in the managed cluster.

```sh
# https://docs.openshift.com/container-platform/4.11/security/certificates/api-server.html

oc delete secret api-certs \
    --ignore-not-found=true \
    -n openshift-config

oc create secret tls api-certs \
    --cert="${cert_dir}/fullchain.pem" \
    --key="${cert_dir}/key.pem" \
    -n openshift-config

oc patch apiserver cluster \
      --type merge \
      --patch="{\"spec\": {\"servingCerts\": {\"namedCertificates\": [ { \"names\": [  \"${cluster_api:?}\"  ], \"servingCertificate\": {\"name\": \"api-certs\" }}]}}}" 

```

The cluster may take several minutes to reconfigure internal resources before all master nodes respond with the new certificate.

You can wait for the complete availability of the API endpoints with the following command:

```sh
oc wait ClusterOperator kube-apiserver \
    --for=condition=Progressing=False \
    --timeout=1200s
oc wait ClusterOperator kube-apiserver \
    --for=condition=Available=True \
    --timeout=1200s
```

At this point, Hive will likely start complaining about the new API certificate. You can confirm that by running the following command against the cluster running Hive:

```sh
# Assumes you are logged in to the cluster running Hive as an 
# administrator

managed_cluster_name=#type the managed cluster name here

oc describe ClusterDeployment "${managed_cluster_name:?}" \
    --namespace "${managed_cluster_name}"
```

The output can be somewhat verbose, but you may see the following fragment somewhere in that output:

```txt
    ...
    Last Probe Time:          ...
    Last Transition Time:     ...
    Message:                  Get "https://api.mycluster.mylab.com:6443/api?timeout=32s": x509: certificate signed by unknown authority
    Reason:                   ErrorConnectingToCluster
    Status:                   True
    Type:                     Unreachable
    ...
```

---

## Updating Hive's configuration

With the certificate signer in hand, it is time to update Hive's configuration for that cluster.

Conceptually, we want to locate the [kubeconfig](https://kubernetes.io/docs/concepts/configuration/organize-cluster-access-kubeconfig/) file for the managed cluster and update the list of trusted certificate authorities with the signing certificate from the previous section.

![Box representing the cluster running OpenShift Hive. The cluster contains another box representing the namespace corresponding to the cluster (labeled "cluster-a"). Inside the namespace are two resources: the ClusterDeployment resource for cluster A and the "kubeconfig" secret referenced in that ClusterDeployment resource. An arrow connects an icon outside the cluster box, representing the addition of the new signing certificate to the CA database stored in the secret.](images/hive-ocp-certs.svg)

The first step is to identify the Kubernetes secret containing the `kubeconfig` file using the following commands:

```sh
managed_cluster_name=#type the managed cluster name here

oc get ClusterDeployment "${managed_cluster_name:?}" \
    --namespace "${managed_cluster_name}"

secret_name=$(oc get ClusterDeployment "${managed_cluster_name}" \
        --namespace "${managed_cluster_name}" \
        -o jsonpath='{.spec.clusterMetadata.adminKubeconfigSecretRef.name}')

echo ${secret_name:?}
```

With the secret name in hand, it is time to dump the `kubeconfig` contents into a local file so we can modify it and then update it. One could edit the downloaded content for this section with a text editor, but you can use the scripted approach described below.

Note that since the file contents use the YAML format, the snippet below relies on the [yq](https://mikefarah.gitbook.io/yq/) utility:

```sh
WORKDIR=/tmp/hive-ca
mkdir -p "${WORKDIR}"

kubeconfig_yaml="${WORKDIR}/${managed_cluster_name}-kubeconfig.yaml"
ca_crt="${WORKDIR}/${managed_cluster_name}.crt"

oc extract secret/"${secret_name:?}" \
    --namespace "${managed_cluster_name:?}" \
    --keys=kubeconfig --to=- > "${kubeconfig_yaml:?}"

yq -r .clusters[].cluster.certificate-authority-data "${kubeconfig_yaml}" \
    | base64 -d > "${ca_crt}"

# Shows original CA certs for the managed cluster API server
cat "${ca_crt}"
```

At this point, the original API certificates are stored in the file designated by the `ca_crt` variable.

The next step is to generate a new CA file with the recent signing certificate. Note that one could argue in favor of outright replacing the contents of the `kubeconfig` CA data, but since there is no documentation about their contents, it is safer to combine the contents rather than risk finding out some of the contents were helpful for other reasons.

```sh
# This is the CA file for the signing certificate for the cluster-a
additional_ca_file=${cert_dir}/ca.cer

# Merges the existing CA with the new CA
ca_new_crt_bundle="${WORKDIR}/${managed_cluster_name}-new.crt"
cat "${ca_crt}" "${additional_ca_file}" \
    | openssl base64 -A > "${ca_new_crt_bundle}"

# Generates a new kubeconfig file
ca_new_crt=$(cat "${ca_new_crt_bundle}")

yq -i "del (.clusters[0].cluster.certificate-authority-data)" "${kubeconfig_yaml}"

yq -i ".clusters[0].cluster.certificate-authority-data = \"${ca_new_crt}\"" "${kubeconfig_yaml}"
```

After the previous block, we have an updated version of `kubeconfig` for the cluster stored in the file location designated by the `kubeconfig_yaml` variable, containing the new signing certificate. The next step is to update the original `Secret` resource with that new configuration.

Note that there are **2** fields in the secret requiring updates:

1. `kubeconfig`
1. `raw-kubeconfig`

```sh
kubeconfig_64_yaml="${WORKDIR}/${managed_cluster_name}-kubeconfig-64.yaml"
openssl base64 -A -in "${kubeconfig_yaml}" > "${kubeconfig_64_yaml}"
kubeconfig_64=$(cat "${kubeconfig_64_yaml}")

oc patch Secret "${secret_name}" \
      --namespace "${managed_cluster_name}" \
      --type='json' -p="[{'op': 'replace', 'path': '/data/kubeconfig', 'value': '${kubeconfig_64:?}'},{'op': 'replace', 'path': '/data/raw-kubeconfig', 'value': '${kubeconfig_64:?}'}]"

# It is a good idea to wait for the ClusterDeployment resource
# to report being ready before proceeding
oc wait ClusterDeployment "${managed_cluster_name}" \
    --namespace "${managed_cluster_name}" \
    --for=condition=Ready=true \
    --timeout=600s 
```

Assuming everything was executed successfully, OpenShift Hive should now recognize the new certificate for the managed cluster.

You can validate that Hive can connect to the cluster again by running the same `oc describe` command from earlier:

```sh
oc describe ClusterDeployment "${managed_cluster_name}" \
    --namespace "${managed_cluster_name}"
```

The command 

```txt
    ...
    Last Probe Time:          2022-12-06T15:27:31Z
    Last Transition Time:     2022-12-06T15:27:31Z
    Message:                  cluster is reachable
    Reason:                   ClusterReachable
    Status:                   False
    Type:                     Unreachable
    ...
```

---

## Conclusion

OpenShift Hive does a great job creating new clusters in supported Cloud providers. Still, it currently lacks primitives for certain management operations, such as adding a signed certificate to the API endpoints of the managed clusters.

This article shows how to locate and update the `kubeconfig` for the managed cluster, using a concrete example and code samples to effect the change.
