#!/bin/bash

# shellcheck disable=SC2086

set -x
set -e

FACTORY_VERSION=2.7

if [ ! -e /etc/os-release ]; then
	echo "Cannot detect OS without /etc/os-release"
	exit 1
fi

# shellcheck disable=SC1091
. /etc/os-release

PKG_MANAGER=zypper
COMMON_PKGS="wget python3"

retry_counter=0
max_retries=5

loop_command() {
	local retry_counter=0
	local max_retries=5

	while true; do
		(( retry_counter+=1 ))
		if [ "${retry_counter}" -gt "${max_retries}" ]; then
			exit 1
		fi
		# shellcheck disable=SC2068
		$@ && break

		# In case it is a network error let's wait a bit.
		echo "Retrying attempt ${retry_counter}"
		sleep "${retry_counter}"
	done
}


for like in ${ID_LIKE}; do
	if [ "${like}" = "fedora" ]; then
		PKG_MANAGER=dnf
		break
	fi
done


if [ "${ID}" = "openEuler" ]; then
	PKG_MANAGER=dnf
	FACTORY_VERSION=
fi


if [ "${PKG_MANAGER}" = "dnf" ]; then
	if [ "${ID}" = "openEuler" ]; then
		OHPC_RELEASE="http://121.36.3.168:82/home:/huangtianhua:/ohpc/standard_$(uname -m)/$(uname -m)/ohpc-release-2-1.oe2203.ohpc.2.0.0.$(uname -m).rpm"
	else
		# We need to figure out if we are running on RHEL (clone) 8 or 9 and
		# rpmdev-vercmp from rpmdevtools is pretty good at comparing versions.
		loop_command "${PKG_MANAGER}" -y  install rpmdevtools crypto-policies-scripts "${COMMON_PKGS}"

		# Exit status is 0 if the EVR's are equal, 11 if EVR1 is newer, and 12 if EVR2
		# is newer.  Other exit statuses indicate problems.
		set +e
		rpmdev-vercmp 9 "${VERSION_ID}"
		if [ "$?" -eq "11" ]; then
			OHPC_RELEASE="http://repos.openhpc.community/OpenHPC/2/CentOS_8/x86_64/ohpc-release-2-1.el8.x86_64.rpm"
		else
			# This is our RHEL 9 pre-release repository
			loop_command wget http://obs.openhpc.community:82/home:/adrianr/CentOS9/home:adrianr.repo -O /etc/yum.repos.d/ohpc-pre-release.repo
			# The OBS signing key is too old
			update-crypto-policies --set LEGACY
			NINE=1
		fi
		set -e
	fi
else
	OHPC_RELEASE="http://repos.openhpc.community/OpenHPC/2/Leap_15/x86_64/ohpc-release-2-1.leap15.x86_64.rpm"
fi

if [ "${FACTORY_VERSION}" != "" ]; then
	FACTORY_REPOSITORY=http://obs.openhpc.community:82/OpenHPC:/"${FACTORY_VERSION}":/Factory/
	if [ "${PKG_MANAGER}" = "dnf" ]; then
		if [ -z "${NINE}" ]; then
			FACTORY_REPOSITORY="${FACTORY_REPOSITORY}EL_8"
		else
			FACTORY_REPOSITORY="${FACTORY_REPOSITORY}EL_9"
		fi
		FACTORY_REPOSITORY_DESTINATION="/etc/yum.repos.d/obs.repo"
	else
		FACTORY_REPOSITORY="${FACTORY_REPOSITORY}Leap_15"
		FACTORY_REPOSITORY_DESTINATION="/etc/zypp/repos.d/obs.repo"
	fi
	FACTORY_REPOSITORY="${FACTORY_REPOSITORY}/OpenHPC:${FACTORY_VERSION}:Factory.repo"
fi

if [ "${PKG_MANAGER}" = "dnf" ]; then
	if [ "${ID}" = "openEuler" ]; then
		loop_command "${PKG_MANAGER}" -y install ${COMMON_PKGS} openEuler-release dnf-plugins-core git rpm-build gawk "${OHPC_RELEASE}"
	else
		loop_command "${PKG_MANAGER}" -y install ${COMMON_PKGS} epel-release dnf-plugins-core git rpm-build gawk "${OHPC_RELEASE}"
		if [ -z "${NINE}" ]; then
			loop_command "${PKG_MANAGER}" config-manager --set-enabled powertools
			loop_command "${PKG_MANAGER}" config-manager --set-enabled devel
		else
			loop_command "${PKG_MANAGER}" config-manager --set-enabled crb
		fi
	fi
	if [ "${FACTORY_VERSION}" != "" ]; then
		loop_command wget "${FACTORY_REPOSITORY}" -O "${FACTORY_REPOSITORY_DESTINATION}"
	fi
	loop_command "${PKG_MANAGER}" -y install lmod-ohpc
	adduser ohpc
else
	loop_command "${PKG_MANAGER}" -n install ${COMMON_PKGS} awk rpmbuild
	loop_command "${PKG_MANAGER}" -n --no-gpg-checks install "${OHPC_RELEASE}"
	if [ "${FACTORY_VERSION}" != "" ]; then
		loop_command wget "${FACTORY_REPOSITORY}" -O "${FACTORY_REPOSITORY_DESTINATION}"
	fi
	loop_command "${PKG_MANAGER}" -n --no-gpg-checks install lmod-ohpc
	useradd -m ohpc
fi
