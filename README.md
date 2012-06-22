README
======

Tools for Ubuntu + OpenStack + OpenVZ

Building a Kernel
-----------------

Building an OpenVZ kernel on Ubuntu is only supported on Oneiric (11.10).
This is due to the requirement for a specific version of gcc. 
You also need at least 10 GB free space for the build directory.

Run the following to build a kernel on a fresh Oneiric VM:

    ./create-openvz-kernel.sh -D <build-dir> -L <build-name>

This will take care of installing all the prerequisites, downloading
the linux kernel and the latest openvz kernel patch set, setting up
the fakeroot environment, and building some .deb packages.

Package files will be placed in <build-dir> along with a few log files.


Installing the Kernel
---------------------

Once you've built an openvz-enabled kernel, you can install it on
Natty, Oneiric, or Precise with the following script.

    # you can override the default kernel location in the install script
    # or download my kernel build by default
    export KERNEL_URL='http://your.server.here/'
    export KERNEL_NAME='package-name-here'

    ./install-openvz-kernel.sh


This will do several things to your system:

1. download and install the kernel image and headers
2. make some risky changes to grub to force it to use the new (old) kernel
3. install some openvz-related packages
4. install an old version of rsyslog to get around this bug:
   https://bugs.launchpad.net/ubuntu/+source/rsyslog/+bug/523610

After this finishes, you will need to restart the host before you can use
the new kernel. You can verify that it is running by checking the kernel
version and looking in processlist.

    ubuntu@oneiric:~$ uname -a
    Linux oneiric 2.6.32-openvz #1 SMP Thu May 24 16:09:56 UTC 2012 x86_64 x86_64 x86_64 GNU/Linux
    
    ubuntu@oneiric:~$ ps u `pidof vzmond`
    USER         PID %CPU %MEM    VSZ   RSS TTY      STAT START   TIME COMMAND
    root         878  0.0  0.0      0     0 ?        S    17:41   0:00 [vzmond]
    
