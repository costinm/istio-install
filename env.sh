#!/usr/bin/env bash

# A set of helper functions and examples of install. You can set ISTIO_CONFIG to a yaml file containing
# your own setting overrides.
# 
# - iop_FOO [update|install|delete] - will update(default)  or install/delete the FOO component
# - iop_all - a typical deployment with all core components.
#
#
# Environment:
# - ISTIO_CONFIG - file containing user-specified overrides
# - TOP - if set will be used to locate src/istio.io/istio for installing a 'bookinfo-style' istio for upgrade tests
# - TEMPLATE=1 - generate template to stdout instead of installing
# - INSTALL=1: do an install instead of the default 'update'
# - DELETE=1: do a delete/purge instead of the default 'update'
# - NAMESPACE - namespace where the component is installed, defaults to name of component
# - DOMAIN - if set, ingress will setup mappings for the domain (requires a A and * CNAME records)
#
# Files:
# global.yaml - istio common settings and docs
# user-values... - example config overrides
# FOO/values.yaml - each component settings (not including globals)
# ~/.istio.rc - environment variables sourced - may include TOP, TAG, HUB
# ~/.istio-values.yaml - user config (can include common setting overrides)




# Allow setting some common per user env.
if [ -f $HOME/.istio.rc ]; then
    source $HOME/.istio.rc
fi

if [ "$TOP" == "" ]; then
  IBASE=.
else
  IBASE=$TOP/src/github.com/costinm/istio-install
fi

# Contains values overrides for all configs.
# Can point to a different file, based on env or .istio.rc
ISTIO_CONFIG=${ISTIO_CONFIG:-${IBASE}/user-values.yaml}


HUB=${HUB:-grc.io/istio-release}


# TAGs will default to 'release1.1-latest-daily'

# Typical installation
function iop_all() {
    iop_system_citadel $*
    iop_control $*
    iop_ingress_pilot $*
    iop_ingress $*
    iop_telemetry $*
    iop_policy $*
}

# Install a test environment - you can use different TAG or settings.
function iop_tst_env() {
    # Control under istio-pilot11
    iop_control11 $*

    # Under istio-ingress-insecure, mtls off, not using certs.
    iop_ingress_pilot_insecure $*
    iop_ingress_insecure $*
}

# Can run side-by-side with istio 1.0 or 1.1 - just runs citadel.
#
# Optional:
# - insecure mode set ( not implemented yet in this repo)
# - alternative cert provisioning is used (node agent, etc) exposing SDS interface
# - Secrets with expected names must be created manually or by some automation tools. (TODO: document requirements)
#
# CRITICAL: before installing a control plane profile, make sure you upgrade citadel settings
# Galley and injector depend on DNS-based certs.
function iop_system_citadel() {
    NAMESPACE=istio-system istioop istio-system-citadel $IBASE/istio-system  $*
}


# Default control plane under istio-control
# This also acts as ingress controller, using default istio-ingress
function iop_control() {
    istioop istio-control $IBASE/istio-control
}

# Ingress 1.1 in istio-ingress namespace, with k8s ingress and dedicated pilot
# istio-system may have a second ingress.
function iop_ingress() {
    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Normal 1.1 ingress. Defaults to istio-control control plane.
    istioop istio-ingress $IBASE/istio-ingress \
        --set k8sIngress=true \
        --set global.istioNamespace=istio-ingress \
        $*
}

function iop_ingress_pilot() {
    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Same namespace pilot, with ingress controller activated
    # No MCP or injector - dedicated for the gateway ( perf and scale characteristics are different from main pilot,
    # and we may want custom settings anyways )
    NAMESPACE=istio-ingress istioop istio-ingress-pilot $IBASE/istio-control \
         --set ingress.ingressControllerMode=DEFAULT \
         --set pilot.env.K8S_INGRESS_NS=istio-ingress \
         --set pilot.useMCP=false \
         --set sidecarInjectorWebhook.enabled=false \
         --set galley.enabled=false \
          $*

}

# Verify we can install a second ingress.
# This must be in STRTICT mode to avoid conflicts
function iop_ingress_insecure() {
    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Normal 1.1 ingress. Defaults to istio-control control plane.
    istioop istio-ingress-insecure $IBASE/istio-ingress \
        --set k8sIngress=true \
        --set global.controlPlaneSecurityEnabled=false \
        --set global.istioNamespace=istio-ingress-insecure \
        $*
}

