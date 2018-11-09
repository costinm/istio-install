helm upgrade istio-system install/kubernetes/helm/istio -f tests/helm/istio-system/values-small.yaml --set global.tag=101-6 --set global.hub=costinm  -f tests/helm/istio-system/values-small.yaml
