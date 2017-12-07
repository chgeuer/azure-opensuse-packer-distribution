#!/bin/bash

# Got grub2 config from https://docs.microsoft.com/en-us/azure/virtual-machines/linux/redhat-create-upload-vhd
sed -i 's/^GRUB_CMDLINE_LINUX=""$/GRUB_CMDLINE_LINUX="rootdelay=300 console=ttyS0 earlyprintk=ttyS0 net.ifnames=0"/' /etc/default/grub
grub2-mkconfig -o /boot/grub2/grub.cfg