function iop_ingress_pilot_insecure() {
    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Same namespace pilot, with ingress controller activated
    # No MCP or injector - dedicated for the gateway ( perf and scale characteristics are different from main pilot,
    # and we may want custom settings anyways )
    # Policy disabled by default ( insecure anyways ), can be enabled for tests.
    NAMESPACE=istio-ingress-insecure istioop istio-ingress-insecure-pilot $IBASE/istio-control \
         --set ingress.ingressControllerMode=STRICT \
         --set pilot.env.K8S_INGRESS_NS=istio-ingress-insecure \
         --set pilot.useMCP=false \
         --set sidecarInjectorWebhook.enabled=false \
         --set galley.enabled=false \
         --set global.controlPlaneSecurityEnabled=false \
         --set global.mtls.enabled=false \
         --set pilot.policy.enabled=false \
         --set ingress.ingressClass=istio-insecure \
         --set global.meshExpansion.enabled=false \
          $*

}

# Standalone ingress. Uses istio-system pilot (bookinfo-style 1.0 or 1.1).
function iop_ingress_system() {
    istioop istio-ingress-system $IBASE/istio-ingress \
        --set domain=wis.istio.webinf.info \
        --set global.istioNamespace=istio-system \
        $*
    kubectl --namespace istio-ingress-system get svc -o wide
}

# Standalone ingress. Uses istio-pilot11 pilot.
function iop_ingress_11() {
    istioop istio-ingress11 $IBASE/istio-ingress \
        --set domain=w11.istio.webinf.info \
        --set global.istioNamespace=istio-pilot11 \
        $*

    kubectl --namespace istio-ingress11 get svc -o wide

}

# Egress gateway
function iop_egress() {
    istioop istio-egress $IBASE/istio-egress --set zvpn.suffix=v10.webinf.info $*
}


# Install full istio1.1 in istio-system
function iop_istio11_istio_system() {
    istioop istio-system $TOP/src/istio.io/istio/install/kubernetes/helm/istio  $*
}


# Pilot-10 profile. Standalone pilot and istio-1.0.
# Old - may still work but not supported, only 1.1+
#function iop_control10() {
#    istioop istio-pilot10 $IBASE/istio-control --set global.istio10=true --set global.tag=release-1.0-latest-daily $*
#}

# Second test control plane under istio-pilot11
function iop_control11() {
    istioop istio-pilot11 $IBASE/istio-control
}

function iop_telemetry() {
    istioop  istio-telemetry $IBASE/istio-telemetry $*
}

function iop_policy() {
    istioop  istio-policy $IBASE/istio-policy $*
}

# Install just node agent, in istio-system - a-la-carte.
# Node agent will run, but default config for istio-system will not use it until it is updated.
# It should be possible to opt-in !
function iop_nodeagent() {

    # env.CA_PROVIDER
    # env.CA_ADDR


    NAMESPACE=istio-system istioop nodeagent $IBASE/istio-system/charts/nodeagent
}

# Install just CNI, in istio-system
# TODO: verify it ignores auto-installed, opt-in possible
function iop_cni() {
    NAMESPACE=istio-system istioop cni $IBASE/istio-system/charts/istio-cni
}

function iop_load() {
    kubectl create ns load
    kubectl label namespace load istio-injection=enabled

    istioop load $IBASE/test/pilotload $*
}


# Kubernetes log wrapper
function _klog() {
    local label=$1
    local container=${2:-istio-proxy}
    local ns=${3:-istio-system}
    echo kubectl --namespace=$ns log $(kubectl --namespace=$ns get -l $label pod -o=jsonpath='{.items[0].metadata.name}') $container
    kubectl --namespace=$ns log $(kubectl --namespace=$ns get -l $label pod -o=jsonpath='{.items[0].metadata.name}') $container $4
}

# Kubernetes exec wrapper
function _kexec() {
    local label=$1
    local container=${2:-istio-proxy}
    local ns=${3:-istio-system}
    local cmd=${4:-/bin/bash}
    kubectl --namespace=$ns exec -it $(kubectl --namespace=$ns get -l $label pod -o=jsonpath='{.items[0].metadata.name}') -c $container -- "$cmd"
}

function logs-ingress() {
    istioctl proxy-status -i istio-pilot11
    _klog istio=istio-ingress istio-proxy istio-ingress $*
}

function exec-ingress() {
    istioctl proxy-status -i istio-pilot11
    _kexec istio=istio-ingress istio-proxy istio-ingress $*
}

function logs-inject() {
    _klog istio=sidecar-injector sidecar-injector-webhook istio-env11 $*
}

function logs-inject11() {
    _klog istio=sidecar-injector sidecar-injector-webhook istio-pilot11 $*
}

