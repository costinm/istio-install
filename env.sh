#!/usr/bin/env bash

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
function helm_cmd() {
    local upg=$1
    shift
    local n=$1
    shift

    # --set global.tag=$TAG --set global.hub=$HUB

    if [ "$upg" == "upgrade" ] ; then
        helm upgrade $n $* --set debug=debug
    elif [ "$upg" == "delete" ] ; then
        helm delete --purge $n
        kubectl delete ns $n
    else
        helm install --namespace $n -n $n $*
    fi
}

# Components to install
function _helm_all() {
    # upgrade or install or delete
    local upg=$1
    shift

    helm_cmd $upg istio-pilot11 istio-control $*
    helm_cmd $upg istio-pilot10 istio-control --set global.tag=release-1.0-latest-daily $*

    helm_cmd $upg istio-egress istio-egress $*
    helm_cmd $upg istio-egresstest istio-egress --set global.tag=master-latest-daily \
        --set zvpn.suffix=v10.webinf.info $*

    helm_cmd $upg istio-ingress istio-ingress $*
    helm_cmd $upg istio-ingress-10 istio-ingress --set global.tag=release-1.0-latest-daily --set global.istioNamespace=istio-pilot10  \
        --set zvpn.enabled=false $*
    #helm_cmd $upg istio-ingress-12 --set global.tag=master-latest-daily \
    #    --set zvpn.suffix=v10.webinf.info $*

    helm_cmd $upg istio-telemetry istio-telemetry $*


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
    kubectl label ns fortio11 istio-injection=istio-sidecarinjector11

    kubectl create ns fortio10
    kubectl label ns fortio10 istio-injection=istio-sidecarinjector10
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

# Get a wildcard ACME cert. MUST BE CALLED BEFORE SETTING THE CNAME
function getCertLego() {
 # DNS_ZONE=istiotest
 #GCP_PROJECT=costin-istio
 # DNS_DOMAIN=istio.webinf.info
 gcloud iam service-accounts create dnsmaster
 gcloud projects add-iam-policy-binding $DNS_PROJECT  \
   --member "serviceAccount:dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com" \
   --role roles/dns.admin
 gcloud iam service-accounts keys create $HOME/.ssh/dnsmaster.json \
    --iam-account dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com

 gcloud dns record-sets list --zone istiotest

 GCE_SERVICE_ACCOUNT_FILE=~/.ssh/dnsmaster.json \
 GCE_PROJECT="$DNS_PROJECT"  \
 lego -a --email="dnsmaster@${DNS_PROJECT}.iam.gserviceaccount.com"  \
 --domains="*.istio.webinf.info"     \
 --dns="gcloud"     \
 --path="${HOME}/.lego"  run
}

