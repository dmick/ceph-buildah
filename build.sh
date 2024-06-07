#!/bin/bash -ex

CFILE=${1:-Containerfile}
shift || true

podman build --squash  -f $CFILE "${@}" 2>&1 | tee ${0}.out
image_id=$(tail -1 ${0}.out)

# inspect notes:
# we want .Architecture and everyting in .Config.Env
# printf will not accept "\n" (is this a podman bug?)
# so construct vars with two calls to podman inspect, joined by a newline,
# so that vars will get the output of the first command, newline, output
# of the second command
#
# PATH is removed from the output as it would cause problems for this
# parent script and its children
#
# the variable settings are prefixed with "export CEPH_CONTAINER_" so that
# an eval or . can be used to put them into the environment

vars="$(podman inspect -f '{{printf "export CEPH_CONTAINER_ARCH=%v" .Architecture}}' ${image_id})
$(podman inspect -f '{{range $index, $value := .Config.Env}}export CEPH_CONTAINER_{{$value}}{{println}}{{end}}' ${image_id})"
vars="$(echo "${vars}" | grep -v PATH)"
eval ${vars}

# remove everything up to and including the last slash
from_part=${CEPH_CONTAINER_FROM_IMAGE##*/}
# translate : to -
from_part=${from_part/:/-}
podman tag ${image_id} daemon-base:${from_part}-${CEPH_CONTAINER_CEPH_REF}-${CEPH_CONTAINER_ARCH}
