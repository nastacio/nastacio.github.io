---
title: Using ODF object buckets as OADP backup storage locations
excerpt: A useful backup solution for airgapped environments
category:
  - technote
tags:
  - openshift
  - storage
  - backup
  - odf
  - oadp
toc: false
classes: wide
---

## Context

This technote covers the configuration of an OADP backup destination using an object bucket in [OpenShift Data Foundation](https://www.redhat.com/en/technologies/cloud-computing/openshift-data-foundation).

[OpenShift API for Data Protection](https://docs.openshift.com/container-platform/4.15/backup_and_restore/application_backup_and_restore/oadp-intro.html) is a downstream project of [Velero](https://velero.io) and is a disaster recovery layer covering OpenShift Container Platform applications, cluster resources, persistent volumes, and internal images.

The instructions in OADP documentation for [configuration with ODF](https://docs.openshift.com/container-platform/4.15/backup_and_restore/application_backup_and_restore/installing/installing-oadp-ocs.html) are good, but do not entirely cover the exact linkage between the OADP `BackupStorageLocation` and an ODF `ObjectBucket`.

## Steps

### Create the ODF Object Bucket

Create a new object bucket by creating a new ODF [ObjectBucketClaim](https://access.redhat.com/documentation/en-us/red_hat_openshift_data_foundation/4.14/html/managing_hybrid_and_multicloud_resources/object-bucket-claim#dynamic-object-bucket-claim_rhodf).

```sh
cat <<EOF | oc apply -f -
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucketClaim
metadata:
  name: oadp-object-bucket
  namespace: openshift-adp
spec:
  generateBucketName: oadp-object-bucket
  objectBucketName: obc-openshift-adp-oadp-object-bucket
  storageClassName: ocs-storagecluster-ceph-rgw
EOF

oc wait ObjectBucketClaim oadp-object-bucket \
    -n openshift-adp \
    --for=jsonpath='{.status.phase}'=Bound
```

![Screenshot of the ODF ObjectBucketClaim](/assets/images/technote-oadp-odf/odf-bucket.png)

ODF then creates the actual `ObjectBucket` instance AND the corresponding `Secret` for the bucket with the AWS-like credentials to access the bucket:

```yaml
apiVersion: objectbucket.io/v1alpha1
kind: ObjectBucket
metadata:
...
  name: obc-openshift-adp-oadp-object-bucket
spec:
  ...
  endpoint:
    bucketHost: rook-ceph-rgw-ocs-storagecluster-cephobjectstore.openshift-storage.svc
    bucketName: oadp-object-bucket-51cc2dd6-937b-4521-a6e9-160eb19a6a44
    bucketPort: 443
    region: ''
    subRegion: ''
  storageClassName: ocs-storagecluster-ceph-rgw
status:
  phase: Bound
```

Secret:

```yaml
kind: Secret
apiVersion: v1
metadata:
  name: oadp-object-bucket
  namespace: openshift-adp
  labels:
    bucket-provisioner: openshift-storage.ceph.rook.io-bucket
data:
  AWS_ACCESS_KEY_ID: ...
  AWS_SECRET_ACCESS_KEY: ...
type: Opaque
```

![Screenshot of the ObjectBucketClaim being bound](/assets/images/technote-oadp-odf/obc-bound.png)

### Create the cloud-credentials

The `Secret` for `BackupStorageLocation` has a slightly different format than the `Secret` created by `ObjectBucketClaim`, so we need to make that transformation.

The original secret data created by ODF looks like this:

```txt
AWS_ACCESS_KEY_ID: ...
AWS_SECRET_ACCESS_KEY: ...
```

But OADP expects the secret data to be formatted like this:

```txt
[default]
aws_access_key_id=...
aws_secret_access_key=...
```

The following commands make that transformation:

```sh
oc create secret generic cloud-credentials \
    --namespace openshift-adp \
    --from-literal=cloud="$(cat << EOF
[default]
aws_access_key_id=$(oc get secret oadp-object-bucket --template="{% raw %}{{index .data.AWS_ACCESS_KEY_ID | base64decode}}{% endraw %}")
aws_secret_access_key=$(oc get secret oadp-object-bucket --template="{% raw %}{{index .data.AWS_SECRET_ACCESS_KEY | base64decode}}{% endraw %}")
EOF
)" \
    --dry-run=client \
    -o yaml \
| oc apply -f -
```

### Create the Data Protection Application

Configure the OADP `DataProtectionApplication` with those values (see them under `.spec.backupLocations.velero.config`):

```sh
s3_host=$(oc get ObjectBucket obc-openshift-adp-oadp-object-bucket \
    -n openshift-adp \
    -o jsonpath={.spec.endpoint.bucketHost})
s3_port=$(oc get ObjectBucket obc-openshift-adp-oadp-object-bucket \
    -n openshift-adp \
    -o jsonpath={.spec.endpoint.bucketPort})
s3_bucket=$(oc get ObjectBucket obc-openshift-adp-oadp-object-bucket \
    -n openshift-adp \
    -o jsonpath={.spec.endpoint.bucketName})

cat <<EOF | oc apply -f -
apiVersion: oadp.openshift.io/v1alpha1
kind: DataProtectionApplication
metadata:
  name: velero
  namespace: openshift-adp
spec:
  backupLocations:
    - velero:
        config:
          insecureSkipTLSVerify: 'true'
          profile: default
          region: local
          s3ForcePathStyle: 'true'
          s3Url: https://${s3_host:?}:${s3_port:?}
        credential:
          key: cloud
          name: cloud-credentials
        default: true
        objectStorage:
          bucket: ${s3_bucket}
          prefix: velero
        provider: aws
  configuration:
    nodeAgent:
      enable: true
      uploaderType: restic
    velero:
      defaultPlugins:
        - openshift
        - aws
        - kubevirt
EOF
```

![Screenshot of the OADP instances in the cluster](/assets/images/technote-oadp-odf/oadp-instances.png)

## Validation

Create a new OADP `Backup` object:

```sh
cat <<EOF | oc apply -f -
apiVersion: velero.io/v1
kind: Backup
metadata:
  name: backup-test
  namespace: openshift-adp
spec:
  csiSnapshotTimeout: 10m0s
  defaultVolumesToFsBackup: true
  defaultVolumesToRestic: true
  includedNamespaces:
    - default
  itemOperationTimeout: 4h0m0s
  snapshotMoveData: false
  storageLocation: velero-1
  ttl: 720h0m0s
EOF
```

Wait for it to be completed:

```sh
oc wait Backup backup-test \
    -n openshift-adp \
    --for=jsonpath='{.status.phase}'=Completed
```

If successful, delete the backup. OADP will automatically delete the `DeleteBackupRequest` CR once the original `Backup` object is deleted.

```sh
cat <<EOF | oc apply -f -
apiVersion: velero.io/v1
kind: DeleteBackupRequest
metadata:
  name: deletebackuprequest
  namespace: openshift-adp
spec:
  backupName: backup
EOF
```

If all commands execute successfully, your OADP configuration will work correctly and send backup contents to the object bucket in the ODF Storage Cluster.
