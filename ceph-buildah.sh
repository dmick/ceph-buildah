#!/bin/bash -e 
# required args:
# CEPH_VERSION  alpha branchname/version string
# OSD_FLAVOR (crimson)
# EL_VERSION (8/9)
# CEPH_REF git branch (for shaman)

### todo 
# conditional package lists for all the bits other than iscsi and ganesha
# final commit to image tag

# inputs
CEPH_VERSION=${CEPH_VERSION:-main}
OSD_FLAVOR=${OSD_FLAVOR:-default}
EL_VERSION=${EL_VERSION:-9}
CEPH_REF=${CEPH_REF:-${CEPH_VERSION}}
GIT_BRANCH=${GIT_BRANCH:-${CEPH_VERSION}}
ARCH=$(arch)
if [[ "${ARCH}" == "aarch64" ]] ; then ARCH="arm64"; fi
echo "CEPH_VERSION=${CEPH_VERSION}"
echo "OSD_FLAVOR=${OSD_FLAVOR}"
echo "EL_VERSION=${EL_VERSION}"
echo "CEPH_REF=${CEPH_REF}"
echo "GIT_BRANCH=${GIT_BRANCH}"
echo "ARCH=${ARCH}"

set -x
DAEMON_BASE_TAG=ceph/daemon-base:${GIT_BRANCH}-${ARCH}
BASE_IMAGE=centos:stream${EL_VERSION}

working_container=work

. ./ceph-buildah-package-lists.txt

buildah rm ${working_container} || true

buildah from --name ${working_container} ${BASE_IMAGE}

buildah config --env I_AM_IN_A_CONTAINER=1 ${working_container}

# Who is the maintainer ?
buildah config --label maintainer="Guillaume Abrioux <gabrioux@redhat.com>" ${working_container}

# Is a ceph container ?
buildah config --label ceph="True" ${working_container}

# What is the actual release ? If not defined, this equals the git branch name
buildah config --label RELEASE="wip-c9-${working_container}-add-arm64" work

# What was the url of the git repository
buildah config --label GIT_REPO="git@github.com:ceph/ceph-container" ${working_container}

# What was the git branch used to build this container
buildah config --label GIT_BRANCH="wip-c9-${working_container}-add-arm64" work # What was the commit ID of the current HEAD
buildah config --label GIT_COMMIT="38587130b387d65d30b4f151b8686954be7a21c1" ${working_container}

# Was the repository clean when building ?
buildah config --label GIT_CLEAN="True" ${working_container}

# What CEPH_POINT_RELEASE has been used ?
buildah config --label CEPH_POINT_RELEASE="" ${working_container}

buildah config --env CEPH_VERSION=main ${working_container}
buildah config --env CEPH_POINT_RELEASE="" ${working_container}
buildah config --env CEPH_DEVEL=false ${working_container}
buildah config --env CEPH_REF=main ${working_container}
buildah config --env OSD_FLAVOR=default ${working_container}

#======================================================
# Install ceph and dependencies, and clean up
#======================================================

buildah config --port 6789 --port 6800 --port 6801 --port 6802 --port 6803 --port 6804 --port 6805 --port 80 --port 5000 ${working_container}

buildah run ${working_container} -- yum install -y epel-release jq

# construct optional repo files

# nfs-ganesha

if [[ "${CEPH_VERSION}" =~ master|main|reef|squid ]]; then
	BASEURL="https://buildlogs.centos.org/centos/\$releasever-stream/storage/\$basearch/nfsganesha-5/"
elif [[ "${CEPH_VERSION}" =~ quincy ]]; then
	BASEURL="https://buildlogs.centos.org/centos/\$releasever/storage/\$basearch/nfsganesha-4/"
elif [[ "${CEPH_VERSION}" == pacific ]]; then 
	BASEURL="https://download.ceph.com/nfs-ganesha/rpm-V3.5-stable/$CEPH_VERSION/el\$releasever/\$basearch/"
elif [[ "${CEPH_VERSION}" == octopus ]]; then 
	BASEURL="https://download.ceph.com/nfs-ganesha/rpm-V3.3-stable/$CEPH_VERSION/el\$releasever/\$basearch/"
elif [[ "${CEPH_VERSION}" == nautilus ]]; then
	BASEURL="https://download.ceph.com/nfs-ganesha/rpm-V2.8-stable/$CEPH_VERSION/\$basearch/"
else
	BASEURL="https://download.ceph.com/nfs-ganesha/rpm-V2.7-stable/$CEPH_VERSION/\$basearch/"
fi

GANESHA_REPO="[ganesha]
name=ganesha
baseurl=${BASEURL}
gpgcheck=0
enabled=1"


if [[ -n "${GANESHA_PACKAGES}" ]] ; then
	echo "${GANESHA_REPO}" > ./ganesha.repo
	buildah copy ${working_container} ./ganesha.repo /etc/yum.repos.d/
fi

# ceph-iscsi

TCMU_RUNNER_REPO_URL="https://shaman.ceph.com/api/repos/tcmu-runner/main/latest/centos/${EL_VERSION}/repo?arch=$(arch)"
if [[ "${CEPH_VERSION}" =~ main|master ]] ; then
	ISCSI_REPO_URL="https://shaman.ceph.com/api/repos/ceph-iscsi/main/latest/centos/${EL_VERSION}/repo"
elif [[ "${CEPH_VERSION}" =~ nautilus|octopus|pacific|quincy|reef|squid ]]; then
	ISCSI_REPO_URL="https://download.ceph.com/ceph-iscsi/3/rpm/el${EL_VERSION}/ceph-iscsi.repo"
