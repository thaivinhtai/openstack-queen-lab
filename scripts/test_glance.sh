#!/bin/bash

set -e

. admin-openrc

echo "Registering Cirros IMAGE for GLANCE"

openstack image create "cirros" \
    --file cirros-0.4.0-x86_64-disk.img \
    --disk-format qcow2 \
    --container-format bare \
    --public

#rm -f cirros-*-x86_64-disk.img
