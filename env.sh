#!/usr/bin/env bash

# A set of helper functions and examples of install. You can set ISTIO_CONFIG to a yaml file containing
# your own setting overrides.
# 
# - install_FOO [update|install|delete] - will update(default)  or install/delete the FOO component
# - install_all - a typical deployment with all core components.
#
#
# Environment:
# ISTIO_CONFIG - file containing user-specified overrides
# TOP - if set will be used to locate src/istio.io/istio for installing a 'bookinfo-style' istio for upgrade tests
# TEMPLATE=1 - generate template to stdout instead of installing
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

# TAGs will default to 'BRANCH-latest-daily'

# All 'install_' functions take 'install' or 'delete' as optional parameter, update by default.
# The minimal istio-system needed for the a-la-carte.


# Can run side-by-side with istio 1.0 or 1.1 - just runs citadel.
#
# Optional:
# - insecure mode set ( not implemented yet in this repo)
# - alternative cert provisioning is used (node agent, etc) exposing SDS interface
# - Secrets with expected names must be created manually or by some automation tools. (TODO: document requirements)
#
# CRITICAL: before installing a control plane profile, make sure you upgrade citadel settings
# Galley and injector depend on DNS-based certs.
function install_system() {
    local upg=${1:-update}
    shift

    NAMESPACE=istio-system helm_cmd $upg istio-system-citadel $IBASE/istio-system  $*
}


# Default control plane under istio-control
# This also acts as ingress controller, using default istio-ingress
function install_control() {
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-control $IBASE/istio-control
}

# Ingress 1.1 in istio-ingress namespace, with k8s ingress and dedicated pilot
# istio-system may have a second ingress.
function install_ingress() {
    local upg=${1:-update}
    shift

    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Normal 1.1 ingress. Defaults to istio-control control plane.
    helm_cmd $upg istio-ingress $IBASE/istio-ingress \
        --set k8sIngress=true \
        --set global.istioNamespace=istio-ingress \
        $*
}

function install_ingress_pilot() {
    local upg=${1:-update}
    shift

    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Same namespace pilot, with ingress controller activated
    # No MCP or injector - dedicated for the gateway ( perf and scale characteristics are different from main pilot,
    # and we may want custom settings anyways )
    NAMESPACE=istio-ingress helm_cmd $upg istio-ingress-pilot $IBASE/istio-control \
         --set ingress.ingressControllerMode=DEFAULT \
         --set pilot.env.K8S_INGRESS_NS=istio-ingress \
         --set pilot.useMCP=false \
         --set sidecarInjectorWebhook.enabled=false \
         --set galley.enabled=false \
          $*

}

# Verify we can install a second ingress.
# This must be in STRTICT mode to avoid conflicts
function install_ingress_insecure() {
    local upg=${1:-update}
    shift

    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Normal 1.1 ingress. Defaults to istio-control control plane.
    helm_cmd $upg istio-ingress-insecure $IBASE/istio-ingress \
        --set k8sIngress=true \
        --set global.controlPlaneSecurityEnabled=false \
        --set global.istioNamespace=istio-ingress-insecure \
        $*
}

