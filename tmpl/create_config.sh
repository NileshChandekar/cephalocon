#!/bin/bash

cat static.tmpl > envoy-config.yaml

echo -n 'Region1 Name(us-east-1): '
read region1
[ "${region1}" == "" ] && region1="us-east-1"
export region=${region1} 

cat listeners_secret.tmpl | envsubst >> envoy-config.yaml

echo -n 'Region2 Name(us-west-1): '
read region2
[ "${region2}" == "" ] && region2="us-west-1"
export region=${region2}

cat listeners_secret.tmpl | envsubst >> envoy-config.yaml

echo -n 'S3 Endpoint Port(443): '
read dstrport
[ "${dstrport}" == "" ] && dstrport="443"
echo -n 'S3 Endpoint fqdn(s3.example.com): '
read dstrfqdn
[ "${dstrfqdn}" == "" ] && dstrfqdn="s3.example.com"

export name=${dstrfqdn}
export port=${dstrport}

cat listeners.tmpl | envsubst >> envoy-config.yaml
cat virtualservice.tmpl | envsubst >> envoy-config.yaml

export region=${region1}
cat routes_dashboard.tmpl | envsubst >> envoy-config.yaml
cat routes.tmpl | envsubst >> envoy-config.yaml
export region=${region2}
cat routes_dashboard.tmpl | envsubst >> envoy-config.yaml
cat routes.tmpl | envsubst >> envoy-config.yaml

cat filters.tmpl >> envoy-config.yaml

export region=${region1}
cat listeners_tls.tmpl | envsubst >> envoy-config.yaml

cat clusters.tmpl >> envoy-config.yaml

echo -n "RGW (${region1}) endpoint(ceph1.example.com): "
read upfqdn1
[ "${upfqdn1}" == "" ] && upfqdn1="ceph1.example.com"
echo -n "RGW (${region2}) endpoint(ceph2.example.com): "
read upfqdn2
[ "${upfqdn2}" == "" ] && upfqdn2="ceph2.example.com"
echo -n "OpenPolicyAgent (all) endpoint(localhost): "
read opametrics
[ "${opametrics}" == "" ] && opametrics=$(hostname)

echo -n "RGW (all) endpoint port1(80): "
read upport1
[ "${upport1}" == "" ] && upport1="80"
echo -n "RGW (all) endpoint port2(81): "
read upport2
[ "${upport2}" == "" ] && upport2="81"
echo -n "RGW (all) dashboard port(8443): "
read upport3
[ "${upport3}" == "" ] && upport3="8443"
echo -n "OpenPolicyAgent (all) port(9191): "
read opaport
[ "${opaport}" == "" ] && opaport="9191"

export name="dashboard-${region1}"
cat cluster.tmpl | envsubst >> envoy-config.yaml

export port=${upport3}
export ip=$(host ${upfqdn1} | awk ' { print $NF } ')
cat endpoint.tmpl | envsubst >> envoy-config.yaml
cat cluster_tls.tmpl | envsubst >> envoy-config.yaml

export name="s3-rgw-${region1}"
cat cluster.tmpl | envsubst >> envoy-config.yaml

export name=${region1}
export port=${upport1}
cat endpoint.tmpl | envsubst >> envoy-config.yaml

export port=${upport2}
cat endpoint.tmpl | envsubst >> envoy-config.yaml

export name="dashboard-${region2}"
cat cluster.tmpl | envsubst >> envoy-config.yaml

export port=${upport3}
export ip=$(host ${upfqdn2} | awk ' { print $NF } ')
cat endpoint.tmpl | envsubst >> envoy-config.yaml
cat cluster_tls.tmpl | envsubst >> envoy-config.yaml

export name="s3-rgw-${region2}"
cat cluster.tmpl | envsubst >> envoy-config.yaml

export name=${region2}
export port=${upport1}
cat endpoint.tmpl | envsubst >> envoy-config.yaml

export port=${upport2}
cat endpoint.tmpl | envsubst >> envoy-config.yaml

export name="metrics-opa"
cat cluster_grpc.tmpl | envsubst >> envoy-config.yaml
export port=${opaport}
export ip=$(host ${opametrics} | awk ' { print $NF } ')
cat endpoint.tmpl | envsubst >> envoy-config.yaml
