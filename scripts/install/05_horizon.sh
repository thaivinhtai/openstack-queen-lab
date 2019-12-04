#!/bin/bash
## Install HORIZON

function install_horizon() {
    local filehtml=/var/www/html/index.html
    local localcnf=/etc/openstack-dashboard/local_settings.py

    echocolor "Installing Dashboard package"
    apt-get -y install openstack-dashboard
    rm -rf /var/log/apache2/*

    backup_config $localcnf
    backup_config $filehtml

    echocolor "Creating redirect page"

    cat << EOF > $filehtml
<html>
<head>
<META HTTP-EQUIV="Refresh" Content="0.5; URL=http://$PUBLIC_FQDN_CTL/horizon">
</head>
<body>
<center> <h1>Redirecting to OpenStack Dashboard</h1> </center>
</body>
</html>
EOF

    # Configure the dashboard to use OpenStack services on the controller node
    # OPENSTACK_HOST = "controller"
    sed -i "s/OPENSTACK_HOST = .*/OPENSTACK_HOST = \'$MGNT_FQDN_CTL\'/g" $localcnf
    sed -i "s/127.0.0.1/$MGNT_FQDN_CTL/g" $localcnf
    # In the Dashboard configuration section, allow your hosts to access Dashboard
    # ALLOWED_HOSTS = ['one.example.com', 'two.example.com']
    # ALLOWED_HOSTS = ['*']

    # Configure the memcached session storage service
    cat $localcnf | grep SESSION_ENGINE || cat << EOF >> $localcnf
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'

CACHES = {
    'default': {
         'BACKEND': 'django.core.cache.backends.memcached.MemcachedCache',
         'LOCATION': 'controller:11211',
    }
}
EOF

    # Enable the Identity API version 3
    # OPENSTACK_KEYSTONE_URL = "http://%s:5000/v3" % OPENSTACK_HOST
    sed -i "s/http:\/\/\%s:5000\/v2.0/http:\/\/\%s:5000\/v3/g" $localcnf

    # Enable support for domains
    sed -i "s/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = .*/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/g" $localcnf

    # Configure API versions
    # cat << EOF >> $localcnf
    # OPENSTACK_API_VERSIONS = {
    # #    "data-processing": 1.1,
    #     "identity": 3,
    #     "volume": 2,
    #     "compute": 2,
    # }
    # EOF

    # Configure default as the default domain for users that you create via the dashboard
    sed -i "s/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = .*/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'Default'/g" $localcnf

    # Configure user as the default role for users that you create via the dashboard
    sed -i "s/OPENSTACK_KEYSTONE_DEFAULT_ROLE = .*/OPENSTACK_KEYSTONE_DEFAULT_ROLE = 'user'/g" $localcnf

    # Optionally, configure the time zone
    sed -i "s/TIME_ZONE = .*/TIME_ZONE = 'Asia\/Ho_Chi_Minh'/g" $localcnf
    sed -i "s/DEFAULT_THEME = .*/DEFAULT_THEME = 'default'/g" $localcnf

    # # Allowing insert password in dashboard ( only apply in image )
    sed -i "s/'can_set_password': False/'can_set_password': True/g" $localcnf
    sed -i "s/_member_/user/g" $localcnf

    sed -i "s/#OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = .*/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'Default'/g" $localcnf

    service apache2 restart

    print_success "Finish setting up Horizon"
    echocolor "LOGIN INFORMATION IN HORIZON"
    echocolor "URL: http://$PUBLIC_FQDN_CTL/horizon"
    echocolor "Admin user"
    echo "User:     $CREDENTIALS_ADMIN_USERNAME"
    echo "Password: $CREDENTIALS_ADMIN_PASSWORD"
    echocolor "Normal user"
    echo "User:     $CREDENTIALS_DEMO_USERNAME"
    echo "Password: $CREDENTIALS_DEMO_PASSWORD"
}
