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

KERNEL_URL=${KERNEL_URL:-'http://15.185.168.213'}
KERNEL_BASE=${KERNEL_BASE:-'2.6.32'}
KERNEL_REV=${KERNEL_REV:-'042stab055.7~devstack'}
KERNEL_NAME="${KERNEL_BASE}-openvz_${KERNEL_REV}"

# do we need vzdump? it pulls in exim4 and many other packages
VZ_PACKAGES="vzctl vzquota"


# ###########################
# routines to do all our work

do_download() {
   echo "Downloading kernel packages..."
   if [ ! -f "linux-headers-${BUILD_NAME}_amd64.deb" ]; then
      wget -q "${KERNEL_URL}/linux-headers-${KERNEL_NAME}_amd64.deb" || \
         die "failed to download kernel headers"
   fi
   if [ ! -f "linux-image-${BUILD_NAME}_amd64.deb" ]; then
      wget -q "${KERNEL_URL}/linux-image-${KERNEL_NAME}_amd64.deb" || \
         die "failed to download kernel image"
   fi
   echo "... done"
}

do_install_kernel() { 
   echo "installing kernel ..."
   sudo dpkg -i linux-headers-${KERNEL_NAME}_amd64.deb linux-image-${KERNEL_NAME}_amd64.deb > install.log 2>&1 || \
      die "dpkg install of kernels failed"
   echo "... done"
}

do_update_grub() {
   echo "updating grub ..."

   # remove 3 linues from /etc/grub.d/10_linux to disable submenus in grub
   sed -n '1h;1!H;${;g;s/if \[ "$list" \] && ! $in_submenu; then\n.*in_submenu=:\n\s*fi/# submenu removed/g;p;}' \
      /etc/grub.d/10_linux > /tmp/10_linux || \
      die "failed to read /etc/grub.d/10_linux"
   ol=$(wc -l /etc/grub.d/10_linux | awk '{print $1}')
   nl=$(wc -l /tmp/10_linux | awk '{print $1}')
   if [ $(($ol - $nl)) -eq 3 ]; then
      sudo chown root:root /tmp/10_linux 
      sudo chmod 755 /tmp/10_linux
      sudo mv /tmp/10_linux /etc/grub.d/10_linux 
   else
      die "editing of /etc/grub.d/10_linux failed. Check temporary file /tmp/10_linux"
   fi

   # find our new kernel and make it default
   knum=$(grep menuentry /boot/grub/grub.cfg | grep -n openvz | grep -v 'recovery mode' | sed 's/^\([0-9]*\):.*/\1/')
   if [ ! $knum ]; then
      die "failed to identify index of new kernel"
   fi
   # menu entries start from index 0, so we need to subtract 1 from grep linenum
   knum=$(($knum - 1))
   sed "s/^GRUB_DEFAULT=[0-9]$/GRUB_DEFAULT=$knum/" /etc/default/grub > /tmp/grub
   sudo chown root:root /tmp/grub
   sudo chmod 644 /tmp/grub 
   sudo mv /tmp/grub /etc/default/grub 

   # rebuild /boot/grub/grub.cfg with our changes
   sudo update-grub > install.log 2>&1 || \
      die "updating grub failed. Check install.log"
   echo "... done"
}

do_install_extra_packages() {
   echo "Installing openvz packages..."
   sudo apt-get -q -y install $VZ_PACKAGES > install.log 2>&1 || \
      die "failed to install openvz packages: $VZ_PACKAGES"
   echo ".. done"
}

die() {
   echo "ERROR: $1"
   exit 1
}

# ###########################
# actually install things now

do_download
do_install_kernel
do_update_grub
do_install_extra_packages

echo "Finished!"
exit 0
