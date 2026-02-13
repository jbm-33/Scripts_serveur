#!/bin/bash
#
# Installe certbot (Let's Encrypt) pour Apache.
# Permet d'utiliser ensuite vhost_apache.sh -l 1 pour un vhost HTTPS.
#

set -e

echo "Installation de Certbot (Let's Encrypt) pour Apache..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Distribution non reconnue."
    exit 1
fi

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get update
    apt-get install -y certbot python3-certbot-apache
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
    yum install -y epel-release
    yum install -y certbot python3-certbot-apache2
elif [ "$OS" = "fedora" ]; then
    dnf install -y certbot python3-certbot-apache
else
    echo "Distribution non supportée pour ce script. Installez certbot manuellement."
    exit 1
fi

echo "✓ Certbot installé. Pour un vhost HTTPS : ./scripts/vhost_apache.sh -l 1 -n example.com ..."
