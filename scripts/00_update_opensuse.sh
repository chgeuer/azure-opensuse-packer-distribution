#!/bin/bash

openSUSEversion=$(cat /etc/os-release | grep -Po '^VERSION="\K[^"]*')
zypper addrepo "http://download.opensuse.org/distribution/leap/${openSUSEversion}/repo/oss/" online

zypper update --no-confirm
