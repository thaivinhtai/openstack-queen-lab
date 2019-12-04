#!/bin/bash
## Install Keystone | Identity service

function install_keystone() {
  echocolor "Create Database for Keystone"

  cat << EOF | mysql -uroot -p$MYSQL_PASS
DROP DATABASE IF EXISTS keystone;
CREATE DATABASE keystone default character set utf8;

GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$KEYSTONE_DBPASS';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$KEYSTONE_DBPASS';

FLUSH PRIVILEGES;
EOF

  print_install "Install keystone"
  apt-get install -y keystone apache2 libapache2-mod-wsgi-py3

  print_header "Configure keystone"

  path_keystone=/etc/keystone/keystone.conf
  backup_config $path_keystone
  rm -rf /var/log/keystone/*

  # In the [database] section, configure database access
  ops_edit $path_keystone database connection mysql+pymysql://keystone:$KEYSTONE_DBPASS@$MGNT_FQDN_CTL/keystone
  # In the [token] section, configure the Fernet token provider
  ops_edit $path_keystone token provider fernet
  # Populate the Identity service database
  su -s /bin/sh -c "keystone-manage db_sync" keystone
  # Initialize Fernet key repositories
  keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
  keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

  print_header "Bootstrap the Identity service"
  keystone-manage bootstrap --bootstrap-password $CREDENTIALS_ADMIN_PASSWORD \
    --bootstrap-admin-url http://$MGNT_FQDN_CTL:5000/v3/ \
    --bootstrap-internal-url http://$MGNT_FQDN_CTL:5000/v3/ \
    --bootstrap-public-url http://$PUBLIC_FQDN_CTL:5000/v3/ \
    --bootstrap-region-id ${REGION_NAME}

  print_header "Configure the Apache HTTP server"
  cat /etc/apache2/apache2.conf | grep ServerName || echo "ServerName $PUBLIC_FQDN_CTL" >>  /etc/apache2/apache2.conf
  sed -i 's/ServerName .*/ServerName '$PUBLIC_FQDN_CTL'/g' /etc/apache2/apache2.conf

  systemctl start apache2
  systemctl restart apache2
  systemctl enable apache2

  print_header "Create a domain, projects, users, and roles"

  export OS_USERNAME=$CREDENTIALS_ADMIN_USERNAME
  export OS_PASSWORD=$CREDENTIALS_ADMIN_PASSWORD
  export OS_PROJECT_NAME=admin
  export OS_USER_DOMAIN_NAME=default
  export OS_PROJECT_DOMAIN_NAME=default
  export OS_AUTH_URL=http://$PUBLIC_FQDN_CTL:5000/v3
  export OS_IDENTITY_API_VERSION=3

  # Create the service project
  openstack project create --domain default \
    --description "Service Project" service

  # Create the user role
  openstack role create user

  print_header "Verify operation"

  unset OS_AUTH_URL OS_PASSWORD

  echocolor "Create OpenStack client environment scripts"

  # Create environment file
  cat << EOF > admin-openrc
export OS_PROJECT_DOMAIN_NAME=default
export OS_USER_DOMAIN_NAME=default
export OS_PROJECT_NAME=admin
export OS_USERNAME=${CREDENTIALS_ADMIN_USERNAME}
export OS_PASSWORD=${CREDENTIALS_ADMIN_PASSWORD}
export OS_AUTH_URL=http://$PUBLIC_FQDN_CTL:5000/v3
export OS_IDENTITY_API_VERSION=3
export OS_IMAGE_API_VERSION=2
EOF
  chmod +x admin-openrc

#   cat << EOF > ${CREDENTIALS_DEMO_USERNAME}-openrc
# export OS_PROJECT_DOMAIN_NAME=default
# export OS_USER_DOMAIN_NAME=default
# export OS_PROJECT_NAME=${CREDENTIALS_DEMO_USERNAME}
# export OS_USERNAME=${CREDENTIALS_DEMO_USERNAME}
# export OS_PASSWORD=${CREDENTIALS_DEMO_PASSWORD}
# export OS_AUTH_URL=http://$PUBLIC_FQDN_CTL:5000/v3
# export OS_IDENTITY_API_VERSION=3
# export OS_IMAGE_API_VERSION=2
# EOF
#   chmod +x ${CREDENTIALS_DEMO_USERNAME}-openrc

  echocolor "Verifying keystone"
  source admin-openrc
  openstack token issue
}
