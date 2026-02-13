#!/bin/bash

# Script d'installation et de configuration de Fail2ban

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation de Fail2ban"
echo "========================================="

# Détecter la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Impossible de détecter la distribution Linux"
    exit 1
fi

# Installation selon la distribution
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Mise à jour des paquets..."
    apt-get update
    
    echo "Installation de Fail2ban..."
    apt-get install -y fail2ban
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y epel-release
        yum install -y fail2ban fail2ban-systemd
    else
        dnf install -y fail2ban fail2ban-systemd
    fi
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

# Configuration de base de Fail2ban
echo "Configuration de Fail2ban..."

# Créer le fichier de configuration local
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
# Adresse IP à bannir
bantime = 3600
findtime = 600
maxretry = 5
destemail = root@localhost
sendername = Fail2Ban
action = %(action_)s

[sshd]
enabled = true
port = ssh
logpath = %(sshd_log)s
backend = %(sshd_backend)s
maxretry = 3

[apache-auth]
enabled = true
port = http,https
logpath = %(apache_error_log)s

[apache-badbots]
enabled = true
port = http,https
logpath = %(apache_access_log)s
bantime = 86400

[apache-noscript]
enabled = true
port = http,https
logpath = %(apache_error_log)s

[apache-overflows]
enabled = true
port = http,https
logpath = %(apache_error_log)s
maxretry = 2

[php-url-fopen]
enabled = true
port = http,https
logpath = %(apache_error_log)s
EOF

# Sauvegarder la configuration
save_config "fail2ban" "/etc/fail2ban/jail.local" "Configuration Fail2ban"

# Démarrer Fail2ban
systemctl enable fail2ban
systemctl start fail2ban

echo "✓ Fail2ban installé et configuré"
echo "  Protection SSH activée"
echo "  Protection Apache activée"
echo "  Configuration sauvegardée dans ${DEVOPS_ROOT}/configs/"
