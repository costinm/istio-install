# istio-helm

Fork of istio helm templates, with additional modularity.

## Separate namespaces

Each component should be installed in separate namespaces, to improve security and 
reduce upgrade risks.

With few exceptions - citadel CA, k8s ingress - it is possible to run each component
in multiple namespaces, with possibly different versions or settings. 

This allows testing a new configuration or version before rolling it out to all pods.

Pods can use a particular configuration in 2 ways:
- using an explicit annotation on the pod, to select a specific pilot
- by deploying separate sidecar injectors, and selecting them using namespace labels.

## New install

A new install will start with deploying the core components in istio-system.

```
cd istio
helm dep update
helm install . -n istio-system --namespace istio-system
cd ..

```

Next step is to follow the 'gradual install' steps to add the components you want.
Note that installing istio-system includes some of the components that are not yet
migrated to separate namespace/installs: galley, mixer and prometheus, citadel. 

## Gradual install / migration

For a gradual install of the new version: start with installing Istio 1.0.x
If you already have 1.0.x installed - keep it in place while following the next steps.

### Control Plane - pilot

Install:

```

# Install other pilot versions for canarying and testing
helm install -n istio-pilot10 --namespace istio-pilot10 subcharts/pilot \
  --set global.tag=release-1.0-latest-daily
helm install -n istio-pilot11 --namespace istio-pilot11 subcharts/pilot \
   --set global.tag=release-1.1-latest-daily \
   --set externalPort=14011
helm install -n istio-pilot12 --namespace istio-pilot11 subcharts/pilot --set global.tag=master-latest-daily \
   --set externalPort=16011

```

Installing gateways:

```

# Install the main ingress gateway, using 1.1 envoy and pilot11
helm install --namespace istio-ingress -n \
  istio-ingress ingress 

helm install --namespace istio-egress -n \
  istio-egress 

# A gateway using Istio 1.0 pilot (for testing)
helm install --namespace istio-ingress-10 -n istio-ingress-10 ingress \
   --set global.tag=release-1.0-latest-daily \
   --set global.istioNamespace=istio-pilot10 --set debug=debug

```

Upgrade using same settings with ```helm upgrade NAME subcharts/pilot ...```

## Other components

```
helm install --namespace grafana -n grafana subcharts/grafana



```

## Get status and config

To see which sidecar and gateway is connected to each pilot:

```

istioctl proxy-status -i istio-pilot10
istioctl proxy-status -i istio-pilot11
istioctl proxy-status -i istio-pilot12
istioctl proxy-status 


```

## Additional test templates

A number of helm test setups are general-purpose and should be installable in any cluster, to confirm
Istio works properly and allow testing the specific install.


## TODO

- move citadel to separate namespace, don't install in istio-system
- move prometheus and telemetry to separate namespace
