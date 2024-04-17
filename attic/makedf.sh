#!/bin/bash -e
# required args:
# CEPH_VERSION  alpha branchname/version string
# OSD_FLAVOR (crimson)
# EL_VERSION (8/9)
# CEPH_REF git branch (for shaman)

### todo
# conditional package lists for all the bits other than iscsi and ganesha
# final commit to image tag

function stderr() { printf "%s\n" "$*" >&2; }

# inputs
CEPH_VERSION=${CEPH_VERSION:-squid}
OSD_FLAVOR=${OSD_FLAVOR:-default}
EL_VERSION=${EL_VERSION:-9}
CEPH_REF=${CEPH_REF:-${CEPH_VERSIoN}}
GIT_BRANCH=${GIT_BRANCH:-${CEPH_VERSION}}
ARCH=x86_64
if [[ "${ARCH}" == "aarch64" ]] ; then ARCH="arm64"; fi
stderr "CEPH_VERSION=${CEPH_VERSION}"
stderr "OSD_FLAVOR=${OSD_FLAVOR}"
stderr "EL_VERSION=${EL_VERSION}"
stderr "CEPH_REF=${CEPH_REF}"
stderr "GIT_BRANCH=${GIT_BRANCH}"
stderr "ARCH=${ARCH}"

# XXX
DAEMON_BASE_TAG=ceph/daemon-base:${GIT_BRANCH}-el${EL_VERSION}-${OSD_FLAVOR}-${ARCH}
BASE_IMAGE=centos:stream${EL_VERSION}

. ./package-lists.txt

echo "FROM ${BASE_IMAGE} as work"


#======================================================
# Install ceph and dependencies, and clean up
#======================================================


echo "RUN yum install -y epel-release jq"

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
	echo "COPY ./ganesha.repo /etc/yum.repos.d/"
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
	echo "COPY ./tcmu-runner.repo ./ceph-iscsi.repo /etc/yum.repos.d/"
fi

echo "RUN yum update -y --setopt=install_weak_deps=False"
echo "RUN  rpm --import 'https://download.ceph.com/keys/release.asc'"

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

echo "RUN  rpm -Uvh $REPO_URL/noarch/ceph-release-1-${RELEASE_VER}.el${EL_VERSION}.noarch.rpm"

# scikit-learn, asyncssh
if [[ ${EL_VERSION} -eq 8 ]]; then
    echo "RUN  yum install -y dnf-plugins-core"
    echo "RUN  yum copr enable -y tchaikov/python-scikit-learn"
    echo "RUN  yum copr enable -y tchaikov/python3-asyncssh"
fi


# XXX this might vary, 8 to 9.  definitely varies depending on ganesha/iscsi/etc.
if [[ ${EL_VERSION} -eq 8 ]] ; then
	enable=powertools
else
	enable=crb
fi

#
# copr for CentOS 8stream's libprotobuf dependency (somehow EPEL8 supplies
# grpc-devel but not libprotobuf that it requires
#

if [[ ${EL_VERSION} -eq 8 ]] ; then
	echo "RUN  dnf copr enable -y ceph/grpc"
fi


echo "RUN  yum install -y --setopt=install_weak_deps=False --enablerepo=${enable} ${CEPH_BASE_PACKAGES}"

# Perform any final cleanup actions like package manager cleaning, etc.
stderr 'Postinstall cleanup'
echo "RUN rm -rf /usr/bin/hyperkube /usr/bin/etcd /usr/bin/systemd-analyze /usr/share/hwdata/{iab.txt,oui.txt} /etc/profile.d/lang.sh"
echo "RUN yum clean all"

echo "RUN sed -i -e 's/udev_rules = 1/udev_rules = 0/' -e 's/udev_sync = 1/udev_sync = 0/' -e 's/obtain_device_list_from_udev = 1/obtain_device_list_from_udev = 0/' /etc/lvm/lvm.conf"

echo "RUN mkdir -p /var/run/ganesha"

# Clean common files like /tmp, /var/lib, etc.
echo "RUN  rm -rf \
        /etc/{selinux,systemd,udev} \
        /lib/{lsb,udev} \
        /tmp/* \
        /usr/lib{,64}/{locale,systemd,udev,dracut} \
        /usr/share/{doc,info,locale,man} \
        /usr/share/{bash-completion,pkgconfig/bash-completion.pc} \
        /var/log/* \
        /var/tmp/*"
echo "RUN find  / -xdev -name "*.pyc" -o -name "*.pyo" -exec rm -f '{}' \;"

# ceph-dencoder is only used for debugging, compressing it saves 10MB
# If needed it will be decompressed
# TODO: Is ceph-dencoder safe to remove as rook was trying to do?
echo "RUN bash -c 'if [ -f /usr/bin/ceph-dencoder ] ; then gzip -9 /usr/bin/ceph-dencoder; fi'"

# TODO: What other ceph stuff needs removed/stripped/zipped here?
# Photoshop files inside a container ?
echo "RUN rm -f /usr/lib/ceph/mgr/dashboard/static/AdminLTE-*/plugins/datatables/extensions/TableTools/images/psd/*"

# Some logfiles are not empty, there is no need to keep them
echo "RUN  find /var/log/ -type f -exec truncate -s 0 '{}' \;"

# Verify that the packages installed haven't been accidentally cleaned
echo "RUN rpm -q ${CEPH_BASE_PACKAGES} && echo 'Packages verified successfully'"

echo "FROM scratch "
echo "COPY --from=work / /"

echo "ENV \
I_AM_IN_A_CONTAINER=1 \
CEPH_VERSION=main \
CEPH_POINT_RELEASE=\"\" \
CEPH_DEVEL=false \
CEPH_REF=main \
OSD_FLAVOR=${OSD_FLAVOR}"

echo "LABEL \
maintainer=\"Guillaume Abrioux <gabrioux@redhat.com>\" \
ceph=True \
RELEASE=CEPH_RELEASE \
GIT_REPO=git@github.com:ceph/ceph \
GIT_BRANCH=GITBRANCH \
GIT_COMMIT=38587130b387d65d30b4f151b8686954be7a21c1 \
GIT_CLEAN=True \
CEPH_POINT_RELEASE=\"\""

echo "EXPOSE 6789 6800 6801 6802 6803 6804 6805 80 5000"

stderr "now run:"
stderr "podman build -t ${DAEMON_BASE_TAG} ."
