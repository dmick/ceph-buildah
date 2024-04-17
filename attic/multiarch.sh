#!/bin/bash -ex

BRANCH=main
daemon_base_tag() {
	branch=$1
	arch=$2
	if [[ -n "$arch" ]] ; then 
		echo 'ceph/daemon-base:$branch-$arch'
	else
		echo 'ceph/daemon-base:$branch'
	fi
}


#podman manifest create $(daemon_base_tag ${BRANCH} "") $(daemon_base_tag ${BRANCH} "amd64") $(daemon_base_tag ${BRANCH} "arm64")

# podman manifest create remote-multiarchname remote-amd64name remote-arm64name
# podman manifest push remote-multiarchname docker://remote-multiarchname 
