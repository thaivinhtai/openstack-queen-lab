#!/bin/bash
# Print the commands being run so that we can see the command that triggers
# an error.  It is also useful for following along as the install occurs.
set -o xtrace
set -e

###############################################################################
## Init environment source
TOP_DIR=$(cd $(dirname "$0") && pwd)
source $TOP_DIR/lib/functions.sh

function add_openstack_repo {
    print_header "Enable the OpenStack Train repository"
    apt-get install -y software-properties-common
    add-apt-repository -y cloud-archive:train

    print_install "Upgrade the packages for server"
    apt-get -y update
    apt-get -y upgrade
    apt-get -y dist-upgrade
    apt-get install python3-pip
    apt-get clean
}

###############################################################################
### Pipeline
add_openstack_repo

print_success "Done"
