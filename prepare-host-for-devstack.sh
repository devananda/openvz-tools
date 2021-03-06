#!/bin/bash

# Upload this script to a fresh nova instance and run it as root.
# Reboot the instance when this script finishes so the new kernel takes effect.

# Copyright (C) 2011-2012 OpenStack LLC.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
# implied.
#
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit

if [ $(whoami) != 'root' ]; then
   echo "Error: this script must be run as root."
   exit 1
fi

##################
# install custom kernel and openvz tools
##################

echo "Installing new kernel"

wget https://raw.github.com/devananda/openvz-tools/master/install-openvz-kernel.sh 2>/dev/null
chmod +x install-openvz-kernel.sh
./install-openvz-kernel.sh


##################
# adjust networking for openvz guests
##################

echo "Modifying sysctl.conf"

cat <<EOF >>/etc/sysctl.conf
net.ipv4.ip_forward = 1
net.ipv6.conf.default.forwarding = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.default.proxy_arp = 0
net.ipv4.conf.all.rp_filter = 1
kernel.sysrq = 1
net.ipv4.conf.default.send_redirects = 
EOF

##################
# set some ubuntu-specific options for openvz
##################

echo "Modifying vz.conf"

cat <<"EOF" >>/etc/vz/vz.conf
ADD_IP=debian-add_ip.sh
DEL_IP=debian-del_ip.sh
SET_HOSTNAME=debian-set_hostname.sh
SET_DNS=set_dns.sh
SET_USERPASS=set_userpass.sh
SET_UGID_QUOTA=set_ugid_quota.sh
POST_CREATE=postcreate.sh

# uncomment this block if your vz.conf file does not already specify this
#LOCKDIR=/var/lib/vz/lock
#TEMPLATE=/var/lib/vz/template
#VE_ROOT=/var/lib/vz/root/$VEID
#VE_PRIVATE=/var/lib/vz/private/$VEID
EOF

##################
# have openvz automatically add guests to the network bridge
# without this, guests will not have network access
##################

echo "Creating vps.mount script"

cat <<"EOF" >/etc/vz/conf/vps.mount
#!/bin/sh
# 
# Add virtual network interfaces (veth's) in a container to a bridge on CT0
# Modified from vznetaddbr script

CONFIGFILE=/etc/vz/conf/$VEID.conf
. $CONFIGFILE

NETIFLIST=$(printf %s "$NETIF" |tr ';' '\n')

if [ -z "$NETIFLIST" ]; then
   echo >&2 "According to $CONFIGFILE, CT$VEID has no veth interface configured."
   exit 1
fi

DEFAULT_BRIDGE=${DEFAULT_BRIDGE:-br100}
BRIDGE_TIMEOUT=${BRIDGE_TIMEOUT:-30}

{
for iface in $NETIFLIST; do
    bridge=
    host_ifname=

    for str in $(printf %s "$iface" |tr ',' '\n'); do
            case "$str" in
                bridge=*|host_ifname=*)
                eval "${str%%=*}=\${str#*=}" ;;
            esac
    done

    bridge=${bridge:-$DEFAULT_BRIDGE}
    timeleft=${timeleft:-$BRIDGE_TIMEOUT}

    while [ $timeleft -gt 0 ]; do
        /sbin/ifconfig $host_ifname >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            break
        fi
        timeleft=$((timeleft - 1))
        if [ $timeleft -eq 0 ]; then
            exit 1
        fi
        sleep 1
    done

    ip link set dev "$host_ifname" up
    ip addr add 0.0.0.0/0 dev "$host_ifname"
    echo 1 >"/proc/sys/net/ipv4/conf/$host_ifname/proxy_arp"
    echo 1 >"/proc/sys/net/ipv4/conf/$host_ifname/forwarding"
    brctl addif "$bridge" "$host_ifname"

    break
done
} &

exit 0
EOF

chmod +x /etc/vz/conf/vps.mount

##################
# create tun device if necessary
##################
[ ! -e /dev/net ] && mkdir /dev/net
[ ! -e /dev/net/tun ] && mknod /dev/net/tun c 10 200
/sbin/modprobe tun

##################
# fix directory permissions for the user running devstack
##################

echo "Creating 'vz' group and changing ownership of /var/lib/vz"

groupadd vz
usermod -a -G vz ubuntu 2>/dev/null || echo
usermod -a -G vz stack 2>/dev/null  || echo
cd /var/lib/vz/
chown -R :vz ./
chmod g+w *
chmod g+w template/cache

##################
# All done! 
# Reboot into new kernel now
##################

echo "Done preparing host for devstack + openvz"
echo "You should reboot into the new kernel now."