function logs-pilot11() {
    _klog istio=pilot discovery istio-pilot11 $*
}

function exec-pilot11() {
    _kexec istio=pilot discovery istio-pilot11 $*
}

function logs-fortio11() {
    _klog app=fortiotls istio-proxy fortio11 $*
}

function exec-fortio11() {
    _kexec app=fortiotls istio-proxy fortio11 $*
}

function exec-fortio11-cli() {
    _kexec app=cli-fortio-tls app fortio11 $*
}

function exec-fortio11-cli-proxy() {
    # curl -v  -k  --key /etc/certs/key.pem --cert /etc/certs/cert-chain.pem https://fortiotls:8080
    _kexec app=cli-fortio-tls istio-proxy fortio11 $*
}

function logs-fortio11-cli() {
    _klog app=cli-fortio-tls istio-proxy fortio11 $*
}

function iop_test_apps() {
    #helm install -n fortio11 --namespace fortio11 helm/fortio
    #kubectl -n test apply -f samples/httpbin/httpbin.yaml
    #kubectl -n bookinfo apply -f samples/bookinfo/kube/bookinfo.yaml

    helm install -n fortio10 --namespace fortio10 test/fortio

}

function iop_testns() {
    # Using istio-system (can be pilot10 or pilot11) annotation
    kubectl create ns test
    kubectl label namespace test istio-injection=enabled

    kubectl create ns bookinfo
    kubectl create ns bookinfo
    kubectl label namespace bookinfo istio-injection=enabled
    kubectl -n bookinfo apply -f $TOP/src/istio.io/samples/bookinfo/kube/bookinfo.yaml

    kubectl create ns httpbin
    kubectl label namespace httpbin istio-injection=enabled
    kubectl -n httpbin apply -f $TOP/src/istio.io/samples/httpbin/httpbin.yaml

    # Using custom profile for injection.
    kubectl create ns fortio11
    kubectl label ns fortio11 istio-env=istio-sidecarinjector11

    kubectl create ns fortio10
    kubectl label ns fortio10 istio-env=istio-sidecarinjector10
}

# Prepare GKE for Lego DNS. You must have a domain, $DNS_PROJECT
# and a zone DNS_ZONE created.
function getCertLegoInit() {
 # GCP_PROJECT=costin-istio

 gcloud iam service-accounts create dnsmaster

 gcloud projects add-iam-policy-binding $GCP_PROJECT  \
   --member "serviceAccount:dnsmaster@${GCP_PROJECT}.iam.gserviceaccount.com" \
   --role roles/dns.admin

 gcloud iam service-accounts keys create $HOME/.ssh/dnsmaster.json \
    --iam-account dnsmaster@${GCP_PROJECT}.iam.gserviceaccount.com

}

# Get a wildcard ACME cert. MUST BE CALLED BEFORE SETTING THE CNAME
function getCertLego() {
 # GCP_PROJECT=costin-istio
 # DOMAIN=istio.webinf.info

 #gcloud dns record-sets list --zone ${DNS_ZONE}

 GCE_SERVICE_ACCOUNT_FILE=~/.ssh/dnsmaster.json \
 lego -a --email="dnsmaster@${GCP_PROJECT}.iam.gserviceaccount.com"  \
 --domains="*.${DOMAIN}"     \
 --dns="gcloud"     \
 --path="${HOME}/.lego"  run

 kubectl create -n istio-ingress secret tls istio-ingressgateway-certs --key ${HOME}/.lego/certificates/_.${DOMAIN}.key \
    --cert ${HOME}/.lego/certificates/_.${DOMAIN}.crt

}

# Setup DNS entries - currently using gcloud
# Requires GCP_PROJECT, DOMAIN and DNS_ZONE to be set
# For example, DNS_DOMAIN can be istio.example.com and DNS_ZONE istiozone.
# You need to either buy a domain from google or set the DNS to point to gcp.
# Similar scripts can setup DNS using a different provider
function testCreateDNS() {
    local ver=${1:-v10}
    local name=ingress${ver}

    gcloud dns --project=$GCP_PROJECT record-sets transaction start --zone=$DNS_ZONE

    gcloud dns --project=$GCP_PROJECT record-sets transaction add $IP --name=${name}.${DOMAIN}. --ttl=300 --type=A --zone=$DNS_ZONE
    gcloud dns --project=$GCP_PROJECT record-sets transaction add ${name}.${DOMAIN} --name="*.${DOMAIN}." \
        --ttl=300  --type=CNAME --zone=$DNS_ZONE

    gcloud dns --project=$GCP_PROJECT record-sets transaction execute --zone=$DNS_ZONE
}


