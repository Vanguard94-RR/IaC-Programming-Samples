#!/bin/bash
# --------------------------------------------------------
# Name   : patching-tool.sh
# Desc   : Automating patching steps
# Author : Gene Ordanza II <geronimo.ordanza@fisglobal.com>
# Group  : ETS Linux/Unix Patching
# History: 20140610 (initial draft)
# --------------------------------------------------------

BOOT="/boot/grub/"
DMID="/usr/sbin"

echo -e "Running automated patching ...\n"

echo "DATE        : `date`"
echo "HOSTNAME    : `hostname`"
echo "IP ADDRESS  : `hostname -i`"
echo "OS RELEASE  : `cat /etc/redhat-release`"
echo "OS Kernel   : `uname -r` "
sleep 1

# Make backup of grub.conf
echo -e "\nCreating backup of /boot/grub/grub.conf file ..."
cp $BOOT/grub.conf $BOOT/grub.conf-prepatch-`date +%m-%d-%Y`


# Disable BoKs Authentication
echo -e "\nDisable BoKs Authentication ...\n"
/usr/boksm/lib/sysreplace restore


# Run either yum or up2date to patch the server
echo  "Running patch program ..."
if [ -f /usr/bin/yum ]; then
    echo -e "Using yum utility to update server ...\n"
    /usr/bin/yum -y update

elif [ -f /usr/sbin/up2date ]; then
    echo "Using up2date to update server ..."
    /usr/sbin/up2date --update
    /usr/sbin/up2date --list
fi


# Activate BoKs Authentication
# NOTE: you can email  infosec.szu.mailbox <infosec.szu.mailbox@fisglobal.com>
# if you got timeout/lockout from BoKs
echo -e "\nActivate BoKs Authentication ...\n"
/usr/boksm/lib/sysreplace replace


# Check if server is running as VMware guest OS; if yes, run vmware-config-tool
if $DMID/dmidecode | grep -i "VMware Virtual Platform" &> /dev/null; then
    echo -e "\nRunning as Guest OS ..."
    $DMID/dmidecode|grep -i product
    echo -e "\nCalling 'vmware-config-tools.pl' utility ..."

    if [ -f /usr/bin/vmware-config-tools.pl ]; then
        /usr/bin/vmware-config-tools.pl
    else
        echo "*** WARNING *** vmware-config-tools.pl utility not installed!!"
    fi

else
    echo -e "\nRunning on physical server ..."
    $DMID/dmidecode | grep -i product
fi


# Temporarily disable grub password during boot-up (restore after boot)
echo -e "\nChecking for password setup in grub.conf ..."
cp $BOOT/grub.conf $BOOT/grub.conf-postpatch-`date +%m-%d-%Y`
if grep -e "^password" $BOOT/grub.conf &> /dev/null; then
    echo  "Password setting enabled in grub.conf ... "
    echo -e "Disabling password settings in grub.conf ...\n "
    sed -i.bak 's/^password/#password/' $BOOT/grub.conf
    diff $BOOT/grub.conf $BOOT/grub.conf.bak | tail -n3
else
    echo -e "No password was setup in grub.conf ...\n"
fi

# Verify patching status
if [ -f /usr/bin/yum ]; then

    case `yum check-update &>/dev/null; echo $?` in
        "0") echo -e "*** System packages are updated! ***\n" ;;
        "1") echo -e "*** Error occured! Use yum check-update manually ***\n";;
      "100") echo -e "*** System updates available ***\n" ;;
    esac

elif [ -f /usr/sbin/up2date ]; then
    /usr/sbin/up2date --list; echo
fi
