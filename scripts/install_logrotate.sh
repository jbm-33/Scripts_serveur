#!/bin/bash
#
# Configure logrotate pour les logs des services (Apache, PHP-FPM, MongoDB, MariaDB, fail2ban)
# pour éviter de remplir le disque.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "Configuration de logrotate pour les services..."

# Détection distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Distribution non reconnue."
    exit 1
fi

# Logrotate est généralement déjà installé
if ! command -v logrotate &>/dev/null; then
    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update && apt-get install -y logrotate
    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
        [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] && yum install -y logrotate || dnf install -y logrotate
    fi
fi

CONFD="/etc/logrotate.d"

# Apache (Debian/Ubuntu ou RHEL)
if [ -d /var/log/apache2 ]; then
    cat > "$CONFD/devops-apache2" <<'EOF'
/var/log/apache2/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload apache2 >/dev/null 2>&1 || true
    endscript
}
EOF
    echo "  + logrotate Apache (Debian/Ubuntu)"
elif [ -d /var/log/httpd ]; then
    cat > "$CONFD/devops-httpd" <<'EOF'
/var/log/httpd/*log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    sharedscripts
    postrotate
        systemctl reload httpd >/dev/null 2>&1 || true
    endscript
}
EOF
    echo "  + logrotate Apache (RHEL)"
fi

# PHP-FPM
for d in /var/log/php*-fpm; do
    [ -d "$d" ] || continue
    cat > "$CONFD/devops-php-fpm" <<EOF
$d/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
}
EOF
    echo "  + logrotate PHP-FPM"
    break
done

# MongoDB
if [ -f /var/log/mongodb/mongod.log ]; then
    cat > "$CONFD/devops-mongodb" <<'EOF'
/var/log/mongodb/mongod.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    copytruncate
}
EOF
    echo "  + logrotate MongoDB"
fi

# MariaDB / MySQL
if [ -d /var/log/mysql ]; then
    cat > "$CONFD/devops-mysql" <<'EOF'
/var/log/mysql/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
}
EOF
    echo "  + logrotate MariaDB/MySQL"
fi

# Fail2ban
if [ -f /var/log/fail2ban.log ]; then
    cat > "$CONFD/devops-fail2ban" <<'EOF'
/var/log/fail2ban.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
}
EOF
    echo "  + logrotate Fail2ban"
fi

# Logs d'installation (dossier Devops)
if [ -d "${DEVOPS_ROOT}/logs" ]; then
    cat > "$CONFD/devops-install-logs" <<EOF
${DEVOPS_ROOT}/logs/*.log {
    weekly
    missingok
    rotate 4
    compress
    notifempty
}
EOF
    echo "  + logrotate logs d'installation (${DEVOPS_ROOT}/logs)"
fi

# Logs Apache par instance vhost : /home/*/logs/apache/
# Chaque instance créée par vhost_apache.sh a ses propres logs dans son home
cat > "$CONFD/devops-vhost-apache-logs" <<'EOF'
/home/*/logs/apache/*.log {
    daily
    missingok
    rotate 14
    compress
    delaycompress
    notifempty
    copytruncate
    sharedscripts
    postrotate
        systemctl reload apache2 >/dev/null 2>&1 || systemctl reload httpd >/dev/null 2>&1 || true
    endscript
}
EOF
echo "  + logrotate logs Apache par instance (/home/*/logs/apache/)"

echo "✓ Logrotate configuré. Vérification : logrotate -d $CONFD/devops-* 2>/dev/null || true"