else
	ISCSI_REPO_URL="https://download.ceph.com/ceph-iscsi/2/rpm/el${EL_VERSION}/ceph-iscsi.repo"
fi


if [[ -n "${ISCSI_PACKAGES}" ]] ; then
	curl -s -L -o ./tcmu-runner.repo "${TCMU_RUNNER_REPO_URL}"
	curl -s -L -o ./ceph-iscsi.repo "${ISCSI_REPO_URL}"
	buildah copy ${working_container} ./tcmu-runner.repo ./ceph-iscsi.repo /etc/yum.repos.d/
fi

buildah run ${working_container} yum update -y --setopt=install_weak_deps=False
buildah run ${working_container} rpm --import 'https://download.ceph.com/keys/release.asc'

# XXX idk wtf this is all about, but ignoring it because 'nautilus' for right now
#if [[ "${CEPH_VERSION}" == nautilus ]]; then \
#  CEPH_MGR_K8SEVENTS="ceph-mgr-k8sevents"; \
#  if [[ -n "" ]]; then \
#    CPR= ; \
#    if [[ ${CPR:1:2} -eq 14 ]] && [[ ${CPR:4:1} -eq 2 ]] && [[ ${CPR:6} -lt 5 ]]; then \
#      CEPH_MGR_K8SEVENTS="" ; \
#    fi ; \
#  fi ; \
#fi && \

if [[ ${CEPH_VERSION} =~ master|main ]] || ${CEPH_DEVEL}; then
	REPO_URL=$(curl -s "https://shaman.ceph.com/api/search/?project=ceph&distros=centos/${EL_VERSION}/${ARCH}&flavor=${OSD_FLAVOR}&ref=${CEPH_REF}&sha1=latest" | jq -r .[0].url)
	RELEASE_VER=0
else
	RELEASE_VER=1
        REPO_URL="http://download.ceph.com/rpm-${CEPH_VERSION}/el${EL_VERSION}"
fi

buildah run ${working_container} rpm -Uvh "$REPO_URL/noarch/ceph-release-1-${RELEASE_VER}.el${EL_VERSION}.noarch.rpm"

# scikit-learn, asyncssh
if [[ ${EL_VERSION} -eq 8 ]]; then
    buildah run ${working_container} yum install -y dnf-plugins-core
    buildah run ${working_container} yum copr enable -y tchaikov/python-scikit-learn
    buildah run ${working_container} yum copr enable -y tchaikov/python3-asyncssh
fi


# XXX this might vary, 8 to 9.  definitely varies depending on ganesha/iscsi/etc.
if [[ ${EL_VERSION} -eq 8 ]] ; then
	enable=powertools
else
	enable=crb
fi
buildah run ${working_container} yum install -y --setopt=install_weak_deps=False --enablerepo=${enable}  ${CEPH_BASE_PACKAGES}


INITIAL_SIZE=$(buildah run ${working_container} -- bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')

# Perform any final cleanup actions like package manager cleaning, etc.
echo 'Postinstall cleanup'
buildah run ${working_container} -- rm -rf "/usr/bin/hyperkube /usr/bin/etcd /usr/bin/systemd-analyze /usr/share/hwdata/{iab.txt,oui.txt} /etc/profile.d/lang.sh"
buildah run ${working_container} -- yum clean all

buildah run ${working_container} -- sed -i -e 's/udev_rules = 1/udev_rules = 0/' -e 's/udev_sync = 1/udev_sync = 0/' -e 's/obtain_device_list_from_udev = 1/obtain_device_list_from_udev = 0/' /etc/lvm/lvm.conf 

buildah run ${working_container} -- mkdir -p /var/run/ganesha
    
# Clean common files like /tmp, /var/lib, etc.
buildah run ${working_container} rm -rf \
        /etc/{selinux,systemd,udev} \
        /lib/{lsb,udev} \
        "/tmp/*" \
        "/usr/lib{,64}/{locale,systemd,udev,dracut}" \
        /usr/share/{doc,info,locale,man} \
        /usr/share/{bash-completion,pkgconfig/bash-completion.pc} \
        "/var/log/*" \
        "/var/tmp/*"
buildah run ${working_container} -- find  / -xdev -name "*.pyc" -o -name "*.pyo" -exec rm -f '{}' \;

# ceph-dencoder is only used for debugging, compressing it saves 10MB
# If needed it will be decompressed
# TODO: Is ceph-dencoder safe to remove as rook was trying to do?
buildah run ${working_container} -- bash -c "if [ -f /usr/bin/ceph-dencoder ] ; then gzip -9 /usr/bin/ceph-dencoder; fi"

# TODO: What other ceph stuff needs removed/stripped/zipped here?
# Photoshop files inside a container ?
buildah run ${working_container} -- rm -f /usr/lib/ceph/mgr/dashboard/static/AdminLTE-*/plugins/datatables/extensions/TableTools/images/psd/*

# Some logfiles are not empty, there is no need to keep them
buildah run ${working_container} -- find /var/log/ -type f -exec truncate -s 0 '{}' \;

# Report size savings (strip / from end)
FINAL_SIZE="$(buildah run ${working_container} -- bash -c 'sz="$(du -sm --exclude=/proc /)" ; echo "${sz%*/}"')"
REMOVED_SIZE=$((INITIAL_SIZE - FINAL_SIZE)) 

# Verify that the packages installed haven't been accidentally cleaned
buildah run ${working_container} -- rpm -q ${CEPH_BASE_PACKAGES} && echo 'Packages verified successfully'

echo "Cleaning process removed ${REMOVED_SIZE}MB"
echo "Dropped container size from ${INITIAL_SIZE}MB to ${FINAL_SIZE}MB"

buildah commit ${working_container} ${DAEMON_BASE_TAG}

