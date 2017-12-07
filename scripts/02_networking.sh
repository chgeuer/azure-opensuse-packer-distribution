#!/bin/bash

sed -i 's/^DHCLIENT_SET_HOSTNAME=".*"$/DHCLIENT_SET_HOSTNAME="no"/' /etc/sysconfig/network/dhcp
sed -i 's/^DHCLIENT6_SET_HOSTNAME=".*"$/DHCLIENT6_SET_HOSTNAME="no"/' /etc/sysconfig/network/dhcp
