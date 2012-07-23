#!/bin/bash

# This script builds an openvz-enabled debian kernel package
# for Ubuntu 11.04, 11.10, and 12.04, using the OpenVZ RHEL patches.
# Note that this script needs a specific version of GCC, 
# which is only present in Ubutu 11.10 (Oneiric).

#  Forked from https://github.com/CoolCold/tools/blob/master/openvz/kernel/create-ovz-kernel-for-debian.sh
#              https://github.com/CoolCold/tools/commit/02540e1894fec1015296981f72324540088e2ade
#  Original copyright  (C) 2012, Roman Ovchinnikov, coolthecold@gmail.com

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


declare -A opts
declare -A KERNELINFO

# ----------
# Edit these options to suit your needs, or specify on cmd-line.
# 
# buildir base
BUILDDIR="/mnt/build"
# default name for kernel
LOCALNAME="devstack"
# kernel.org url
KERNEL_BASE_URL="http://www.kernel.org/pub/linux/kernel/v2.6"
# 
# openvz.org url
OPENVZ_BASE_URL="http://ftp.openvz.org/kernel/branches"
# 
KERNELINFO["base"]="2.6.32"
KERNELINFO["ovzbranch"]="rhel6-2.6.32-testing"
KERNELINFO["arch"]="x86_64"

# try to auto-detect the latest version from openvz
CURRENT_VER=$(curl $OPENVZ_BASE_URL/${KERNELINFO["ovzbranch"]}/current/patches/ 2>/dev/null | grep .gz.asc | sed 's/.*patch-\(.*\)-combined.gz.asc.*/\1/')

# fall back to a known good version otherwise
KERNELINFO["ovzname"]=${CURRENT_VER:-"042stab055.7"}

# 
# Sample file URLs, for reference.
# We build these based on the options given above.
# http://www.kernel.org/pub/linux/kernel/v2.6/linux-2.6.32.tar.bz2
# http://ftp.openvz.org/kernel/branches/rhel6-2.6.32-testing/042stab055.7/patches/patch-042stab055.7-combined.gz
# http://ftp.openvz.org/kernel/branches/rhel6-2.6.32-testing/042stab055.7/configs/config-2.6.32-042stab055.7.x86_64
# 
# ----------
# You should not need to edit anything below this line
# ----------

NEEDPACKAGES="build-essential kernel-package fakeroot gcc-4.4"
NEEDRELEASE='11.10'

PROGNAME=$(basename $0)

print_usage() {
    echo "Usage: $PROGNAME [-h] [-s] [-B <base>] [-O <ovzname>] [-b <ovzbranch>] [-A <arch>] [-L <localname>] [-D <builddir>]"
    echo ""
    echo "-h - show this help"
    echo "-s - skip installing prerequisites (useful for non-sudo environment)"
    echo "-B <base>      - specifies base (vanilla) kernel version to use.   Default: ${KERNELINFO['base']}"
    echo "-O <ovzname>   - specifies version for openvz kernel patch.        Default: ${KERNELINFO['ovzname']}"
    echo "-b <ovzbranch> - specifies branch name in openvz repo.             Default: ${KERNELINFO['ovzbranch']}"
    echo "-L <localname> - specifies string appended to package.             Default: $LOCALNAME"
    echo "-D <builddir>  - specifies local build directory.                  Default: $BUILDDIR"
    echo "-A <arch>      - specifies processor architecture to use. Don't change this."
    echo ""
    echo "Most default options should be sane, but you may want to change <localname> anyway."
}

print_help() {
    echo "$PROGNAME"
    echo ""
    print_usage
    echo ""
    echo "This script builds OpenVZ kernel packages on Ubuntu Oneiric"
    echo "by downloading a base kernel from kernel.org and patches from openvz.org"
}

show_opts() {
    echo "The next options will be used for building kernel"
    for i in "base" "ovzname" "ovzbranch" "arch" "localname" "builddir"; do
        echo "$i: ${opts[$i]}"
    done
}

# saving arguments count
argcount=$#

