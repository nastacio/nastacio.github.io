---
title: Using gp3 Root Volumes for OpenShift Nodes on AWS
excerpt: Avoid paying for expensive IOPS capacity reservation you may not need
category:
  - technote
tags:
  - aws
  - openshift
  - storage
  - iops
toc: false
classes: wide
---

This technical note is a write-up of our investigation into overspending in our AWS bill. Our EC2 spend ran away from us for a few weeks, even though we had been on top of hibernating our self-managed clusters not in use.

While drilling down the bill, we noticed a costly line item for `x.xxxx per GB-month of Provisioned IOPS SSD (io1) provisioned storage`.

It was initially a bit of a mystery for two reasons:

1. Clusters in that region were hibernated for most of the billing cycle, so there should be no data IO between EC2 and EBS instances.
2. Our application storage uses the `gp3-csi` storage class for volumes.

## A Bit of Background

When it comes to volume storage in AWS, you are looking at [AWS EBS](https://aws.amazon.com/ebs/) volume types. There are currently four categories:

1. [General Purpose](https://aws.amazon.com/ebs/general-purpose/) volumes, such as `gp2` and `gp3`
2. [Provisioned IOPS](https://aws.amazon.com/ebs/provisioned-iops/), such as `io1` and `io2`
3. [Throughput Optimized HDD volumes](https://aws.amazon.com/ebs/throughput-optimized/), such as `st1`
4. [Cold HDD Volumes](https://aws.amazon.com/ebs/cold-hdd/), such as `sc1`

To get the easy ones out of the way:

- Option `3` is a poor match for node volumes, as it favors data throughput at the expense of IOPS capacity. For example, something like "etcd" on master nodes needs the opposite tradeoff, with a high number of small IO transactions per second. Worker nodes require initial bursts of high-volume transfer to cache images, where `st1` may help but then drop to nearly no traffic afterwards. At this point, you are just paying for very expensive and highly capable storage for no reason.

- Option `4` is magnetic tapes, so enough said.

This leaves us choosing between "General Purpose" and "Provisioned IOPS" for the node volumes.

It is worth noting that the digit after the volume type name indicates the generation of the technology. In other words, `gp3` supersedes `gp2`, and `io2` supersedes `io1`.

In time, `gp3` and `io2` were [introduced in 2020](https://aws.amazon.com/about-aws/whats-new/2020/12/introducing-new-amazon-ebs-general-purpose-volumes-gp3/) and [2021](https://aws.amazon.com/about-aws/whats-new/2021/07/aws-announces-general-availability-amazon-ebs-block-express-volumes/), respectively.

Interestingly enough, `gp3` is not that much more capable than its `gp2` predecessor, it is mostly [less expensive](https://aws.amazon.com/blogs/storage/migrate-your-amazon-ebs-volumes-from-gp2-to-gp3-and-save-up-to-20-on-costs/) across all billing dimensions.

On the other hand, `io2` is cheaper AND [more reliable](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-optimized.html) than `io1`.

So, if your workloads still use `gp2` or `io1` volume types, your org may be paying extra dollars for reduced performance.

## Root Cause #1: Why unexpected `io1` volumes?

The reason for the presence of `io1` volumes came up rather quickly.

Those were the root volumes for _cluster nodes_, not the storage volumes for applications. The OCP installers set up these root volumes, one per node, while creating the entire cluster.

A root volume is a local disk for each node, and it is used for things like hosting the binaries running the Kubernetes processes, caching container images for containers running in the node, and transient storage for container filesystems.

By default, the OCP installers for AWS [steer administrators towards choosing the `io1` volume type](https://docs.openshift.com/container-platform/4.12/installing/installing_aws/installing-aws-customizations.html) for the nodes.

The `io1` volume type is also the suggested default for the root volumes of AWS self-managed clusters created through [RHACM](https://access.redhat.com/documentation/en-us/red_hat_advanced_cluster_management_for_kubernetes/2.8), as well as the hardcoded choice for [ROSA](https://docs.openshift.com/rosa/rosa_architecture/rosa-understanding.html) clusters.

## Root Cause #2: Why do volumes without IO activity cost so much?

For those not familiar with the cost model for [AWS storage volume types for EBS](https://aws.amazon.com/ebs/volume-types/), you are billed across the following dimensions:

1. Requested volume size.
2. "Provisioned IOPS," a _reservation_ for the maximum number of IO operations per second
3. Provisioned throughput, a _reservation_ for the maximum data volume per second.

Given that these are all reservations, you pay for the capacity whether or not you are using it. The cost for volume size is higher for "Provisioned IOPS."

As of today, here is the cost and capacity information directly from the AWS website:

- [https://aws.amazon.com/ebs/general-purpose/](https://aws.amazon.com/ebs/general-purpose/)
- [https://aws.amazon.com/ebs/provisioned-iops/](https://aws.amazon.com/ebs/provisioned-iops/)

| io1 | io2 | gp3 |
| ------------------- | -------------------- | --- |
| 64,000 Max IOPS/volume | 64,000 Max IOPS/volume  | 16,000 Max IOPS/volume |
| $0.125/GB-month| $0.125/GB-month | $0.08/GB-month|
| $0.065/provisioned IOPS-month | $0.065/provisioned IOPS-month up to 32,000 IOPS<br><br>$0.046/provisioned IOPS-month from 32,001 to 64,000 IOPS<br><br>$0.032/provisioned IOPS-month for greater than 64,000 IOPS | 3,000 IOPS free and<br><br>$0.005/provisioned IOPS-month over 3,000|
| - | - | 125 MB/s free and<br>$0.04/provisioned MB/s-month over 125|

To spell it out, not only does `gp3` cost less per requested storage capacity than either `io1` or `io2` volumes (0.08/GB-month versus 0.125/GB-month,) but its provisioned IOPS cost is a whopping **13 times cheaper**.

Additionally, by default, the OCP installers only reserve 4,000 IOPS per volume, well within the operational range of the cheaper `gp3` storage. With that setting, the cluster nodes will never be allowed to reach the much higher IOPS limits for `io1` node volumes.

You may point out that `gp3` has an associated cost for provisioned throughput above 125MB/s. However, the OpenShift installers for AWS are hardcoded to request the root volumes with the throughput capped at 125MB/s. You will not be paying for that unless you manually increase that throughput reservation later.

## Do you really need io1/io2 volumes over gp3 volumes?

For particular production workloads, maybe. For development, rarely.

The advantage of "Provisioned IOPS" over "General Purpose" volume types is that the former allows higher IOPS rates. For example, `io2` enables the reservation of up to 64,000 IOPS per volume, while `gp3` tops at reservations of 16,000 IOPS per volume. Considering that OpenShift installers either suggest or default to requesting the reservation of only 4,000 IOPS, it does not matter whether you choose `io2` or `gp3` unless you plan to bump up the reservations past 16,000 IOPS later.

## Summary

1. If using ROSA clusters, root volumes cannot be configured, so you must accept using "Provisioned IOPS" volumes.
2. If you still use `gp2` or `io1` volumes, consider "upgrading" them to `gp3` and `io2`. The costs for `gp3` and `io2` tend to be much lower, especially when requesting the higher capacity reservations for throughput and IOPS.
3. If using self-managed AWS clusters, study the limits available for the different volume types and decide whether `gp3` storage volumes specified with a max throughput of 125MB/s will work for the root volume of master and worker nodes. The use of `gp3` will lower your AWS bill without affecting cluster performance.
4. If you actually need the higher reserved IOPS capacity of "Provisioned IOPS" volume types, `io2` is considerably cheaper than `io1`, to the tune of 50% cheaper than `io1` if you ask for more than 64,000 IOPS for each root volume.
