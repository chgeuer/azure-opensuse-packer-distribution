#!/bin/bash

openSUSEversion=$(cat /etc/os-release | grep -Po '^VERSION="\K[^"]*')
zypper addrepo "http://download.opensuse.org/distribution/leap/${openSUSEversion}/repo/oss/" online

zypper update --no-confirm

zypper install --no-confirm WALinuxAgent
chkconfig waagent on
service waagent start

sed -i 's/^DHCLIENT_SET_HOSTNAME=".*"$/DHCLIENT_SET_HOSTNAME="no"/' /etc/sysconfig/network/dhcp
sed -i 's/^DHCLIENT6_SET_HOSTNAME=".*"$/DHCLIENT6_SET_HOSTNAME="no"/' /etc/sysconfig/network/dhcp

# Got grub2 config from https://docs.microsoft.com/en-us/azure/virtual-machines/linux/redhat-create-upload-vhd
sed -i 's/^GRUB_CMDLINE_LINUX=""$/GRUB_CMDLINE_LINUX="rootdelay=300 console=ttyS0 earlyprintk=ttyS0 net.ifnames=0"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
