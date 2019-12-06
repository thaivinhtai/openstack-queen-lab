#!/bin/bash
# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace
set -e

###############################################################################
## Init environment source
TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/lib/functions.sh
source $TOP_DIR/lib/base.sh

### Running function
### Checking and help syntax command
if [ $# -ne 1 ]; then
    echocolor  "STEP 2: Setup Environment"
    echo "Setup steps:"
    echo "    Install CrudIni"
    echo "    Install OpenStack client"
    echo "    Install NTP server"
    echo "    Install MariaDB 10.2"
    echo "    Install RabbitMQ"
    echo "    Install Memcached"
    echo "    Install Etcd"
    echo "Syntax command on"
    echo "    Controller: bash $0 controller"
    echo "    Compute{{N}}: bash $0 compute{{N}}"
    echo "    Block{{N}}: bash $0 block{{N}}"
    exit 1;
fi

if [ "$1" == "controller" ]; then
    install_crudini
    install_openstack_client
    install_ntp $1
    install_database
    install_rabbitmq
    install_memcache
    install_etcd

else
    install_crudini
    install_openstack_client
    install_ntp $1
fi

echocolor "Done, you can run next script"