# Forward port - Label, Namespace, PortLocal, PortRemote
# Example:
#  istio-fwd istio=pilot istio-ingress 4444 8080
function istio-fwd() {
    local L=$1
    local NS=$2
    local PL=$3
    local PR=$4

    local N=$NS-$L
    if [[ -f ${LOG_DIR:-/tmp}/fwd-$N.pid ]] ; then
        kill -9 $(cat $LOG_DIR/fwd-$N.pid)
    fi
    kubectl --namespace=$NS port-forward $(kubectl --namespace=$NS get -l $L pod -o=jsonpath='{.items[0].metadata.name}') $PL:$PR &
    echo $! > $LOG_DIR/fwd-$N.pid
}


# For testing the config
function localPilot() {
    pilot-discovery discovery \
        --kubeconfig $KUBECONIG \
        --meshConfig test/local/mesh.yaml \
        --networksConfig test/local/meshNetworks.yaml \

    # TODO:
    #

    # Untested flags: --domain, -a (oneNamespace)
    # --namespace - ???
    # --plugiins=
    #

    # Defaults:
    # secureGrpcAddr :15011
    # meshConfig /etc/istio/config/mesh
    # networksConfig /etc/istio/config/meshNetworks

    # To deprecate:
    # --mcpServerAddrs mcps://istio-galley:9901 -> MeshConfig.ConfigSources.Address
    # -registries
    # -clusterRegistriesNamespace
    #
}

# Fetch the certs from a namespace, save to /etc/cert
# Same process used for mesh expansion, can also be used for dev machines.
function getCerts() {
    local NS=${1:-default}
    local SA=${2:-default}

    kubectl get secret istio.$SA -n $NS -o "jsonpath={.data['key\.pem']}" | base64 -d > /etc/certs/key.pem
    kubectl get secret istio.$SA -n $NS -o "jsonpath={.data['cert-chain\.pem']}" | base64 -d > /etc/certs/cert-chain.pem
    kubectl get secret istio.$SA -n $NS -o "jsonpath={.data['root-cert\.pem']}" | base64 -d > /etc/certs/root-cert.pem
}

# For debugging, get the istio CA. Can be used with openssl or other tools to generate certs.
function getCA() {
    kubectl get secret istio-ca-secret -n istio-system -o "jsonpath={.data['ca-cert\.pem']}" | base64 -d > /etc/certs/ca-cert.pem
    kubectl get secret istio-ca-secret -n istio-system -o "jsonpath={.data['ca-key\.pem']}" | base64 -d > /etc/certs/ca-key.pem
}

function istio_status11() {
    echo "1.0 sidecars"
    istioctl -i istio-pilot10 proxy-status
    echo "1.1 sidecars"
    istioctl -i istio-pilot11 proxy-status
}

# Run install or update istio components. This will be replaced with a real program, for now basic scripting around
# helm.
#
# CLI params
# 1. name of the deloyed component, acts as default namespace unless NAMESPACE is set.
# 2. chart_directory
# 3. any other options
#
# Environment variables:
# - INSTALL=1: do an install instead of the default 'update'
# - DELETE=1: do a delete/purge instead of the default 'update'
# - NAMESPACE - namespace where the component is installed, defaults to name of component
#
# Env: HUB
# You can specify --set global.tag=$TAG to override the chart's default.
function istioop() {
    local n=$1
    shift
    local ns=${NAMESPACE:-$n}

    # Defaults
    local cfg="-f $IBASE/global.yaml"

    # User overrides
    if [ -f $HOME/.istio-values.yaml ]; then
        cfg="$cfg -f $HOME/.istio-values.yaml"
    fi

    # File overrides
    if [ -f $ISTIO_CONFIG ]; then
        cfg="$cfg -f $ISTIO_CONFIG"
    fi

    if [ "$HUB" != "" ] ; then
        cfg="$cfg --set global.hub=$HUB"
    fi
    if [ "$TAG" != "" ] ; then
        cfg="$cfg --set global.tag=$TAG"
    fi

    if [ "$TEMPLATE" == "1" ] ; then
        helm template --namespace $ns -n $n $cfg  $*
    elif [ "$INSTALL" == "1" ] ; then
        echo helm install --namespace $ns -n $n $cfg  $*
        helm install --namespace $ns -n $n $cfg $*
    elif [ "$DELETE" == "1" ] ; then
        helm delete --purge $n
    else
        echo helm upgrade $n $cfg $*
        helm upgrade --wait $n $* $cfg
    fi
}
