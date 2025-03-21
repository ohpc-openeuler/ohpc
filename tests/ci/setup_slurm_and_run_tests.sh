#!/bin/bash

set -x
set -e

USER=$1
shift

# First install slurm and needed packages
dnf -y install \
	autoconf \
	automake \
	make \
	which \
	sudo \
	slurm-slurmd-ohpc \
	slurm-slurmctld-ohpc \
	slurm-example-configs-ohpc \
	slurm-ohpc

# Install rebuilt packages (if any)
# shellcheck disable=SC2046 # (we want the words to be split)
dnf -y install prun-ohpc gnu12-compilers-ohpc openmpi4-gnu12-ohpc mpich-gnu12-ohpc $(find /home/"${USER}"/rpmbuild/RPMS/ -name "*rpm") || true

# Setup slurm
echo "127.0.0.1 node0 node1" >> /etc/hosts

cp /etc/slurm/slurm.conf.example /etc/slurm/slurm.conf

sed -i -e "
	s,SlurmdLogFile=.*$,SlurmdLogFile=/var/log/slurmd.%n.log,g; \
	s,SlurmdSpoolDir=.*$,SlurmdSpoolDir=/var/spool/slurmd.%n,g; \
	s,SlurmdPidFile=.*$,SlurmdPidFile=/var/run/slurmd.%n.pid,g; \
	s,JobCompType=jobcomp/none,,g; \
	s,ProctrackType=.*,ProctrackType=proctrack/linuxproc,g; \
	s,TaskPlugin=.*,TaskPlugin=task/none,g; \
	s,NodeName=.*$,,g; \
	s,PartitionName.*$,,g; \
	s,ReturnToService.*$,ReturnToService=2,g; \
	s,SlurmctldHost=.*$,SlurmctldHost=${HOSTNAME},g;" /etc/slurm/slurm.conf

{
	echo "NodeName=c0 NodeHostname=node0 Port=17004 CPUs=2"
	echo "NodeName=c1 NodeHostname=node1 Port=17005 CPUs=2"
	echo "PartitionName=normal Nodes=c0,c1 Default=YES MaxTime=24:00:00 State=UP"
} >> /etc/slurm/slurm.conf

# cgroupv2 support does not yet work in containers.
# Force cgroupv1 even on hosts with v2.
echo "CgroupPlugin=cgroup/v1" >  /etc/slurm/cgroup.conf

chown root.root /var/log/munge

/usr/sbin/munged -f
/usr/sbin/slurmctld
slurmd -N c0 || cat /var/log/slurm*
slurmd -N c1 || cat /var/log/slurm*

sinfo

retry_counter=0
max_retries=5

while true; do
	(( retry_counter+=1 ))
	if [ "${retry_counter}" -gt "${max_retries}" ]; then
		exit 1
	fi
	scontrol update nodename=c[0-1] state=idle && break
	sinfo

	# In case it is a network error let's wait a bit.
	echo "Retrying scontrol attempt ${retry_counter}"
	sleep "${retry_counter}"
done

srun -N2 hostname

# Figure out which tests we need to run.
# This script returns two array variables: PKGS and TESTS
# shellcheck disable=SC2068 # (we want individual elements)
eval "$(tests/ci/spec_to_test_mapping.py $@)"

if [ "${#PKGS[@]}" -gt 0 ]; then
	dnf -y install "${PKGS[@]}"
fi

export SIMPLE_CI=1

# Always running at least with '--enable-modules'. No need to check for
# an empty TESTS array.
sudo --user="${USER}" --preserve-env=SIMPLE_CI --login bash -c "cd ${PWD}/tests; ./bootstrap; ./configure --disable-all --enable-modules --enable-rms-harness --with-mpi-families='openmpi4 mpich' ${TESTS[*]}; make check"
