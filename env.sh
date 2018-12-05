#!/usr/bin/env bash

# Allow setting some common per user env.
if [ -f $HOME/.istio.rc ]; then
    source $HOME/.istio.rc
fi

ISTIO_CONFIG=${ISTIO_CONFIG:-user-values.yaml}


HUB=${HUB:-grc.io/istio-release}

# TAGs will default to 'BRANCH-latest-daily'

# Upgrade all components
function upgrade_all() {
    _helm_all upgrade
}

# Install all components (including canaries)
function install_all() {
    _helm_all install
}

# Run install or upgrade helm.
# The namespace will match the deployment name.
#
# Params
# 1. command - install | upgrade | delete
# 2. namespace - will also be used as chart name
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

    # --set global.tag=$TAG --set global.hub=$HUB
    local cfg="-f $ISTIO_CONFIG"
    if [ -f $HOME/.istio-values.yaml ]; then
        cfg="$cfg -f $HOME/.istio-values.yaml"
    fi

    if [ "$upg" == "upgrade" ] ; then
        echo helm upgrade $n $cfg $* --set global.hub=$HUB
        helm upgrade $n $* $cfg --set global.hub=$HUB
    elif [ "$upg" == "delete" ] ; then
        helm delete --purge $n
    else
        echo helm install --namespace $n -n $n $cfg --set global.hub=$HUB $*
        helm install --namespace $n -n $n $cfg --set global.hub=$HUB $*
    fi
}

# Function to install or upgrade all components, with 2 versions, for testing and demo
function _helm_all() {
    # upgrade or install or delete
    local upg=$1
    shift

    # Istio 11, auth enabled, defaults
    helm_cmd $upg istio-pilot11 istio-control $*

    # Use the new templates to install Istio 1.0 in a dedicated namespace.
    helm_cmd $upg istio-pilot10 istio-control --set global.istio10=true --set global.tag=release-1.0-latest-daily $*

    # Istio egress gateway, 1.1
    helm_cmd $upg istio-egress istio-egress --set zvpn.suffix=v10.webinf.info $*

    # Each environment namespace has an injector config
    # Custom hub (for extra debug)
    # This is just a sidecar injector, which can be targetted by labeling the namespace.
    # Normally control plane runs an injector as well, but it's possible to create custom settings.
    helm_cmd $upg istio-env11 istio-control/charts/istio-sidecar-injector

    helm_ingress $upg $*

    #helm_cmd $upg istio-ingress-12 --set global.tag=master-latest-daily \
    #    --set zvpn.suffix=v10.webinf.info $*

    # 1.1 telemetry
    helm_cmd $upg istio-telemetry istio-telemetry $*

    # 1.1 policy
    helm_cmd install istio-policy istio-policy

    # TODO: test 1.0 policy and telemetry side-by-side
    # or install istio 1.0 in istio-system and install the rest on separate namespaces
}

# Upgrade or install the current and previous version of ingress.
function helm_ingress() {
    # upgrade or install or delete
    local upg=$1
    shift

    # TODO: customize test domains for each ingress namespace (move to separate function )

    # Normal 1.1 ingress. Defaults to istio-pilot11 control plane.
    helm_cmd $upg istio-ingress istio-ingress \
        --set domain=w11.istio.webinf.info \
        --values istio-ingress/hosts.yaml $*

    # 1.0 ingress. Uses istio-pilot10 control plane settings and version.
    helm_cmd $upg istio-ingress-10 istio-ingress --set global.tag=release-1.0-latest-daily \
        --set domain=w10.istio.webinf.info \
        --values istio-ingress/hosts.yaml $* \
        --set global.istioNamespace=istio-pilot10  \
        --set zvpn.enabled=false $*

    #helm_cmd $upg istio-ingress-12 --set global.tag=master-latest-daily \
    #    --set zvpn.suffix=v10.webinf.info $*

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
    kubectl create ns test
    kubectl label namespace test istio-injection=enabled

    kubectl create ns bookinfo
    kubectl label namespace bookinfo istio-injection=enabled


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
