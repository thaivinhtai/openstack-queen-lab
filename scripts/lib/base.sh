#!/bin/nash

function install_crudini {
    print_install "Installing CRUDINI"
    apt-get -y install crudini
}

function install_openstack_client {
    print_install "Install openstack client"
    apt-get -y install python3-openstackclient
    # pip3 install python-openstackclient
}

function install_ntp {
    local path_chrony=/etc/chrony/chrony.conf

    print_install "Install and config NTP"
    apt-get -y install chrony
    backup_config $path_chrony

    if [ "$1" == "controller" ]; then
        CHRONY_NTP_SERVER=""

        for addr in $(echo $NTP_SERVER | tr " " "\n")
        do
            CHRONY_NTP_SERVER=${CHRONY_NTP_SERVER}'server '${addr}' iburst \\\n'
        done

        PATTERN=$(echo -e 's/__ntp_placeholder__/'$CHRONY_NTP_SERVER'/g')

        sed -i "s/pool ntp.ubuntu.com        iburst maxsources 4/__ntp_placeholder__/" $path_chrony
        sed -i '/ubuntu.pool.ntp.org iburst/d' $path_chrony
        sed -i "$PATTERN" $path_chrony
        echo 'allow 172.25.234.0/24' >> $path_chrony

    elif [ "$1" == "compute1" ] || [ "$1" == "compute2" ]; then
        sed -i "s/pool ntp.ubuntu.com        iburst maxsources 4/server $MGNT_FQDN_CTL iburst/g" $path_chrony

    fi

    service chrony restart
    systemctl enable chrony
    echocolor "Check NTP Server"
    chronyc sources
}

function install_database ()
{
    local my_conf=/etc/mysql/conf.d/99-openstack.cnf
    print_install "Install and Config MariaDB"
    echo "deb http://sgp1.mirrors.digitalocean.com/mariadb/repo/10.4/ubuntu/ bionic main" > /etc/apt/sources.list.d/mariadb.list
    apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
    apt-get update

    echo "mariadb-server-10.2 mysql-server/root_password password $MYSQL_PASS" | debconf-set-selections
    echo "mariadb-server-10.2 mysql-server/root_password_again password $MYSQL_PASS" | debconf-set-selections

    apt-get -y install mariadb-server python-pymysql
    echo '' > $my_conf

    systemctl stop mariadb.service
    rm -rf /var/lib/mysql/*
    mysql_install_db --user=mysql --basedir=/usr --datadir=/var/lib/mysql
    systemctl start mariadb.service
    systemctl enable mariadb.service

    ops_edit $my_conf mysqld bind-address 0.0.0.0
    ops_edit $my_conf mysqld default-storage-engine InnoDB
    ops_edit $my_conf mysqld innodb_file_per_table on
    ops_edit $my_conf mysqld max_connections 4096
    ops_edit $my_conf mysqld collation-server utf8_general_ci
    ops_edit $my_conf client default-character-set utf8
    ops_edit $my_conf mysqld character-set-server utf8
    ops_edit $my_conf mysqld innodb_strict_mode Off

    ops_edit $my_conf mysqld sql_mode TRADITIONAL
    ops_edit $my_conf mysqld max_connections 1024
    ops_edit $my_conf mysqld query_cache_type OFF
    ops_edit $my_conf mysqld query_cache_size 0

    echocolor "Restarting MYSQL"
    systemctl restart mariadb.service
    nc -nz 127.0.0.1 3306
    cat << EOF | mysql
GRANT ALL PRIVILEGES ON *.* TO 'root'@'%' IDENTIFIED BY '$MYSQL_PASS' WITH GRANT OPTION;
GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY '$MYSQL_PASS' WITH GRANT OPTION;
FLUSH PRIVILEGES;
EOF

}

function install_rabbitmq {
    print_install "Install and Config RabbitMQ"
    apt-get -y install rabbitmq-server

    service rabbitmq-server stop
    rm -rf /var/lib/rabbitmq/*
    rm -rf /var/lib/rabbitmq/*.*
    service rabbitmq-server start
    nc -nz 127.0.0.1 5672

    rabbitmqctl add_user openstack $RABBIT_PASS
    rabbitmqctl set_permissions openstack ".*" ".*" ".*"

    systemctl enable rabbitmq-server
}

function install_memcache {
    print_install "Install and Config Memcache"

    apt-get -y install memcached python-memcache
    backup_config /etc/memcached.conf
    sed -i "s/-l 127.0.0.1/-l 0.0.0.0/g" /etc/memcached.conf

    service memcached restart
    systemctl enable memcached.service

}

function install_etcd {
    systemctl stop etcd || true

    groupadd --system etcd
    useradd --home-dir "/var/lib/etcd" \
        --system \
        --shell /bin/false \
        -g etcd \
        etcd

    rm -rf /var/lib/etcd
    mkdir -p /etc/etcd
    chown etcd:etcd /etc/etcd
    mkdir -p /var/lib/etcd
    chown etcd:etcd /var/lib/etcd

    ETCD_VER=v3.2.7
    rm -rf /tmp/etcd && mkdir -p /tmp/etcd
    curl -L -C - https://github.com/coreos/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz -o /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz
    tar xzf /tmp/etcd-${ETCD_VER}-linux-amd64.tar.gz -C /tmp/etcd --strip-components=1
    cp /tmp/etcd/etcd /usr/bin/etcd
    cp /tmp/etcd/etcdctl /usr/bin/etcdctl

    cat << EOF > /etc/etcd/etcd.conf.yml
name: controller
data-dir: /var/lib/etcd
initial-cluster-state: 'new'
initial-cluster-token: 'etcd-cluster-01'
initial-cluster: controller=http://$CTL_MGNT_IP:2380
initial-advertise-peer-urls: http://$CTL_MGNT_IP:2380
advertise-client-urls: http://$CTL_MGNT_IP:2379
listen-peer-urls: http://0.0.0.0:2380
listen-client-urls: http://$CTL_MGNT_IP:2379
EOF

    cat << EOF > /lib/systemd/system/etcd.service
[Unit]
After=network.target
Description=etcd - highly-available key value store

[Service]
LimitNOFILE=65536
Restart=on-failure
Type=notify
ExecStart=/usr/bin/etcd --config-file /etc/etcd/etcd.conf.yml
User=etcd

[Install]
WantedBy=multi-user.target
EOF
    systemctl enable etcd
    systemctl start etcd
}
