#!/bin/bash
## Install GLANCE | Image service

function install_glance() {
    ##  Init config path
    local glanceapi_ctl=/etc/glance/glance-api.conf
    local glancereg_ctl=/etc/glance/glance-registry.conf

    ###############################################################################
    print_header "Create the database for GLANCE"

    cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS glance;
CREATE DATABASE glance;

GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCE_DBPASS';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCE_DBPASS';

FLUSH PRIVILEGES;
EOF

    print_header "Create user, endpoint for GLANCE"

    openstack user create glance --domain default --password $GLANCE_PASS
    openstack role add --project service --user glance admin
    openstack service create --name glance --description \
        "OpenStack Image service" image

    openstack endpoint create --region ${REGION_NAME} \
        image public http://$PUBLIC_FQDN_CTL:9292
    openstack endpoint create --region ${REGION_NAME} \
        image internal http://$MGNT_FQDN_CTL:9292
    openstack endpoint create --region ${REGION_NAME} \
        image admin http://$MGNT_FQDN_CTL:9292

    print_install "Install GLANCE"
    apt-get -y install python3-cinderclient
    apt-get -y install glance
    backup_config $glanceapi_ctl
    backup_config $glancereg_ctl

    rm -rf /var/lib/glance/*
    rm -rf /var/log/glance/*

    print_header "Configuring GLANCE API"
    # Configuring glance config file /etc/glance/glance-api.conf
    ## [database] section
    ops_edit $glanceapi_ctl database connection mysql+pymysql://glance:$GLANCE_DBPASS@$MGNT_FQDN_CTL/glance

    ## [keystone_authtoken] section
    ops_edit $glanceapi_ctl keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
    ops_edit $glanceapi_ctl keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $glanceapi_ctl keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $glanceapi_ctl keystone_authtoken auth_type password
    ops_edit $glanceapi_ctl keystone_authtoken project_domain_name default
    ops_edit $glanceapi_ctl keystone_authtoken user_domain_name default
    ops_edit $glanceapi_ctl keystone_authtoken project_name service
    ops_edit $glanceapi_ctl keystone_authtoken username glance
    ops_edit $glanceapi_ctl keystone_authtoken password $GLANCE_PASS

    ## [paste_deploy] section
    ops_edit $glanceapi_ctl paste_deploy flavor keystone

    ## [glance_store] section
    ops_edit $glanceapi_ctl glance_store stores file,http
    ops_edit $glanceapi_ctl glance_store default_store file
    ops_edit $glanceapi_ctl glance_store filesystem_store_datadir /var/lib/glance/images/

    #
    print_header "Configuring GLANCE REGISTRY"

    ## [DEFAULT] section
    #ops_edit $glancereg_ctl DEFAULT verbose true

    ## [database] section
    ops_edit $glancereg_ctl database connection mysql+pymysql://glance:$GLANCE_DBPASS@$MGNT_FQDN_CTL/glance
    #ops_del $glancereg_ctl database sqlite_db

    # [keystone_authtoken] section
    ops_edit $glancereg_ctl keystone_authtoken www_authenticate_uri http://$MGNT_FQDN_CTL:5000
    ops_edit $glancereg_ctl keystone_authtoken auth_url http://$MGNT_FQDN_CTL:5000
    ops_edit $glancereg_ctl keystone_authtoken memcached_servers $MGNT_FQDN_CTL:11211
    ops_edit $glancereg_ctl keystone_authtoken auth_type password
    ops_edit $glancereg_ctl keystone_authtoken project_domain_name default
    ops_edit $glancereg_ctl keystone_authtoken user_domain_name default
    ops_edit $glancereg_ctl keystone_authtoken project_name service
    ops_edit $glancereg_ctl keystone_authtoken username glance
    ops_edit $glancereg_ctl keystone_authtoken password $GLANCE_PASS

    # [paste_deploy] section
    ops_edit $glancereg_ctl paste_deploy flavor keystone

    echocolor "Populate the Image service database"
    su -s /bin/sh -c "glance-manage db_sync" glance

    echocolor "Restart the Image services"
    # service glance-registry restart
    # service glance-api restart
    service glance-* restart

    print_header "Verify operation"
    openstack image list
}
