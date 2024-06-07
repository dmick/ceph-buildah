#!/bin/bash -ex

CFILE=${1:-Containerfile}
shift || true

podman build --squash  -f $CFILE "${@}" 2>&1 | tee ${0}.out
# check error return of podman
if [[ ${PIPESTATUS[0]} -ne 0 ]] ; then exit ${PIPESTATUS[0]}; fi

image_id=$(tail -1 ${0}.out)

# grab useful image attributes for building the tag
#
# the variable settings are prefixed with "export CEPH_CONTAINER_" so that
# an eval or . can be used to put them into the environment
#
# PATH is removed from the output as it would cause problems for this
# parent script and its children
#
# notes:
#
# we want .Architecture and everything in .Config.Env
#
# printf will not accept "\n" (is this a podman bug?)
# so construct vars with two calls to podman inspect, joined by a newline,
# so that vars will get the output of the first command, newline, output
# of the second command
#
vars="$(podman inspect -f '{{printf "export CEPH_CONTAINER_ARCH=%v" .Architecture}}' ${image_id})
$(podman inspect -f '{{range $index, $value := .Config.Env}}export CEPH_CONTAINER_{{$value}}{{println}}{{end}}' ${image_id})"
vars="$(echo "${vars}" | grep -v PATH)"
eval ${vars}

# remove everything up to and including the last slash
from_lastelement=${CEPH_CONTAINER_FROM_IMAGE##*/}
# translate : to -
from_lastelement=${from_lastelement/:/-}
builddate=$(date +%Y%m%d)
podman tag ${image_id} daemon-base:${from_lastelement}-${CEPH_CONTAINER_CEPH_REF}-${CEPH_CONTAINER_ARCH}-${builddate}
