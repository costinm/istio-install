#!/usr/bin/env bash

kubectl create ns istio-micro-ingress 2>/dev/null
kubectl create ns test-micro-ingress 2>/dev/null

# --prune --all --cascade=true  -> doesn't work across namespaces
kubectl apply --grace-period=4 -n istio-micro-ingress -f test/k8s/minimal-ingress/istio-micro-ingress
kubectl apply --grace-period=4 -n test-micro-ingress -f test/k8s/minimal-ingress/test-micro-ingress

kubectl get nodes -o wide
