#!/bin/bash

#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

# If you created an OpenVZ-enabled Ubuntu kernel using create-openvz-kernel.sh
# then use this script to install the kernel packages, related openvz tools,
# and invoke them all on the next boot


# ############
# set defaults

# try to auto-detect the latest version from openvz
OPENVZ_BASE_URL="http://ftp.openvz.org/kernel/branches"
KERNELINFO["ovzbranch"]="rhel6-2.6.32-testing"
DEFAULT_VER="042stab055.7"
CURRENT_VER=$(curl $OPENVZ_BASE_URL/rhel6-2.6.32-testing/current/patches/ 2>/dev/null | grep .gz.asc | sed 's/.*patch-\(.*\)-combined.gz.asc.*/\1/')
if [ "$CURRENT_VER" ]; then
   CURRENT_VER="${CURRENT_VER}"
else
   CURRENT_VER=''
   echo "NOTE: failed to auto-detect current version of kernel from openvz.org"
   echo "NOTE: defaulting to $DEFAULT_VER"
   CURRENT_VER="${DEFAULT_VER}"
fi

KERNEL_URL=${KERNEL_URL:-'http://15.185.168.213'}
KERNEL_BASE=${KERNEL_BASE:-'2.6.32'}
KERNEL_REV=${KERNEL_REV:-$CURRENT_VER}
KERNEL_NAME=${KERNEL_NAME:-"${KERNEL_BASE}-openvz-${KERNEL_REV}_${KERNEL_REV}~devstack"}

# do we need vzdump? it pulls in exim4 and many other packages
VZ_PACKAGES="vzctl vzquota"

# we also need to install an older version of rsyslog
# new versions eat CPU with this kernel 
# see bug: https://bugs.launchpad.net/ubuntu/+source/rsyslog/+bug/523610
RSYSLOG_URL=${RSYSLOG_URL:-'http://mirror.netcologne.de/ubuntu/pool/main/r/rsyslog/'}
RSYSLOG_PACKAGE=${RSYSLOG_PACKAGE:-'rsyslog_4.2.0-2ubuntu8_amd64.deb'}

# ###########################
# routines to do all our work

do_download() {
   echo "Downloading kernel packages..."
   if [ ! -f "linux-headers-${KERNEL_NAME}_amd64.deb" ]; then
      wget -q "${KERNEL_URL}/linux-headers-${KERNEL_NAME}_amd64.deb" || \
         die "failed to download kernel headers"
   fi
   if [ ! -f "linux-image-${KERNEL_NAME}_amd64.deb" ]; then
      wget -q "${KERNEL_URL}/linux-image-${KERNEL_NAME}_amd64.deb" || \
         die "failed to download kernel image"
   fi
   echo "... done"
}

do_install_kernel() { 
   echo "installing kernel ..."
   sudo dpkg -i linux-headers-${KERNEL_NAME}_amd64.deb linux-image-${KERNEL_NAME}_amd64.deb >> install.log 2>&1 || \
      die "dpkg install of kernels failed"
   echo "... done"
}

do_remove_kernels() {
   echo "Removing previous kernels..."
   klist=$(dpkg-query --list 'linux-image*' | grep -P '^ii\s*linux-image' | grep -v "${KERNEL_NAME}" | awk '{print $2}')
   hlist=$(dpkg-query --list 'linux-headers' | grep -P '^ii\s*linux-headers' | grep -v "${KERNEL_NAME}" | awk '{print $2}')

   for k in $klist $hlist
   do
      sudo dpkg --remove $k >> install.log 2>&1 || \
         die "dpkg failed to remove package $k"
   done
}

do_disable_grub_submenu() {
   echo "Disabling grub submenus..."
   # remove 3 linues from /etc/grub.d/10_linux to disable submenus in grub
   sed  -n '1h;1!H;${;g;s/if \[ "$list" \] && ! $in_submenu; then\n.*in_submenu=:\n\s*fi/# submenu removed/g;p;}' \
      /etc/grub.d/10_linux > /tmp/10_linux || \
      die "failed to read /etc/grub.d/10_linux"
   ol=$(wc -l /etc/grub.d/10_linux | awk '{print $1}')
   nl=$(wc -l /tmp/10_linux | awk '{print $1}')
   if [ $(($ol - $nl)) -eq 3 ]; then
      sudo chown root:root /tmp/10_linux 
      sudo chmod 755 /tmp/10_linux
      sudo mv /tmp/10_linux /etc/grub.d/10_linux 
   elif  [ $(($ol - $nl)) -eq 0 ]; then
      echo "... submenus previously disabled. Not changing /etc/grub.d/10_linux"
   else
      die "editing of /etc/grub.d/10_linux failed. Check temporary file /tmp/10_linux"
   fi
}

do_update_grub() {
   echo "Updating grub ..."

   # find our new kernel and make it default
   knum=$(grep menuentry /boot/grub/grub.cfg | grep -n "openvz-${KERNEL_REV}" | grep -v 'recovery mode' | sed 's/^\([0-9]*\):.*/\1/')
   if [ ! $knum ]; then
      die "failed to identify index of new kernel"
   fi
   # menu entries start from index 0, so we need to subtract 1 from grep linenum
   knum=$(($knum - 1))
   sudo sed -i "s/^GRUB_DEFAULT=[0-9]$/GRUB_DEFAULT=$knum/" /etc/default/grub

   # rebuild /boot/grub/grub.cfg with our changes
   sudo update-grub >> install.log 2>&1 || \
      die "updating grub failed. Check install.log"
   echo "... done"
}

do_install_extra_packages() {
   echo "Installing openvz packages..."
   sudo apt-get -q -y install $VZ_PACKAGES >> install.log 2>&1 || \
      die "failed to install openvz packages: $VZ_PACKAGES"
   echo "... done"

   echo "Installing rsyslog fix..."
   wget -q $RSYSLOG_URL/$RSYSLOG_PACKAGE -O /tmp/$RSYSLOG_PACKAGE || \
      die "failed to donwload rsyslog"
   sudo dpkg -i /tmp/$RSYSLOG_PACKAGE >> install.log 2>&1 || \
      die "failed to install rsyslog"
   sudo bash -c 'echo rsyslog hold | dpkg --set-selections' || \
      die "failed to pin rsyslog version"
   echo "... done"

}

die() {
   echo "ERROR: $1"
   exit 1
}

# ###########################
# actually install things now

do_download
do_install_kernel
#do_remove_kernels
do_disable_grub_submenu
do_update_grub
do_install_extra_packages

echo "Finished!"
exit 0
