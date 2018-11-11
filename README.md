# istio-helm

Fork of istio helm templates, with additional modularity.

Each module should be installed in separate namespaces, to improve security and 
reduce upgrade risks. This allows testing a new configuration or version 
before rolling it out to all pods.

Except istio-system, all modules support multiple 'profiles' (prod, canary, v10, vnext,
etc). Each profile is implemneted using a separae, isolated namespace - the admin
of 'prod' can be different than the admin of 'experiments'.

The profile is selected by labeling the namespace or pod annotations.

Major components:

1. istio-system - will be left with only CRDs and possibly citadel (master secret).
Singleton.

1. istio-control-$PROFILE - pilot, possibly sidecar injector
 
1. istio-config - galley

1. istio-telemetry-$PROFILE - mixer telemetry, possibly prometheus

1. istio-policy-$PROFILE - mixer policy.

1. istio-ingress-$PROFILE - each ingress gateway will handle one or more IPs and
hosts, their certificates and control the routing for its domains to app namespaces.

1. istio-egress-$PROFILE - install if you want all outgoing traffic to be controlled.
When namespace isolation is available, different apps can use different egress
gateways.

TODO: should sidecar injector be in istio-control ? istio-control or istio-pilot ?

Each component's profile should work with versions +1 or -1, to allow gradual and 
by-component upgrade or rollback. For example 1.1 pilot will work with both 1.0.3
and 1.2 sidecars and gateways.

Pods can use a particular profile:
- selecting them using namespace labels, which allows a specific injector profile to
be used
- using different configs with kube-inject
- using an explicit annotation on the pod, to select a specific pilot
- TODO: cni plugin should also support this.

## Installing istio-system

You can migrate from Istio 1.0.x to the new modular install, or start fresh.
Current focus is on the smooth migration experience, until the 'fresh install'
is ready I recommend starting with Istio 1.0.x or 1.1 install in istio-system.

IN PROGRESS: A new install will start with deploying the core components in istio-system.
This will include the CRDs and (optional) citadel.

```
cd istio
helm dep update
helm install . -n istio-system --namespace istio-system
cd ..

```

Next step is to follow the 'gradual install' steps to add the components you want.


### Control Plane - pilot

Install:

```
helm install -n istio-pilot11 --namespace istio-pilot11 pilot \
   --set global.tag=release-1.1-latest-daily 

# Install other pilot versions for canarying and testing
helm install -n istio-pilot10 --namespace istio-pilot10 pilot \
  --set global.tag=release-1.0-latest-daily \
   --set externalPort=14011
 
# You can also install a pilot from master, or with different set of settings 
helm install -n istio-pilot12 --namespace istio-pilot12 pilot \
   --set global.tag=master-latest-daily \
   --set externalPort=16011
```

Each pod will select the pilot to use for configuration using annotation, auto-injection
or kube-inject flags.

### Sidecar injector

It is now possible to have multiple sidecar injectors, each with a different setup.
To select which injector to use, specify a label on the namespace:

```bash

```

TODO: how to set a default injector, exclude from default (tweak the config)

Note that the 'mesh config' associated with the injector is part of the injector config map.


### Ingress gateways 

Installing gateways:

```

# Install the main ingress gateway, using 1.1 envoy and pilot11
helm install --namespace istio-ingress -n \
  istio-ingress ingress 

# A gateway using Istio 1.0 pilot (for testing)
helm install --namespace istio-ingress-10 -n istio-ingress-10 ingress \
   --set global.tag=release-1.0-latest-daily \
   --set global.istioNamespace=istio-pilot10 --set debug=debug

```

Upgrade using same settings with ```helm upgrade NAME subcharts/pilot ...```

### Egress gatways

If you want to route outbound traffic trough an egress gateway, you need to install it
and optionally prevent pods from direct access to external addresses using TrafficPolicy.

The egress is also currently required for zero vpn. 

```bash

helm install --namespace istio-egress -n \
  istio-egress 

```

You can install multiple egress-es, using different namespaces. Note that for each additional
egress you must define a different suffix for zvpn.

```bash

helm install --namespace istio-egress-test -n \
  istio-egress-test --set suffix=test --set debug=debug

```


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
