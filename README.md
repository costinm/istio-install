# istio-installer

Fork of istio helm templates, with additional 'a-la-carte' modularity and security.

The main feature is that the new installer isolates the components, allowing multiple
versions (prod/canary/staging/dev) of each istio component.

This improve security and reduce upgrade risks, allowing testing a new configuration or version 
before rolling it out to all pods and separating the admin permission required for each 
component.

The install is organized in 'environments' - each environment consists of a set of components
in different namespaces that are configured to work together. Regardless of 'environment',
workloads can talk with each other and follow the Istio configs, but each environment 
can use different versions and different defaults. 

Kube-inject or the automatic injector are used to select the environment. The the later,
the namespace label 'istio-env:NAME_OF_ENV' is used instead of 'istio-injected:true'.
The name of the environment is defined as the namespace where the corresponding control plane is 
running. Pod annotations can also select a different control plane. 

# Installing

The new installer is intended to be modular and very explicit about what is installed.
The target is production users who want to correctly tune and understand each binary that
gets deployed, and select which combination to use.

Different teams can manage different components: it is recommended to create a namespace
and an associated service account for each major component. (Note - there are still some 
cluster roles that may need to be fixed...).

It is possible to install each component with 'helm' or 'helm template' + kubectl apply --prune,
see the 'env.sh' for examples.

Note that all steps can be performed in parallel with an existing Istio 1.0 or 1.1 install in
Istio-system. The new components will not interfere with existing apps, but can interoperate 
and it is possible to gradually move apps from Istio 1.0/1.1 to the new environments and 
across environments ( for example canary -> prod )

For each component, there are 2 styles of installing:

Using kubectl prune (recommended):

```bash

helm template --namespace $NAMESPACE -n $COMPONENT $CONFIGDIR -f global.yaml | \
   kubectl apply -n $NAMESPACE --prune -l release=$COMPONENT -f -

```

Using helm:

```bash
helm upgrade --namespace $NAMESPACE -n $COMPONENT $CONFIGDIR -f global.yaml 
```

The doc will use the "iop" helper from env.sh - which is the equivalent with the command 
above. First parameter is NAMESPACE, second is the name of the COMPONENT, and third the directory 
where the config is stored.

## Common options

TODO

## Install CRDs

This is the first step of the install. Please do not remove or edit any CRD - galley requires 
all CRDs to be present. On each upgrade it is recommended to reapply the file, to make sure 
you get all CRDs.

```bash
 kubectl apply -f crds.yaml
```

## Install Security

Security should be installed in istio-system, since it needs access to the root CA. 

This is currently required - but in future other Spifee implementations can be used.

```bash
iop istio-system istio-system-security $IBASE/istio-system-security
```

Important options: the 'dnsCerts' list allows associating DNS certs with specific service accounts.
This should be used if you plan to use Galley or Sidecar injector in different namespaces.
By default it supports "istio-control", "istio-master" namespaces used in the examples.


## Install Control plane 


Control plane contains 3 components. 

### Config (Galley) 

This can be run in any other cluster having the CRDs configured via CI/CD systems or other sync mechanisms. 
It should not be run in 'secondary' clusters, where the configs are not replicated.

Only one environment should enable validation - it is not supported in multiple namespaces.

```bash  
     iop istio-control istio-config istio-config --set configValidation=true

    # Second Galley, using master version of istio
    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-config-master istio-config
```

### Discovery (Pilot)

This can run in any cluster - at least one cluster should run Pilot or equivalent XDS server.

```bash
    iop istio-control istio-control $IBASE/istio-control

    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-control-master $IBASE/istio-control \
                --set policy.enable=false \
               --set global.istioNamespace=istio-master \
               --set global.telemetryNamespace=istio-telemetry-master \
               --set global.policyNamespace=istio-policy-maste

```

### Auto-injection 

This is optional - kube-inject can be used instead.

Only one namespace should have enableNamespacesByDefault=true

```bash
    iop istio-control istio-autoinject $IBASE/istio-autoinject --set enableNamespacesByDefault=true
    
    # Second auto-inject using master version of istio
    # Notice the different options
    TAG=master-latest-daily HUB=gcr.io/istio-release iop istio-master istio-autoinject-master $IBASE/istio-autoinject \
             --set global.istioNamespace=istio-master 

```

## Gateways

A cluster may use multiple Gateways, each with a different load balancer IP, domains and certificates.

Since the domain certificates are stored in the gateway namespace, it is recommended to keep each 
gateway in a dedicated namespace and restrict access.

For large-scale gateways it is optionally possible to use a dedicated pilot in the gateway namespace. 

## K8S Ingress

To support K8S ingress we currently use a separate namespace, using a dedicated Pilot instance. 

## Telemetry 

TODO - see example

## Policy 

TODO - see example

## Egress 


## Other components 


### Egress gatways


## Additional test templates

A number of helm test setups are general-purpose and should be installable in any cluster, to confirm
Istio works properly and allow testing the specific install.

