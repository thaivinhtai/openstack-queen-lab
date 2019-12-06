#!/bin/bash
# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace
set -e

###############################################################################
## Init environment source
TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/lib/functions.sh

### Running function
### Checking and help syntax command
if [ $# -ne 1 ]; then
    echocolor  "STEP 3: Install OpenStack service"
    echo "Syntax command on"
    echo "    Controller: bash $0 controller"
    echo "    Compute{{N}}: bash $0 compute{{N}}"
    echo "    Block{{N}}: bash $0 block{{N}}"
    exit 1;
fi

if [ "$1" == "controller" ]; then
    # Core service
    source $TOP_DIR/install/01_keystone.sh
    source $TOP_DIR/install/02_glance.sh
    source $TOP_DIR/install/03_placement.sh
    source $TOP_DIR/install/04_nova.sh
    source $TOP_DIR/install/05_neutron.sh

    install_keystone
    install_glance
    install_placement
    install_nova $1
    install_neutron $1

    # Additional service
    source $TOP_DIR/install/07_cinder.sh
    install_cinder $1
    source $TOP_DIR/install/06_horizon.sh
    install_horizon

elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ]; then
    source $TOP_DIR/admin-openrc
    source $TOP_DIR/install/03_nova.sh
    source $TOP_DIR/install/04_neutron.sh

    install_nova $1
    install_neutron $1

elif [ "$1" == "block1" ]; then
    source $TOP_DIR/install/06_cinder.sh
    install_cinder $1

else
    echo "Unknown node"
    exit 1
fi