while getopts ":hsB:O:R:b:A:L:D:" Option; do
  case $Option in
    h)
      print_help
      exit 0
      ;;
    s)
      ops["skip"]=1
      ;;
    B)
      opts["base"]="${OPTARG}"
      ;;
    O)
      opts["ovzname"]="${OPTARG}"
      ;;
    b)
      opts["ovzbranch"]="${OPTARG}"
      ;;
    A)
      opts["arch"]="${OPTARG}"
      ;;
    L)
      opts["localname"]="${OPTARG}"
      if [ "$(echo ${opts['localname']} | sed 's/[0-9a-zA-Z+.~]//g')" != '' ]; then
         echo "ERROR: Invalid package name specified. Only letters, digits and characters '-+._' allowed."
         exit 1
      fi
      ;;
    D)
      opts["builddir"]="${OPTARG}"
      ;;
    *)
      print_help
      exit 2
      ;;
  esac
done
shift $(($OPTIND - 1))

for i in "base" "ovzname" "ovzbranch" "arch"; do
    opts[$i]=${opts[$i]:-${KERNELINFO[$i]}}
done
opts["localname"]=${opts["localname"]:-${LOCALNAME}}
opts["builddir"]=${opts["builddir"]:-${BUILDDIR}}

# simplify variables  based on options given
kernel_name="linux-${opts["base"]}"
patch_filename="patch-${opts["ovzname"]}-combined"
patch_url="${OPENVZ_BASE_URL}/${opts["ovzbranch"]}/${opts["ovzname"]}/patches/$patch_filename.gz"
config_filename="config-${opts["base"]}-${opts["ovzname"]}.${opts["arch"]}"
config_url="${OPENVZ_BASE_URL}/${opts["ovzbranch"]}/${opts["ovzname"]}/configs/$config_filename"


# check ubuntu release. Must be oneiric (11.10)
release=$(lsb_release -r | awk '{print $2}')
if [ "$NEEDRELEASE" != "$release" ]; then
    c=$(lsb_release -c | awk '{print $2}')
    echo "ERROR: Kernel must be built on Ubuntu oneiric (11.10)."
    echo "ERROR: This host appears to be Ubuntu $c ($release)."
    exit 1
fi

# check build dir exists and is writable
if [ ! -d ${opts["builddir"]} -o ! -w ${opts["builddir"]} ]; then
    echo "ERROR: Build directory ${opts["builddir"]} does not exist."
    exit 1
fi
if [ ! -w ${opts["builddir"]} ]; then
    echo "ERROR: Build directory ${opts["builddir"]} is not writable."
    exit 1
fi

# make sure build requirements are met, installing them if necessary
do_exit=
if [ ! ${opts["skip"]} ]; then
    echo "installing requirements..."

    sudo apt-get -y -qq update  || do_exit=${do_exit:-1}
    sudo apt-get -y -qq upgrade || do_exit=${do_exit:-1}
    sudo apt-get -y -qq install $NEEDPACKAGES || do_exit=${do_exit:-1}

    if [ $do_exit ]; then
        echo "ERROR: installing prereq's failed. Exiting now."
        exit 1
    else
        echo "... done"
    fi
fi

# do extra check for GCC 4.4.6
gcc-4.4 --version | grep '4.4.6' >/dev/null 2>&1 || do_exit=${do_exit:-1}
if [ $do_exit ]; then
    echo "ERROR: wrong version of gcc installed. Need 4.4.6."
    exit 1
fi

# giving user time to think a bit
if [[ $argcount -lt 1 ]]; then
    show_opts
    echo -e "\n\n"
    echo "No parameters were specified, build will start in 10 seconds with settings from above. Press Ctrl+C to stop bulding or Enter to start"
    read -t 10 || true
fi

############ here we go #########
echo "Changing directory to ${opts["builddir"]} ..."
cd ${opts["builddir"]}

# need to download compressed kernel image if it doesn't exist yet
if ! [ -f "$kernel_name.tar.bz2" ]; then
    echo "Downloading kernel tarball..."
    wget -q "${KERNEL_BASE_URL}/${kernel_name}.tar.bz2" -O "${kernel_name}.tar.bz2"
    if [ $? -ne 0 ]; then
        echo "ERROR: Download kernel tarball from $urltoget failed, exiting"
        exit 1
    fi
