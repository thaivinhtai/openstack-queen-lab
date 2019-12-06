#!/bin/bash
## Install CINDER || Block Storage service

function install_cinder_controller() {
    local nova_conf=/etc/nova/nova.conf
    local cinder_conf=/etc/cinder/cinder.conf

    print_header "Create the database for CINDER"

    cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS cinder;
CREATE DATABASE cinder;

GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'localhost' IDENTIFIED BY '$CINDER_DBPASS';
GRANT ALL PRIVILEGES ON cinder.* TO 'cinder'@'%' IDENTIFIED BY '$CINDER_DBPASS';

FLUSH PRIVILEGES;
EOF

    print_header "Create user, endpoint for CINDER"

    openstack user create cinder --domain default --password $CINDER_PASS
    openstack role add --project service --user cinder admin
    openstack service create --name cinderv2 \
        --description "OpenStack Block Storage" volumev2
    openstack service create --name cinderv3 \
        --description "OpenStack Block Storage" volumev3

    openstack endpoint create --region ${REGION_NAME} \
        volumev2 public http://${PUBLIC_FQDN_CTL}:8776/v2/%\(project_id\)s
    openstack endpoint create --region ${REGION_NAME} \
        volumev2 internal http://${MGNT_FQDN_CTL}:8776/v2/%\(project_id\)s
    openstack endpoint create --region ${REGION_NAME} \
        volumev2 admin http://${MGNT_FQDN_CTL}:8776/v2/%\(project_id\)s

    openstack endpoint create --region ${REGION_NAME} \
        volumev3 public http://${PUBLIC_FQDN_CTL}:8776/v3/%\(project_id\)s
    openstack endpoint create --region ${REGION_NAME} \
        volumev3 internal http://${MGNT_FQDN_CTL}:8776/v3/%\(project_id\)s
    openstack endpoint create --region ${REGION_NAME} \
        volumev3 admin http://${MGNT_FQDN_CTL}:8776/v3/%\(project_id\)s

    print_install "Install CINDER"
    apt install -y cinder-api cinder-scheduler
    backup_config $cinder_conf
    rm -rf /var/log/cinder/*

    print_header "Configuring CINDER"
    # Configuring glance config file /etc/cinder/cinder.conf
    ## [database] section
    ops_edit $cinder_conf database connection mysql+pymysql://cinder:$CINDER_DBPASS@$MGNT_FQDN_CTL/cinder

    echocolor "Configure message queue access"
    ops_edit $cinder_conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$MGNT_FQDN_CTL

    ## [keystone_authtoken] section
    echocolor "Configure identity service access"
    ops_edit $cinder_conf DEFAULT auth_strategy keystone

    ops_edit $cinder_conf keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
    ops_edit $cinder_conf keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $cinder_conf keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $cinder_conf keystone_authtoken auth_type password
    ops_edit $cinder_conf keystone_authtoken project_domain_name default
    ops_edit $cinder_conf keystone_authtoken user_domain_name default
    ops_edit $cinder_conf keystone_authtoken project_name service
    ops_edit $cinder_conf keystone_authtoken username cinder
    ops_edit $cinder_conf keystone_authtoken password $CINDER_PASS

    ## In the [DEFAULT] section, configure the my_ip option to use the management interface IP address of the controller node
    ops_edit $cinder_conf DEFAULT my_ip $CTL_MGNT_IP

    # In the [oslo_concurrency] section, configure the lock path
    ops_edit $cinder_conf oslo_concurrency lock_path /var/lib/cinder/tmp

    # Populate the Block Storage database
    su -s /bin/sh -c "cinder-manage db sync" cinder

    print_header "Configure Compute to use Block Storage"
    ops_edit $nova_conf cinder os_region_name ${REGION_NAME}

    print_header "Finalize installation"
    service nova-api restart
    service cinder-scheduler restart
    service apache2 restart

    openstack volume service list
}

function install_cinder_node() {
    local lvm_conf=/etc/lvm/lvm.conf
    local cinder_conf=/etc/cinder/cinder.conf

    print_header "Install Cinder service"
    apt install -y lvm2 thin-provisioning-tools
    backup_config $lvm_conf

    pvcreate /dev/sdb
    vgcreate cinder-volumes /dev/sdb

    apt install -y cinder-volume
    backup_config $cinder_conf

    print_header "Configuring Cinder service"
    # Configuring glance config file /etc/cinder/cinder.conf
    ## [database] section
    ops_edit $cinder_conf database connection mysql+pymysql://cinder:$CINDER_DBPASS@$MGNT_FQDN_CTL/cinder

    echocolor "Configure message queue access"
    ops_edit $cinder_conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$MGNT_FQDN_CTL

    ## [keystone_authtoken] section
    echocolor "Configure identity service access"
    ops_edit $cinder_conf DEFAULT auth_strategy keystone

    ops_edit $cinder_conf keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
    ops_edit $cinder_conf keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $cinder_conf keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $cinder_conf keystone_authtoken auth_type password
    ops_edit $cinder_conf keystone_authtoken project_domain_name default
    ops_edit $cinder_conf keystone_authtoken user_domain_name default
    ops_edit $cinder_conf keystone_authtoken project_name service
    ops_edit $cinder_conf keystone_authtoken username cinder
    ops_edit $cinder_conf keystone_authtoken password $CINDER_PASS

    ## In the [DEFAULT] section, configure the my_ip option to use the management interface IP address of the controller node
    ops_edit $cinder_conf DEFAULT my_ip $CIN_MGNT_IP

    ops_edit $cinder_conf lvm volume_driver cinder.volume.drivers.lvm.LVMVolumeDriver
    ops_edit $cinder_conf lvm volume_group cinder-volumes
    ops_edit $cinder_conf lvm target_protocol iscsi
    ops_edit $cinder_conf lvm target_helper tgtadm

    ops_edit $cinder_conf DEFAULT enabled_backends lvm
    ops_edit $cinder_conf DEFAULT glance_api_servers http://${MGNT_FQDN_CTL}:9292

    # In the [oslo_concurrency] section, configure the lock path
    ops_edit $cinder_conf oslo_concurrency lock_path /var/lib/cinder/tmp

    print_header "Finalize installation"
    service tgt restart
    service cinder-volume restart
}

function install_cinder() {
    if [ "$1" == "controller" ]; then
        install_cinder_controller
    elif [ "$1" == "block1" ]; then
        install_cinder_node
    fi
}
