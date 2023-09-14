#!/bin/sh

# https://knative.dev/docs/serving/configuration/feature-flags/#kubernetes-node-affinity 
kubectl patch ConfigMap config-features \
   -n knative-serving \
   -p '{"data":{"kubernetes.podspec-affinity":"enabled"}}'

# https://knative.dev/docs/serving/configuration/feature-flags/#kubernetes-toleration
kubectl patch ConfigMap config-features \
   -n knative-serving \
   -p '{"data":{"kubernetes.podspec-tolerations":"enabled"}}'

# https://knative.dev/docs/serving/configuration/feature-flags/#kubernetes-node-selector
kubectl patch ConfigMap config-features \
   -n knative-serving \
   -p '{"data":{"kubernetes.podspec-nodeselector":"enabled"}}'
