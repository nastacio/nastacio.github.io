#!/bin/bash

kubectl get MachineSet \
    -n openshift-machine-api \
    --selector machine.sourcepatch.com/interruptible="true" \
    -o template='{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}' \
| while read -r ms
do
  cat << EOF | kubectl apply -f -
---
apiVersion: autoscaling.openshift.io/v1beta1
kind: MachineAutoscaler
metadata:
  labels:
    machine.sourcepatch.com/interruptible: "true"
  name: ${ms}
  namespace: openshift-machine-api
spec:
  minReplicas: 0
  maxReplicas: 3
  scaleTargetRef:
    apiVersion: machine.openshift.io/v1beta1
    kind: MachineSet
    name: ${ms}
EOF
done

#
# Undoing the changes in the previous command:
#
# kubectl delete MachineAutoscaler \
#     -n openshift-machine-api \
#     --selector machine.sourcepatch.com/interruptible="true" \
