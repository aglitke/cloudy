#!/bin/bash
# Cloudy: An open LAMP benchmark suite
# Copyright (C) 2010 Adam Litke, IBM Corporation
# 
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 2 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public
# License along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

#########################################################################
# setup.sh - Main VM setup script.  Prepare a stock F12 installation to #
# participate as a cloudy instance.                                     #
#########################################################################

. /media/config

function run_always()
{
    /root/MOM-0.1/mom-guestd &
}

function status_page()
{
cat <<EOM > /var/www/html/index.html
<html>
<head>
<title>$NAME Status</title>
</head>
<body>
$1
</body>
</html>
EOM
}

if [ -f /SETUP-DONE ]; then
    run_always
    exit 0
fi

status_page "Configuration in progress"

/usr/bin/mysqladmin -u root password 'linux99'

cat <<EOM > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
BOOTPROTO=dhcp
DHCPCLASS=
MTU=1500
ONBOOT=yes
OPTIONS=layer2=1
TYPE=Ethernet
UUID=5fb06bd0-0bb0-7ffb-45f1-d6edd65f3e03
PEERDNS=yes
PEERROUTES=yes
DHCP_HOSTNAME=$NAME
NAME="System eth0"
EOM

cat <<EOM > /etc/sysconfig/network
NETWORKING=yes
HOSTNAME=$NAME
EOM

/etc/init.d/network restart

### Configure mediawiki
cat <<EOM > /etc/httpd/conf.d/mediawiki.conf
Alias /wiki/skins /usr/share/mediawiki/skins
Alias /wiki /var/www/wiki
EOM
service httpd restart

# Submit the mediawiki web configuration form to initialize the wiki
wget --post-file=mediawiki-form-data -O /tmp/wiki-install-result.php http://localhost/wiki/config/index.php
grep -q 'Installation successful' /tmp/wiki-install-result.php
if [ $? -ne 0 ]; then
  MSG="$MSG mediawiki configuration failed -- see /tmp/wiki-install-result.php"
fi
mv /var/www/wiki/config/LocalSettings.php /var/www/wiki/
chmod 400 /var/www/wiki/LocalSettings.php 

# Import wiki data
pushd /var/www/wiki
php /usr/share/mediawiki/maintenance/importDump.php /media/wikidata.xml
/media/import-images.sh
popd

# Setup the MOM guest daemon
pushd /root
tar xzvf /media/MOM-0.1.tar.gz

if [ -z "$MSG" ]; then
  MSG="Ready."
fi
status_page "$MSG"

touch /SETUP-DONE

run_always
