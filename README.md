# OpenStack Queens | Mini LAB

A small script used for deploy OpenStack Queens

Supported OS:
- Ubuntu Xenial 16.04 LTS
- Ubuntu Bionic Beaver 18.04 LTS

## Topology

![topo](./images/topo.png)

## Hardware requirements

![requirement_hardware](./images/requirement_hardware.png)

# Step 1: Network setup

Changing network interfaces name

Edit your /etc/default/grub changing the line from `GRUB_CMDLINE_LINUX=""` to `GRUB_CMDLINE_LINUX="net.ifnames=0 biosdevname=0"`
and, finally:

```sh
$ sudo update-grub
$ sudo reboot
```

## Ubuntu 16.04
Manual configure IP address for all node at `/etc/network/interfaces`

Example config

```
# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The management network
auto eth0
allow-hotplug eth0
iface eth0 inet dhcp

# The tenant / xvlan network
auto eth1
allow-hotplug eth1
iface eth1 inet static
    address 10.10.20.90
    netmask 255.255.255.0

# The provider / external network
auto eth2
allow-hotplug eth2
iface eth2 inet dhcp

```

## Ubuntu 18.04
Ubuntu 18.04 moved `/etc/network/interfaces` to netplan. You need update IP config at `/etc/netplan/*.yaml`

Example config `/etc/netplan/01-netcfg.yaml`

```
# This file describes the network interfaces available on your system
# For more information, see netplan(5).
network:
  version: 2
  renderer: networkd
  ethernets:
    eth0:
      dhcp4: yes
    eth1:
      addresses:
        - 10.10.20.90/24
    eth2:
      dhcp4: yes

```

Then execute `sudo netplan apply`

# Step 2: Install OpenStack
- Login to root user, Download git & and clone scripts

```sh
$ apt-get -y update && apt-get -y install git-core
$ git clone https://github.com/thaivinhtai/openstack-queen-lab.git /root/openstack
$ cd /root/openstack/scripts
$ chmod -R +x *.sh
```

- Generate new configuration file or use re-configure file at `out/vars`

```sh
$ cd scripts/
$ virtualenv -p python3 venv
$ . venv/bin/activate
$ pip install -r requirements.txt
$ python util/generate_config.py
```

## Controller

- SSH with `root` account and run scripts

```sh
$ source out/vars
$ ./setup01.sh
$ ./setup02.sh controller
$ ./setup03.sh controller
```

## Compute1 and Compute2

- SSH with `root` account and run scripts

```sh
$ source out/vars
$ ./setup01.sh
$ ./setup02.sh compute{n}
$ ./setup03.sh compute{n}
```

## Block

- SSH with `root` account and run scripts

```sh
$ source out/vars
$ ./setup01.sh
$ ./setup02.sh block1
$ ./setup03.sh block1
```

# Step 3: Test operation
## Create demo VMs
```sh
$ . admin-openrc
# Create Cirros images
$ ./test_glace.sh
# Create base network
$ ./test_neutron.sh

# Modify SECURITY_GROUP_ID match with current project
$ ./test_nova_provider_network.sh
$ ./test_nova_self_network.sh
```

## Login dashboad

- Dashboard: `http://<controller mngt IP>/horizon` or `http://${PUBLIC_FQDN_CTL}/horizon`
- User : `admin / admin`

## Check by command or dashboard

![console](./images/img1.png)
![web](./images/img2.png)

# Credit
Thanks to @congto https://github.com/congto/OpenStack-Newton-Scripts
Thanks to @PT Studio https://github.com/pt-studio/openstack-queens-labs.git

# License

```
Copyright 2018 PT Studio.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

   http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```
