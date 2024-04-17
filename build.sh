#!/bin/bash -ex

CFILE=${1:-Containerfile}

image_id=$(podman build --squash -q -f $CFILE)

# jq notes:
# inspect outputs an array, always? of len 1
# collect .Architecture and all of .Config.Env except PATH into an array
# sort it and output each element
# thus we have a list of variable setting statements
vars="$(podman inspect ${image_id} | jq -r '.[] | ["ARCH=\(.Architecture)", .Config.Env[] | select(startswith("PATH=") | not)] | sort | .[]')"
echo "${vars}"
eval ${vars}

podman tag ${image_id} daemon-base:${CEPH_REF}-${ARCH}
