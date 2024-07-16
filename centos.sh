#!/bin/bash

# This script is designed for CentOS.

# Apache site settings
SITE=php_proxy.conf

# Apache file to where this will be written
CONF_FILE=/etc/httpd/conf.d/$SITE

# How much RAM should be allocated to each Apache process? This is measured in kB (kilobytes) because MemTotal below is given in kB
# RSS for an average httpd php-proxy instance is anywhere from 10-15 MB
# Actual unique memory taken up by each is 2-5 MB. Factor in all the "shared memory", and the real average should be about 5 MB
APACHE_PROCESS_MEM=5000

function check_apache(){

    # check if directory exist
    if [ -d /etc/httpd/ ]; then
        echo "Apache is already installed on this system. This installation only works on fresh systems"
        exit
    fi
}

function check_www(){

    # check if directory exist
    if [ -d "/var/www/" ]; then
        echo "Contents of /var/www/ will be removed."
        read -p "Do you want to continue? [Y/n] "
        
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf /var/www/
        else
            exit
        fi
    fi
}

function install_cron(){

    # brackets = list of commands to be executed as one unit
    # restart apache every 12 hours
    (crontab -l 2>/dev/null; echo "0 0,12 * * * /usr/sbin/service httpd restart") | crontab -
    
    # update php-proxy-app everyday on midnight
    (crontab -l 2>/dev/null; echo "0 0 * * * /usr/local/bin/composer update --working-dir=/var/www/") | crontab -
}

function update(){

    # dist upgrades
    yum -y update
}

function install_composer(){

    # install composer
    curl -sS https://getcomposer.org/installer | php
    mv composer.phar /usr/local/bin/composer

    # preserve those command arguments for every composer call
    alias composer='/usr/local/bin/composer'
}

# should we even run this script?
check_apache

# does /var/www/ already exist?
check_www

## fresh installations may need to update package locations
update

## git for composer and bc for math operations - vnstat for bandwidth
yum -y install git bc curl vnstat

# How much RAM does this computer even have? This will be in kilobytes
MEM_TOTAL=$( grep MemTotal /proc/meminfo | awk '{print $2}' )

# How much of that RAM should be set aside exclusively for Apache?
APACHE_MEM=$( echo "$MEM_TOTAL * 0.90 / 1" | bc  )

# MaxClients = Usable Memory / Memory per Apache process
MAX_CLIENTS=$(( $APACHE_MEM / $APACHE_PROCESS_MEM )) 


# LAMP setup
yum -y install httpd php php-cli php-curl php-mbstring

# We need youtube-dl too - this takes a while to install....
yum -y install youtube-dl

# we need these mods
sed -i 's/^#LoadModule status_module/LoadModule status_module/' /etc/httpd/conf.modules.d/00-base.conf

# we don't need these mods. -f to avoid "WARNING: The following essential module will be disabled"
sed -i 's/^LoadModule deflate_module/#LoadModule deflate_module/' /etc/httpd/conf.modules.d/00-base.conf
sed -i 's/^LoadModule alias_module/#LoadModule alias_module/' /etc/httpd/conf.modules.d/00-base.conf
sed -i 's/^LoadModule rewrite_module/#LoadModule rewrite_module/' /etc/httpd/conf.modules.d/00-base.conf

install_composer

# remove default stuff from apache home directory
rm -rf /var/www/*

## create a new configuration file and write our own
touch $CONF_FILE

echo "Writing to a configuration file $CONF_FILE...";

cat > $CONF_FILE <<EOL
ServerName localhost

<VirtualHost *:80>
    DocumentRoot /var/www/
</VirtualHost>

ServerLimit $MAX_CLIENTS

<IfModule mpm_prefork_module>
    StartServers        5
    MinSpareServers     5
    MaxSpareServers     10
    MaxClients          $MAX_CLIENTS
    MaxRequestsPerChild 0
</IfModule>

ExtendedStatus On

<Location /proxy-status>
    SetHandler server-status
</Location>

EOL

## enable our new site
systemctl enable httpd
systemctl restart httpd

composer create-project athlon1600/php-proxy-app:dev-master /var/www/ --no-interaction

# optimize composer
composer dumpautoload -o --working-dir=/var/www/

install_cron