function install_ingress_pilot_insecure() {
    local upg=${1:-update}
    shift

    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Same namespace pilot, with ingress controller activated
    # No MCP or injector - dedicated for the gateway ( perf and scale characteristics are different from main pilot,
    # and we may want custom settings anyways )
    # Policy disabled by default ( insecure anyways ), can be enabled for tests.
    NAMESPACE=istio-ingress-insecure helm_cmd $upg istio-ingress-insecure-pilot $IBASE/istio-control \
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

# Standalone ingress. Uses istio-system pilot.
function install_ingress_system() {
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-ingress-system $IBASE/istio-ingress \
        --set domain=wis.istio.webinf.info \
        --set global.istioNamespace=istio-system \
        $*
    kubectl --namespace istio-ingress-system get svc -o wide
}

# Standalone ingress. Uses istio-pilot11 pilot.
function install_ingress_11() {
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-ingress11 $IBASE/istio-ingress \
        --set domain=w11.istio.webinf.info \
        --set global.istioNamespace=istio-pilot11 \
        $*

    kubectl --namespace istio-ingress11 get svc -o wide

}

# Egress gateway
function install_egress() {
    # update or install or delete
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-egress $IBASE/istio-egress --set zvpn.suffix=v10.webinf.info $*

}


# Typical installation
function install_all() {
    local upg=${1:-update}
    shift

    install_system $upg $*
    install_control $upg $*
    install_ingress_pilot $upg $*
    install_ingress $upg $*
    install_telemetry $upg $*
    install_policy $upg $*
}

# Install full istio1.1 in istio-system
function install_system11() {
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-system $TOP/src/istio.io/istio/install/kubernetes/helm/istio  $*
}


# Pilot-10 profile. Standalone pilot and istio-1.0.
# Old - may still work but not supported, only 1.1+
#function install_control10() {
#    local upg=${1:-update}
#    shift
#
#    helm_cmd $upg istio-pilot10 $IBASE/istio-control --set global.istio10=true --set global.tag=release-1.0-latest-daily $*
#}

# Second test control plane under istio-pilot11
function install_control11() {
    local upg=${1:-update}
    shift

    helm_cmd $upg istio-pilot11 $IBASE/istio-control
}

function install_telemetry() {
    local upg=${1:-update}
    shift

    helm_cmd  $upg istio-telemetry $IBASE/istio-telemetry $*
}

function install_policy() {
    local upg=${1:-update}
    shift

    helm_cmd  $upg istio-policy $IBASE/istio-policy $*
}
# Install just node agent, in istio-system - a-la-carte.
# Node agent will run, but default config for istio-system will not use it until it is updated.
# It should be possible to opt-in !
function install_nodeagent() {
    local upg=${1:-update}
    shift

    # env.CA_PROVIDER
    # env.CA_ADDR


    NAMESPACE=istio-system helm_cmd $upg nodeagent $IBASE/istio-system/charts/nodeagent
}

# Install just CNI, in istio-system
# TODO: verify it ignores auto-installed, opt-in possible
function install_cni() {
    local upg=${1:-update}
    shift

    NAMESPACE=istio-system helm_cmd $upg cni $IBASE/istio-system/charts/istio-cni
}

function install_load() {
    local upg=${1:-update}
    shift

    kubectl create ns load
    kubectl label namespace load istio-injection=enabled

    helm_cmd $upg load $IBASE/test/pilotload $*
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

function install_test_apps() {
    #helm install -n fortio11 --namespace fortio11 helm/fortio
    #kubectl -n test apply -f samples/httpbin/httpbin.yaml
    #kubectl -n bookinfo apply -f samples/bookinfo/kube/bookinfo.yaml

    helm install -n fortio10 --namespace fortio10 test/fortio

}

function install_testns() {
    # Using istio-system (can be pilot10 or pilot11) annotation
    kubectl create ns test
    kubectl label namespace test istio-injection=enabled

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

# Setup DNS entries - currently using gcloud
# Requires DNS_PROJECT, DNS_DOMAIN and DNS_ZONE to be set
# For example, DNS_DOMAIN can be istio.example.com and DNS_ZONE istiozone.
# You need to either buy a domain from google or set the DNS to point to gcp.
# Similar scripts can setup DNS using a different provider
function testCreateDNS() {
    local ver=${1:-v10}
    local name=ingress${ver}

    gcloud dns --project=$DNS_PROJECT record-sets transaction start --zone=$DNS_ZONE

    gcloud dns --project=$DNS_PROJECT record-sets transaction add $IP --name=${name}.${DNS_DOMAIN}. --ttl=300 --type=A --zone=$DNS_ZONE
    gcloud dns --project=$DNS_PROJECT record-sets transaction add ${name}.${DNS_DOMAIN} --name="*.${ver}.${DNS_DOMAIN}." --ttl=300  --type=CNAME --zone=$DNS_ZONE

    gcloud dns --project=$DNS_PROJECT record-sets transaction execute --zone=$DNS_ZONE
}

# Prepare GKE for Lego DNS. You must have a domain, $DNS_PROJECT
# and a zone DNS_ZONE created.
function getCertLegoInit() {
 local domain=${1:-w10.istio.webinf.info}

 # DNS_ZONE=istiotest
 # GCP_PROJECT=costin-istio
 # DNS_DOMAIN=istio.webinf.info
 gcloud iam service-accounts create dnsmaster
 gcloud projects add-iam-policy-binding $DNS_PROJECT  \
   --member "serviceAccount:dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com" \
   --role roles/dns.admin
 gcloud iam service-accounts keys create $HOME/.ssh/dnsmaster.json \
    --iam-account dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com

 gcloud dns record-sets list --zone ${DNS_ZONE}

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


# Get a wildcard ACME cert. MUST BE CALLED BEFORE SETTING THE CNAME
function getCertLego() {
 local domain=${1:-w10.istio.webinf.info}

 GCE_SERVICE_ACCOUNT_FILE=~/.ssh/dnsmaster.json \
 GCE_PROJECT="$DNS_PROJECT"  \
 lego -a --email="dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com"  \
 --domains="*.${domain}"     \
 --dns="gcloud"     \
 --path="${HOME}/.lego"  run
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

# Run install or update helm.
# The namespace will match the deployment name.
#
# Params
# 1. command - install | update | delete
# 2. namespace - will also be used as chart name (unless explicitly overridden)
# 3. chart_directory
# 4. any other options
#
# Env: HUB
# You can specify --set global.tag=$TAG to override the chart's default.
function helm_cmd() {
    local upg=$1
    shift
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
    elif [ "$upg" == "update" ] ; then
        echo helm upgrade $n $cfg $*
        helm upgrade --wait $n $* $cfg
    elif [ "$upg" == "delete" ] ; then
        helm delete --purge $n
    else
        echo helm install --namespace $ns -n $n $cfg  $*
        helm install --namespace $ns -n $n $cfg $*
    fi
}
