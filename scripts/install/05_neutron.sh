#!/bin/bash
## Install NEUTRON

function init_nova_database() {
cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS neutron;
CREATE DATABASE neutron;

GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$NEUTRON_DBPASS';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$NEUTRON_DBPASS';

FLUSH PRIVILEGES;
EOF
}

function enable_net_bridge() {
    modprobe br_netfilter
    cat /etc/sysctl.conf | grep bridge-nf-call-iptables || echo 'net.bridge.bridge-nf-call-iptables=1' >> /etc/sysctl.conf
    cat /etc/sysctl.conf | grep bridge-nf-call-ip6tables || echo 'net.bridge.bridge-nf-call-ip6tables=1' >> /etc/sysctl.conf
    sysctl -p
}

function install_neutron() {
    ##  Init config path
    local neutron_ctl=/etc/neutron/neutron.conf
    local neutron_com=/etc/neutron/neutron.conf
    local nova_ctl=/etc/nova/nova.conf
    local nova_com=/etc/nova/nova.conf
    local netmetadata=/etc/neutron/metadata_agent.ini
    local ml2_clt=/etc/neutron/plugins/ml2/ml2_conf.ini
    local lbfile=/etc/neutron/plugins/ml2/linuxbridge_agent.ini
    local netdhcp=/etc/neutron/dhcp_agent.ini
    local netl3agent=/etc/neutron/l3_agent.ini

    enable_net_bridge

    if [ "$1" == "controller" ]; then
        rm -rf /var/log/neutron/*

        echocolor "Create DB for NEUTRON on $1 "

        init_nova_database

        echocolor "Create user, endpoint for NEUTRON"
        openstack user create neutron --domain default --password $NEUTRON_PASS
        openstack role add --project service --user neutron admin

        openstack service create --name neutron \
            --description "OpenStack Networking" network

        openstack endpoint create --region ${REGION_NAME} \
            network public http://$PUBLIC_FQDN_CTL:9696

        openstack endpoint create --region ${REGION_NAME} \
            network internal http://$MGNT_FQDN_CTL:9696

        openstack endpoint create --region ${REGION_NAME} \
            network admin http://$MGNT_FQDN_CTL:9696

        echocolor "Networking Option 2: Self-service networks"
        apt-get -y install neutron-server neutron-plugin-ml2 \
            neutron-linuxbridge-agent neutron-l3-agent neutron-dhcp-agent \
            neutron-metadata-agent

        backup_config $neutron_ctl
        backup_config $lbfile
        backup_config $netl3agent
        backup_config $netdhcp
        backup_config $netmetadata
        backup_config $ml2_clt

        echocolor "Configure the server component"

        ops_edit $neutron_ctl database connection mysql+pymysql://neutron:$NEUTRON_DBPASS@$MGNT_FQDN_CTL/neutron

        ops_edit $neutron_ctl DEFAULT core_plugin ml2
        ops_edit $neutron_ctl DEFAULT service_plugins router
        ops_edit $neutron_ctl DEFAULT allow_overlapping_ips true
        ops_edit $neutron_ctl DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$MGNT_FQDN_CTL
        ops_edit $neutron_ctl DEFAULT auth_strategy keystone

        ops_edit $neutron_ctl keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
        ops_edit $neutron_ctl keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
        ops_edit $neutron_ctl keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
        ops_edit $neutron_ctl keystone_authtoken auth_type password
        ops_edit $neutron_ctl keystone_authtoken project_domain_name default
        ops_edit $neutron_ctl keystone_authtoken user_domain_name default
        ops_edit $neutron_ctl keystone_authtoken project_name service
        ops_edit $neutron_ctl keystone_authtoken username neutron
        ops_edit $neutron_ctl keystone_authtoken password $NEUTRON_PASS

        ops_edit $neutron_ctl DEFAULT notify_nova_on_port_status_changes true
        ops_edit $neutron_ctl DEFAULT notify_nova_on_port_data_changes true
        ops_edit $neutron_ctl oslo_concurrency lock_path /var/lib/neutron/tmp

        ops_edit $neutron_ctl nova auth_url http://$MGNT_FQDN_CTL:5000
        ops_edit $neutron_ctl nova auth_type password
        ops_edit $neutron_ctl nova project_domain_name default
        ops_edit $neutron_ctl nova user_domain_name default
        ops_edit $neutron_ctl nova region_name ${REGION_NAME}
        ops_edit $neutron_ctl nova project_name service
        ops_edit $neutron_ctl nova username nova
        ops_edit $neutron_ctl nova password $NOVA_PASS

        echocolor "Configure the Modular Layer 2 (ML2) plug-in"
        ops_edit $ml2_clt ml2 type_drivers flat,vlan,vxlan
        ops_edit $ml2_clt ml2 tenant_network_types vxlan
        ops_edit $ml2_clt ml2 mechanism_drivers linuxbridge,l2population
        ops_edit $ml2_clt ml2 extension_drivers port_security
        ops_edit $ml2_clt ml2_type_flat flat_networks provider
        ops_edit $ml2_clt ml2_type_vxlan vni_ranges "1:1000"
        ops_edit $ml2_clt securitygroup enable_ipset true

        ops_edit $ml2_clt vxlan enable_vxlan true
        ops_edit $ml2_clt vxlan local_ip $CTL_DATA_IP
        ops_edit $ml2_clt vxlan l2_population true

        echocolor "Configure the Linux bridge agent"
        ops_edit $lbfile linux_bridge physical_interface_mappings provider:$EXT_INTERFACE

        # ops_edit $lbfile vxlan enable_vxlan false
        ops_edit $lbfile vxlan enable_vxlan true
        ops_edit $lbfile vxlan local_ip $CTL_DATA_IP
        ops_edit $lbfile vxlan l2_population true

        ops_edit $lbfile securitygroup enable_security_group true
        ops_edit $lbfile securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

        echocolor "Configure the layer-3 agent"
        ops_edit $netl3agent DEFAULT interface_driver linuxbridge

        echocolor "Configure the DHCP agent"
        ops_edit $netdhcp DEFAULT interface_driver linuxbridge
        ops_edit $netdhcp DEFAULT dhcp_driver neutron.agent.linux.dhcp.Dnsmasq
        ops_edit $netdhcp DEFAULT enable_isolated_metadata true

        echocolor "Configure the metadata agent"
        ops_edit $netmetadata DEFAULT nova_metadata_host $MGNT_FQDN_CTL
        ops_edit $netmetadata DEFAULT metadata_proxy_shared_secret $METADATA_SECRET

        echocolor "Configure the Compute service to use the Networking service"
        ops_edit $nova_ctl neutron url http://$MGNT_FQDN_CTL:9696
        ops_edit $nova_ctl neutron auth_url http://$MGNT_FQDN_CTL:5000
        ops_edit $nova_ctl neutron auth_type password
        ops_edit $nova_ctl neutron project_domain_name default
        ops_edit $nova_ctl neutron user_domain_name default
        ops_edit $nova_ctl neutron region_name ${REGION_NAME}
        ops_edit $nova_ctl neutron project_name service
        ops_edit $nova_ctl neutron username neutron
        ops_edit $nova_ctl neutron password $NEUTRON_PASS
        ####
        ops_edit $nova_ctl neutron service_metadata_proxy true
        ops_edit $nova_ctl neutron metadata_proxy_shared_secret $METADATA_SECRET

        su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
            --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron
        service nova-api restart
        sleep 1
        service neutron-server restart
        service neutron-linuxbridge-agent restart
        service neutron-dhcp-agent restart
        service neutron-metadata-agent restart
        service neutron-l3-agent restart

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ]; then
        apt-get install -y neutron-linuxbridge-agent
        backup_config $neutron_com
        backup_config $lbfile

        ops_edit $neutron_com DEFAULT transport_url rabbit://openstack:$RABBIT_PASS@$MGNT_FQDN_CTL
        ops_edit $neutron_com DEFAULT auth_strategy keystone

        # ## [database] section
        #ops_del $neutron_com database connection
        ops_edit $neutron_com database connection mysql+pymysql://neutron:$NEUTRON_DBPASS@$MGNT_FQDN_CTL/neutron

        ## [keystone_authtoken] section
        ops_edit $neutron_com keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
        ops_edit $neutron_com keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
        ops_edit $neutron_com keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
        ops_edit $neutron_com keystone_authtoken auth_type password
        ops_edit $neutron_com keystone_authtoken project_domain_name default
        ops_edit $neutron_com keystone_authtoken user_domain_name default
        ops_edit $neutron_com keystone_authtoken project_name service
        ops_edit $neutron_com keystone_authtoken username neutron
        ops_edit $neutron_com keystone_authtoken password $NEUTRON_PASS

        ops_edit $neutron_com oslo_concurrency lock_path /var/lib/neutron/tmp

        echocolor "Configuring linuxbridge_agent"
        # [linux_bridge] section
        ops_edit $lbfile linux_bridge physical_interface_mappings provider:$EXT_INTERFACE

        # [vxlan] section
        ops_edit $lbfile vxlan enable_vxlan true

        if [ "$1" == "compute1" ]; then
            ops_edit $lbfile vxlan local_ip $COM1_DATA_IP

        elif [ "$1" == "compute2" ]; then
            ops_edit $lbfile vxlan local_ip $COM2_DATA_IP
        fi

        ops_edit $lbfile vxlan l2_population true

        # [securitygroup] section
        ops_edit $lbfile securitygroup enable_security_group true
        ops_edit $lbfile securitygroup firewall_driver neutron.agent.linux.iptables_firewall.IptablesFirewallDriver

        print_header "Configure the Compute service to use the Networking service"
        ops_edit $nova_com neutron url http://$MGNT_FQDN_CTL:9696
        ops_edit $nova_com neutron auth_url http://$MGNT_FQDN_CTL:5000
        ops_edit $nova_com neutron auth_type password
        ops_edit $nova_com neutron project_domain_name default
        ops_edit $nova_com neutron user_domain_name default
        ops_edit $nova_com neutron region_name ${REGION_NAME}
        ops_edit $nova_com neutron project_name service
        ops_edit $nova_com neutron username neutron
        ops_edit $nova_com neutron password $NEUTRON_PASS

        print_header "Restarting NEUTRON service"
        service nova-compute restart
        service neutron-linuxbridge-agent restart
        service neutron-linuxbridge-cleanup restart
    fi
}
