#!/bin/sh

infra_id=$(kubectl get Infrastructure cluster -o jsonpath='{.status.infrastructureName}')
echo "Infrastructure id is: ${infra_id}"

# Make sure to pick a valid instance type for the cloud region
#
# (Empirically, instance sizes above 4x8  are reclaimed too quickly
# to be useful as Kubernetes nodes.)
#
instance_size=${1:-c5a.xlarge}

kubectl get MachineSet \
        -n openshift-machine-api \
        -l hive.openshift.io/machine-pool=worker \
        -l hive.openshift.io/managed=true \
        -o yaml \
    | yq 'del (.items[].status)' \
    | yq 'del (.items[].metadata.annotations)' \
    | yq 'del (.items[].metadata.uid)' \
    | yq 'del (.items[].metadata.resourceVersion)' \
    | yq 'del (.items[].metadata.generation)' \
    | yq 'del (.items[].metadata.creationTimestamp)' \
    | yq 'del (.items[].metadata.labels."hive.openshift.io/managed")' \
    | yq 'del (.items[].metadata.labels."hive.openshift.io/machine-pool")' \
    | yq '.items[].metadata.labels += { "machine.sourcepatch.com/interruptible": "true" }' \
    | yq '.items[].spec.template.metadata.labels += { "machine.sourcepatch.com/interruptible": "true" }' \
    | yq '.items[].spec.template.spec.providerSpec.value.spotMarketOptions={}' \
    | yq '.items[].spec.template.spec.taints += [{ "effect": "NoSchedule", "key": "workload.sourcepatch.com/interruptible", "value": "true" }]' \
    | yq '.items[].spec.template.spec.metadata.labels += { "sourcepatch.com/node.interruptible": "true"}' \
    | yq ".items[].spec.template.spec.providerSpec.value.instanceType= \"${instance_size:?}\"" \
    | sed "s/name: ${infra_id:?}-worker/name: ${infra_id:?}-worker-spot/" \
    | sed "s/machineset: ${infra_id:?}-worker/machineset: ${infra_id:?}-worker-spot/" \
    | kubectl apply -f -

#
# Undoing the changes in the previous command:
#
# kubectl delete MachineSet \
#     -n openshift-machine-api \
#     -l machine.sourcepatch.com/interruptible