else
    echo "kernel tarball $kernel_name.tar.bz2 already exists, skipping download"
fi

# clearing old build directory, just in case
if [ -d "./${kernel_name}" ]; then
    echo "removing old dir ./${kernel_name}"
    rm -rf "./${kernel_name}"
    if [ $? -ne 0 ]; then
        echo "ERROR: remove failed, exiting"
        exit 1
    fi
fi

# unpacking archive
echo "Decompressing kernel tarball..."
tar -xf "${kernel_name}.tar.bz2"
if [ $? -ne 0 ]; then
    echo "ERROR: unpacking kernel tarball failed, exiting"
    exit 1
fi

# downloading config
if ! [ -f "$config_filename" ]; then
    echo "Downloading openvz kernel config..."
    wget -q "$config_url" -O "$config_filename"
    if [ $? -ne 0 ]; then
        echo "ERROR: download config from $config_url failed, exiting"
        exit 1
    fi
else
    echo "config file $config_filename already exists, skipping download"
fi

# downloading patch
if ! [ -f "$patch_filename" ]; then
    echo "Downloading openvz kernel patchset..."
    wget -q "$patch_url" -O "$patch_filename.gz"
    if [ $? -ne 0 ]; then
        echo "ERROR: download patch from $patch_url failed, exiting"
        exit 1
    fi
    gzip -d "$patch_filename"
    if [ $? -ne 0 ]; then
        echo "ERROR: unzip of patch failed, exiting"
        exit 1
    fi
 
else
    echo "patch file $patch_filename already exists, skipping download"
fi

# everything is downloaded, patching now
cd ${kernel_name}

# dry run for patch
echo "testing patch before applying..."
patch --dry-run --verbose -p1 < "${opts["builddir"]}/$patch_filename" > ${opts["builddir"]}/patch.log
if [ $? -ne 0 ]; then
    echo "ERROR: patch failed to apply cleanly. See ${opts["builddir"]}/patch.log"
    exit 1
fi

# checking if patch has failed hunks
fgrep -q 'FAILED at' "${opts["builddir"]}/patch.log"
if [ $? -eq 0 ]; then # grep found some failed strings or just patch failed, we should abort now
    echo "ERROR: patch failed to apply cleanly. See ${opts["builddir"]}/patch.log"
    exit 1
else
    echo "patch should apply clean now, trying..."
    patch --verbose -p1 < "${opts["builddir"]}/$patch_filename" > ${opts["builddir"]}/patch.log
    if [ $? -ne 0 ]; then # patch failed somehow anyway
        echo "ERROR: patch failed to apply cleanly. See ${opts["builddir"]}/patch.log"
        exit 1
    else
        echo "patch applied without error"
    fi
fi

# kernel is patched now, copying config
# negate all FTRACE configs so that kernel works on Ubuntu
cat ${opts["builddir"]}/"$config_filename" | sed 's/\(.*FTRACE.*\)=y/\1=n/' > .config
echo "CONFIG_KMEMCHECK=n" >> .config

# compiling
# how much cpu we have?
cpucount=$(grep -cw ^processor /proc/cpuinfo)
CMD="MAKEFLAGS=\"CC=gcc-4.4\" fakeroot make-kpkg --jobs $cpucount --initrd --arch_in_name --append-to-version -openvz-${opts["ovzname"]} --revision ${opts["ovzname"]}~${opts["localname"]} kernel_image kernel_source kernel_headers"
echo -e "\n"
echo "using next command to create package:"
echo "$CMD"
sh -c "$CMD" > ${opts["builddir"]}/compile.log 2>&1
build_result=$?
if [[ $build_result -ne 0 ]]; then
    echo "ERROR: build failed. Check ${opts["builddir"]}/compile.log"
    exit 1
else
    echo "build succeeded, debian packages may be found in ${opts["builddir"]}"
fi

exit 0
