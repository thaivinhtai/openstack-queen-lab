#!/bin/bash
## Install NOVA

function install_nova() {
    ##  Init config path
    local nova_conf=/etc/nova/nova.conf
    local novacom_conf=/etc/nova/nova-compute.conf

    if [ "$1" == "controller" ]; then
        echocolor "Create DB for NOVA"
        cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS nova_api;
DROP DATABASE IF EXISTS nova;
DROP DATABASE IF EXISTS nova_cell0;

CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;

GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_API_DBPASS';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_API_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$NOVA_DBPASS';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$NOVA_DBPASS';

FLUSH PRIVILEGES;
EOF

    fi

    if [ "$1" == "controller" ]; then
        echocolor "Create the Compute service credentials"
        openstack user create nova --domain default --password $NOVA_PASS
        openstack role add --project service --user nova admin
        openstack service create --name nova --description "OpenStack Compute" compute

        echocolor "Create the Compute API service endpoints"
        openstack endpoint create --region ${REGION_NAME} \
            compute public http://$PUBLIC_FQDN_CTL:8774/v2.1
        openstack endpoint create --region ${REGION_NAME} \
            compute internal http://$MGNT_FQDN_CTL:8774/v2.1
        openstack endpoint create --region ${REGION_NAME} \
            compute admin http://$MGNT_FQDN_CTL:8774/v2.1

        openstack user create --domain default --password $PLACEMENT_PASS placement
        openstack role add --project service --user placement admin
        openstack service create --name placement --description "Placement API" placement

        openstack endpoint create --region ${REGION_NAME} placement public http://$PUBLIC_FQDN_CTL:8778
        openstack endpoint create --region ${REGION_NAME} placement internal http://$MGNT_FQDN_CTL:8778
        openstack endpoint create --region ${REGION_NAME} placement admin http://$MGNT_FQDN_CTL:8778

    fi

    print_header "Install and configure components"
    if [ "$1" == "controller" ]; then
        print_install "Install NOVA in $MGNT_FQDN_CTL"
        apt-get -y install nova-api nova-conductor nova-novncproxy nova-scheduler

        backup_config $nova_conf

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ] ; then
        print_install "Install NOVA in $1"
        apt-get -y install nova-compute
        backup_config $novacom_conf

    fi

    rm -rf /var/log/nova/*

    print_header "Modify nova.conf"

    echocolor "Configure database access"
    if [ "$1" == "controller" ]; then
        ops_edit $nova_conf api_database connection mysql+pymysql://nova:$NOVA_API_DBPASS@$MGNT_FQDN_CTL/nova_api
        ops_edit $nova_conf database connection mysql+pymysql://nova:$NOVA_DBPASS@$MGNT_FQDN_CTL/nova

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ] ; then
        # Determine whether your compute node supports hardware acceleration for virtual machines
        # If this command returns a value of zero, your compute node does not support hardware acceleration and you must configure libvirt to use QEMU instead of KVM.
        # egrep -c '(vmx|svm)' /proc/cpuinfo | grep 0 && ops_edit $novacom_conf libvirt virt_type qemu
        ops_edit $novacom_conf libvirt virt_type qemu
    fi

    echocolor "Configure message queue access"
    ops_edit $nova_conf DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$MGNT_FQDN_CTL

    echocolor "Configure identity service access"
    ops_edit $nova_conf api auth_strategy keystone

    ops_edit $nova_conf keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $nova_conf keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $nova_conf keystone_authtoken auth_type password
    ops_edit $nova_conf keystone_authtoken project_domain_name default
    ops_edit $nova_conf keystone_authtoken user_domain_name default
    ops_edit $nova_conf keystone_authtoken project_name service
    ops_edit $nova_conf keystone_authtoken username nova
    ops_edit $nova_conf keystone_authtoken password $NOVA_PASS

    # configure the my_ip option to use the management interface IP address of the controller node
    if [ "$1" == "controller" ]; then
        ops_edit $nova_conf DEFAULT my_ip $CTL_MGNT_IP
        ops_edit $nova_conf scheduler discover_hosts_in_cells_interval 300

    elif [ "$1" == "compute1" ]; then
        ops_edit $nova_conf DEFAULT my_ip $COM1_MGNT_IP

    elif [ "$1" == "compute2" ]; then
        ops_edit $nova_conf DEFAULT my_ip $COM2_MGNT_IP
    fi

    ops_edit $nova_conf DEFAULT use_neutron True
    ops_edit $nova_conf DEFAULT firewall_driver nova.virt.firewall.NoopFirewallDriver

    echocolor "Configure the VNC proxy"
    ops_edit $nova_conf vnc enabled true
    if [ "$1" == "controller" ]; then
        ops_edit $nova_conf vnc server_listen \$my_ip
        ops_edit $nova_conf vnc server_proxyclient_address \$my_ip

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ] ; then
        ops_edit $nova_conf vnc server_listen 0.0.0.0
        ops_edit $nova_conf vnc server_proxyclient_address \$my_ip
        ops_edit $nova_conf vnc novncproxy_base_url http://$PUBLIC_FQDN_CTL:6080/vnc_auto.html
    fi

    ## In the [glance] section, configure the location of the Image service API
    ops_edit $nova_conf glance api_servers http://$PUBLIC_FQDN_CTL:9292

    ## In the [oslo_concurrency] section, configure the lock path
    ops_edit $nova_conf oslo_concurrency lock_path /var/lib/nova/tmp

    ## In the [placement] section, configure the Placement API
    ops_edit $nova_conf placement region_name ${REGION_NAME}
    ops_edit $nova_conf placement project_domain_name default
    ops_edit $nova_conf placement project_name service
    ops_edit $nova_conf placement auth_type password
    ops_edit $nova_conf placement user_domain_name default
    ops_edit $nova_conf placement auth_url http://$MGNT_FQDN_CTL:5000/v3
    ops_edit $nova_conf placement username placement
    ops_edit $nova_conf placement password $PLACEMENT_PASS

    if [ "$1" == "controller" ]; then
        echocolor "Syncing Nova DB"
        su -s /bin/sh -c "nova-manage api_db sync" nova
        su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova
        su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova
        su -s /bin/sh -c "nova-manage db sync" nova

        echocolor "Testing NOVA service"
        # service apache2 start
        # openstack compute service list
        nova-manage cell_v2 list_cells

        # service nova-api restart
        # service nova-scheduler restart
        # service nova-conductor restart
        # service nova-novncproxy restart
        service nova-* restart

        # openstack extension list --network
        # openstack compute service list
        # openstack catalog list
        # openstack image list
        # nova-status upgrade check

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ]; then
        echocolor "Restarting NOVA on $1"
        service nova-compute restart

        echocolor "Add the compute node to the cell database"
        echo 'Run the following commands on the controller node'
        echo 'su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova;'

    fi
}
