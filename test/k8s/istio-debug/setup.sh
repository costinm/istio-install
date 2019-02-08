#!/usr/bin/env bash

D=${1:-control.istio.webinf.info}
INGRESS=${INGRESS:-istio-ingress}

kubectl create ns istio-debug 2>/dev/null


cat test/k8s/istio-debug/pilot-gateway.yaml | \
  sed s/control.istio.webinf.info/$D/  | \
  sed s,istio-ingress,${INGRESS}, | \
  kubectl apply --grace-period=4  -f -
