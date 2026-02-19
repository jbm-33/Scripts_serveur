#!/bin/bash

# Script d'installation et de configuration de MariaDB

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation de MariaDB"
echo "========================================="

# Détecter la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Impossible de détecter la distribution Linux"
    exit 1
fi

# Générer un mot de passe pour root MariaDB
MARIADB_ROOT_PASSWORD=$(generate_password 24)

# Installation selon la distribution
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Mise à jour des paquets..."
    apt-get update
    
    echo "Installation de MariaDB..."
    # Désactiver l'interaction pour la configuration
    export DEBIAN_FRONTEND=noninteractive
    apt-get install -y mariadb-server mariadb-client
    
    # Arrêter MariaDB pour configuration sécurisée
    systemctl stop mariadb
    
    # Configuration initiale avec mot de passe root
    echo "Configuration de MariaDB..."
    mysqld_safe --skip-grant-tables &
    sleep 3
    
    mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    
    pkill mysqld
    sleep 2
    
    # Démarrer MariaDB normalement
    systemctl start mariadb
    systemctl enable mariadb
    
    # Exécuter mysql_secure_installation de manière non-interactive
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    # Root sans mot de passe : authentification par socket Unix (seul l'utilisateur système root peut se connecter)
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket; FLUSH PRIVILEGES;"
    
    # Sauvegarder les configurations MariaDB
    if [ -f /etc/mysql/mariadb.conf.d/50-server.cnf ]; then
        save_config "mariadb" "/etc/mysql/mariadb.conf.d/50-server.cnf" "Configuration serveur MariaDB"
    fi
    if [ -f /etc/mysql/my.cnf ]; then
        save_config "mariadb" "/etc/mysql/my.cnf" "Configuration principale MariaDB"
    fi
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        # Ajouter le dépôt MariaDB pour CentOS/RHEL
        cat > /etc/yum.repos.d/mariadb.repo <<EOF
[mariadb]
name = MariaDB
baseurl = http://yum.mariadb.org/10.11/centos\$releasever-amd64
gpgkey=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB
gpgcheck=1
EOF
        yum install -y mariadb-server mariadb
    else
        dnf install -y mariadb-server mariadb
    fi
    
    systemctl enable mariadb
    systemctl start mariadb
    
    # Configuration du mot de passe root
    mysql -u root <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '${MARIADB_ROOT_PASSWORD}';
FLUSH PRIVILEGES;
EOF
    
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" <<EOF
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF

    # Root sans mot de passe : authentification par socket Unix
    mysql -u root -p"${MARIADB_ROOT_PASSWORD}" -e "ALTER USER 'root'@'localhost' IDENTIFIED VIA unix_socket; FLUSH PRIVILEGES;"
    
    # Sauvegarder les configurations MariaDB
    if [ -f /etc/my.cnf ]; then
        save_config "mariadb" "/etc/my.cnf" "Configuration principale MariaDB"
    fi
    if [ -f /etc/my.cnf.d/server.cnf ]; then
        save_config "mariadb" "/etc/my.cnf.d/server.cnf" "Configuration serveur MariaDB"
    fi
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

# Stocker le mot de passe root dans .passwords (sauvegarde / scripts si besoin)
DEVOPS_ROOT="/root/Devops"
save_password "mariadb" "root" "$MARIADB_ROOT_PASSWORD"

echo "✓ MariaDB installé et configuré"
echo "  Connexion root : sans mot de passe (auth. socket Unix) — mysql -u root"
echo "  Mot de passe root stocké dans ${DEVOPS_ROOT}/.passwords (clé: mariadb)"
echo "  Configuration sauvegardée dans ${DEVOPS_ROOT}/configs/"
