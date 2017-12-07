#!/bin/bash

zypper install --no-confirm WALinuxAgent
chkconfig waagent on
service waagent start
