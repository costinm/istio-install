#!/usr/bin/env bash


function pilot_install() {
    local ns=$1
    shift

    helm install -n $ns --namespace $ns subcharts/pilot  --set global.hub $HUB --set global.tag $TAG $*
}

function pilot_upgrade() {
    local ns=$1
    shift

    helm upgrade $ns helm/pilot --set global.hub $HUB --set global.tag $TAG $*
}

function install_gateway() {
    local ns=$1
    shift

    helm install -n $ns --namespace $ns subcharts/gateways  --set global.hub $HUB --set global.tag $TAG $*
}


function install_all() {
    HUB=istio TAG=1.0.3 pilot_install pilot103
    HUB=istio TAG=1.0.3 pilot_install pilot102

    install_gateway istio-gateway

    #HUB=istio TAG=110 pilot_install pilot110
    helm install -n fortio103 --namespace fortio103 helm/fortio

    kubectl create ns istio-system
    helm install istio -n istio-system --namespace istio-system \
        --set gateways.enabled=false

    kubectl create ns test
    kubectl label namespace test istio-injection=enabled

    kubectl -n test apply -f samples/httpbin/httpbin.yaml
    kubectl create ns bookinfo
    kubectl label namespace bookinfo istio-injection=enabled
    kubectl -n bookinfo apply -f samples/bookinfo/kube/bookinfo.yaml

}

function upgrade_all() {
    HUB=istio TAG=1.0.3 pilot_install pilot103
    HUB=istio TAG=1.0.3 pilot_install pilot102

    helm upgrade istio-system . --set gateways.enabled=false

    install_gateway istio-gateway

    #HUB=istio TAG=110 pilot_install pilot110
    helm install -n fortio103 --namespace fortio103 helm/fortio
}

function test_install() {
    helm upgrade istio-system install/kubernetes/helm/istio --set global.tag=$TAG \
        --set global.hub=$HUB
}
#/bin/bash



# Apply the helm template
function testApply() {
   local F=${1:-"istio/fortio:latest"}
   pushd $TOP/src/istio.io/istio
   helm -n test template \
    --set fortioImage=$F \
    tests/helm |kubectl -n test apply -f -
   popd
}

function testApply1() {
    testApply istio/fortio:1.0.1
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

function addCluster() {

}
