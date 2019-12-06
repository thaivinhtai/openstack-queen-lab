#!/bin/bash
## Install Placement

function install_placement() {
    ##  Init config path
    local placement_conf=/etc/placement/placement.conf

    echocolor "Create DB for NOVA"
    cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS placement;

CREATE DATABASE placement;

GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'localhost' IDENTIFIED BY '$PLACEMENT_PASS';
GRANT ALL PRIVILEGES ON placement.* TO 'placement'@'%' IDENTIFIED BY '$PLACEMENT_PASS';

FLUSH PRIVILEGES;
EOF

    echocolor "Create the placement service credentials"
    openstack user create placement --domain default --password $PLACEMENT_PASS
    openstack role add --project service --user placement admin
    openstack service create --name placement --description "Placement API" placement

    echocolor "Create the Placement API service endpoints"
    openstack endpoint create --region ${REGION_NAME} \
            placement public http://$PUBLIC_FQDN_CTL:8778
    openstack endpoint create --region ${REGION_NAME} \
            placement internal http://$MGNT_FQDN_CTL:8778/
    openstack endpoint create --region ${REGION_NAME} \
            placement admin http://$MGNT_FQDN_CTL:8778/

    openstack endpoint create --region ${REGION_NAME} placement public http://$PUBLIC_FQDN_CTL:8778
    openstack endpoint create --region ${REGION_NAME} placement internal http://$MGNT_FQDN_CTL:8778
    openstack endpoint create --region ${REGION_NAME} placement admin http://$MGNT_FQDN_CTL:8778

    print_header "Install and configure components"
    print_install "Install Placement in $MGNT_FQDN_CTL"
    apt install placement-api

    backup_config $placement_conf

    rm -rf /var/log/placement/*

    print_header "Modify placement.conf"

    echocolor "Configure database access"

    ops_edit $placement_conf placement_database connection mysql+pymysql://placement:$PLACEMENT_PASS@$MGNT_FQDN_CTL/placement

    echocolor "Configure identity service access"
    ops_edit $placement_conf api auth_strategy keystone

    # ops_edit $placement_conf keystone_authtoken www_authenticate_url http://$MGNT_FQDN_CTL:5000
    ops_edit $placement_conf keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $placement_conf keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $placement_conf keystone_authtoken auth_type password
    ops_edit $placement_conf keystone_authtoken project_domain_name default
    ops_edit $placement_conf keystone_authtoken user_domain_name default
    ops_edit $placement_conf keystone_authtoken project_name service
    ops_edit $placement_conf keystone_authtoken username placement
    ops_edit $placement_conf keystone_authtoken password $PLACEMENT_PASS

    echocolor "Syncing Placement DB"

    su -s /bin/sh -c "placement-manage db sync" placement
    service apache2 restart

    print_header "Verify  Installation"
    placement-status upgrade check

    print_header "Install osc-placement plugin"
    pip install osc-placement

    print_header "List available resource classes and traits"
    openstack --os-placement-api-version 1.2 resource class list --sort-column name
}
