# istio-helm

Fork of istio helm templates, with additional modularity.

## Separate namespaces

Pilot and gateways can be installed in separate namespaces, including with different versions 
This allows separation of admins, and using 'production' and 'canary' versions. 


Install:

```
# Install system components - default to master. 
# Gateway will be installed in separate namespace
cd istio
helm dep update
helm install . -n istio-system --namespace istio-system --set gateways.enabled=false
cd ..

# Install other pilot versions for canarying and testing
helm install -n istio-pilot10 --namespace istio-pilot10 subcharts/pilot --set global.tag=release-1.0-latest-daily
helm install -n istio-pilot11 --namespace istio-pilot11 subcharts/pilot --set global.tag=release-1.1-latest-daily \
   --set externalPort=14011
helm install -n istio-pilot12 --namespace istio-pilot11 subcharts/pilot --set global.tag=master-latest-daily \
   --set externalPort=16011

# Install the main gateway, using 1.0 envoy and pilot10
helm install --namespace istio-gateways -n \
  istio-gateways subcharts/gateways --set global.tag=release-1.0-latest-daily \
  --set global.istioNamespace=istio-pilot10 --set istio-egressgateway.enabled=false

# A second gateway, with separate IP, using 11 envoy and pilot11
# You can also point it to istio-system or any other pilot version or configuration.
helm install subcharts/gateways -n istio-gateways-canary --namespace istio-gateways-canary \
  --set global.tag=release-1.1-latest-daily --set istio-egressgateway.enabled=false \
  --set global.istioNamespace=istio-pilot11

```

Upgrade using same settings with ```helm upgrade NAME subcharts/pilot ...```

## Additional test templates

A number of helm test setups are general-purpose and should be installable in any cluster, to confirm
Istio works properly and allow testing the specific install.


