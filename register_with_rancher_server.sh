#! /bin/bash -e

# Register with Rancher server

# Inputs:

# $CATTLE_HOST_LABELS
# $RANCHER_AGENT_TAG

: "${RANCHER_AGENT_REMOVE_STATE:=false}"
: "${RANCHER_HOST_EXTERNAL_DNS_IP:=}"

# export proxy if on system level
. /etc/profile.d/*proxy* > /dev/null 2>&1 || true
export http_proxy
export https_proxy
export no_proxy

# https://github.com/rancher/rancher/issues/1370
# Note that due this bug you may need to action the following if
# receiving 401 Unauthorized we a previously registered host:
if [ "$RANCHER_AGENT_REMOVE_STATE" = 'true' ]; then
  sudo rm -Rf /var/lib/rancher/state
fi

# currently, we keep this fairly old so auto rancher-agent upgrades
# should always bump up easily to the required version according to the server
: "${RANCHER_AGENT_TAG:=v1.0.2}"

# currently we assume the device name will always reside in the 5th column
iface=$(ip route | awk '/default/ { print $5 }')

# we do this because currently (-rwx--x--x 1 root root)
private_ip=`ifconfig $iface | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*'`

env=$(sudo cat /var/spool/rancher/registration.sh)
eval "$env"

# pre-add in the external DNS label if provided
if [ ! -z "$RANCHER_HOST_EXTERNAL_DNS_IP" ]; then
  CATTLE_HOST_LABELS="$CATTLE_HOST_LABELS&io.rancher.host.external_dns_ip=$RANCHER_HOST_EXTERNAL_DNS_IP"
fi

if [ ! -z "$CATTLE_HOST_LABELS" ]; then
  labels=(${CATTLE_HOST_LABELS//&/ })

  echo 'Labels will be added with registration of host:'
  for label in "${labels[@]}"
  do
    echo "    $label"
  done
  cattle_labels="-e CATTLE_HOST_LABELS=$CATTLE_HOST_LABELS"
fi

if [ ! -z $http_proxy ]; then
  http_proxy="-e http_proxy=$http_proxy"
fi

if [ ! -z $https_proxy ]; then
  https_proxy="-e https_proxy=$https_proxy"
fi

if [ ! -z $no_proxy ]; then
  no_proxy="-e NO_PROXY=$no_proxy -e no_proxy=$no_proxy"
fi

# this used to be used in the docker run command below but is not
# required for the rancher-agent and infra services in modern times
# http://rancher.com/docs/rancher/v1.6/en/hosts/custom/#hosts-behind-a-proxy
# make sure your dockerd is configured properly for a forward proxy (if needed)
proxies="$http_proxy $https_proxy $no_proxy"

# support for a static host entry, rancher.localdomain
if grep rancher.localdomain /etc/hosts > /dev/null 2>&1; then
  add_host="--add-host rancher.localdomain:$(grep rancher.localdomain /etc/hosts | cut -d' ' -f1)"
fi

echo 'Running rancher/agent container.'

set -x

sudo docker run \
  --rm --privileged \
  -e CATTLE_AGENT_IP="${private_ip}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /var/lib/rancher:/var/lib/rancher \
  $add_host \
  $cattle_labels \
    "rancher/agent:$RANCHER_AGENT_TAG" \
    "$CATTLE_URL/scripts/$CATTLE_REGISTRATION_SECRET_KEY"

{ set +x; } 2>/dev/null

echo 'Done.'
