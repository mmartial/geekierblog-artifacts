#!/bin/bash

# Adapt newprojectname
MY_PROJECT_ID=$(openstack project list | awk '/ newprojectname / {print $2}')
MY_SEC_GROUP=$(openstack security group list --project ${MY_PROJECT_ID} | awk '/ default / {print $2}')
# check values are assigned
if [ -z $MY_PROJECT_ID ] || [ -z $MY_SEC_GROUP ]; then
  echo "ERROR: issue with needed variables"
  exit 1
fi

openstack security group rule create --ingress --ethertype IPv4 --protocol icmp ${MY_SEC_GROUP}
openstack security group rule create --ingress --ethertype IPv4 --protocol tcp --dst-port 22 ${MY_SEC_GROUP}

openstack quota set --force --instances 10 ${MY_PROJECT_ID}
openstack quota set --force --cores 32 ${MY_PROJECT_ID}
openstack quota set --force --ram 96000 ${MY_PROJECT_ID}
openstack quota set --force --floating-ips 10 ${MY_PROJECT_ID}
