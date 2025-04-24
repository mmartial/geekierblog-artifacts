#!/usr/bin/env bash

# Adapted from init-runonce script

set -o errexit
set -o pipefail

# Avoid some issues, only valid for the local shell
unset LANG
unset LANGUAGE
LC_ALL=C
export LC_ALL

### USER CONF ###
# Specific to our network config
EXT_NET_CIDR='10.30.0.0/24'
EXT_NET_RANGE='start=10.30.0.100,end=10.30.0.199'
EXT_NET_GATEWAY='10.30.0.1'
## Quotas
# Max number of instances per project
CONF_QUOTA_INSTANCE=10
# Max number of floating IPs per project
CONF_QUOTA_FLOATIP=10
# Max number of cores per instance
CONF_QUOTA_CORE=32
# Max amount of MB of memory per instance (1000=1GB)
CONF_QUOTA_MEM=96000

# file locations
KOLLA_CONFIG_PATH=/etc/kolla
export OS_CLIENT_CONFIG_FILE=${KOLLA_CONFIG_PATH}/clouds.yaml
source /etc/kolla/admin-openrc.sh

#####
echo "--"; echo "--"; echo "-- Attempt to add external-net (if not already present)"
if openstack network list | grep -q external; then
   echo "external-net already specicied, skipping"
else
    openstack network create --external --provider-physical-network physnet1 --provider-network-type flat external-net
    openstack subnet create --no-dhcp --allocation-pool ${EXT_NET_RANGE} --network external-net --subnet-range ${EXT_NET_CIDR} --gateway ${EXT_NET_GATEWAY} external-subnet
fi
echo "-- network list"
openstack network list

#####
echo "--"; echo "--"; echo "-- Attempt to configure Security Groups: ssh and ICMP (ping)"
# Get admin user and tenant IDs
ADMIN_PROJECT_ID=$(openstack project list | awk '/ admin / {print $2}')
ADMIN_SEC_GROUP=$(openstack security group list --project ${ADMIN_PROJECT_ID} | awk '/ default / {print $2}')

# Default Security Group Configuration: ssh and ICMP (ping)
if openstack security group rule list ${ADMIN_SEC_GROUP} | grep -q "22:22"; then
    echo "a ssh rule is already in place, skipping"
else
    openstack security group rule create --ingress --ethertype IPv4 --protocol tcp --dst-port 22 ${ADMIN_SEC_GROUP}
fi
if openstack security group rule list ${ADMIN_SEC_GROUP} | grep -q icmp; then
    echo "an ICMP rule is already in place, skipping"
else
    openstack security group rule create --ingress --ethertype IPv4 --protocol icmp ${ADMIN_SEC_GROUP}
fi

#####
echo "--"; echo "--"; echo "-- Attempt to create and add a default id_ecdsa key to nova (if not already present)"
if [ ! -f ~/.ssh/id_ecdsa.pub ]; then
    echo Generating ssh key.
    ssh-keygen -t ecdsa -N '' -f ~/.ssh/id_ecdsa
fi
if [ -r ~/.ssh/id_ecdsa.pub ]; then
    if ! openstack keypair list | grep -q mykey; then
        echo Configuring nova public key.
        openstack keypair create --public-key ~/.ssh/id_ecdsa.pub mykey
    fi
fi

#####
echo "--"; echo "--"; echo "-- Setting quota defaults following user values"
openstack quota set --force --instances ${CONF_QUOTA_INSTANCE} ${ADMIN_PROJECT_ID}
openstack quota set --force --cores ${CONF_QUOTA_CORE} ${ADMIN_PROJECT_ID}
openstack quota set --force --ram ${CONF_QUOTA_MEM} ${ADMIN_PROJECT_ID}
openstack quota set --force --floating-ips ${CONF_QUOTA_FLOATIP} ${ADMIN_PROJECT_ID}
openstack quota show

#####
echo "--"; echo "--"; echo "-- Creating defaults flavors (instance type) (if not already present)"
if ! openstack flavor list | grep -q m1.tiny; then
    openstack flavor create --id 1 --ram 512 --disk 5 --vcpus 1 m1.tiny
    openstack flavor create --id 2 --ram 512 --disk 5 --vcpus 2 m2.tiny
    openstack flavor create --id 3 --ram 2048 --disk 20 --vcpus 2 m2.small
    openstack flavor create --id 4 --ram 4096 --disk 20 --vcpus 2 m2.medium
    openstack flavor create --id 5 --ram 8192 --disk 20 --vcpus 4 m4.large
    openstack flavor create --id 6 --ram 16384 --disk 20 --vcpus 8 m8.xlarge
    openstack flavor create --id 7 --ram 32768 --disk 20 --vcpus 16 m16.xxlarge
    openstack flavor create --id 8 --ram 65536 --disk 20 --vcpus 32 m32.xxxlarge
fi
echo ""; echo ""; echo "Done"

