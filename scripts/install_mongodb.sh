#!/bin/bash

# Script d'installation et de configuration de MongoDB

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation de MongoDB"
echo "========================================="

# Détecter la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "Impossible de détecter la distribution Linux"
    exit 1
fi

# Générer un mot de passe pour l'utilisateur admin MongoDB
MONGO_ADMIN_PASSWORD=$(generate_password 24)
MONGO_ADMIN_USER="admin"

# Installation selon la distribution
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "Ajout de la clé GPG MongoDB..."
    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor
    
    echo "Ajout du dépôt MongoDB..."
    if [ "$OS" = "ubuntu" ]; then
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/7.0 multiverse" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    else
        echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/debian bullseye/mongodb-org/7.0 main" | tee /etc/apt/sources.list.d/mongodb-org-7.0.list
    fi
    
    echo "Mise à jour des paquets..."
    apt-get update
    
    echo "Installation de MongoDB..."
    apt-get install -y mongodb-org
    
    # Démarrer MongoDB
    systemctl daemon-reload
    systemctl enable mongod
    systemctl start mongod
    
    # Attendre que MongoDB soit prêt
    echo "Attente du démarrage de MongoDB..."
    sleep 5
    
    # Créer l'utilisateur administrateur
    echo "Création de l'utilisateur administrateur MongoDB..."
    mongosh admin --eval "db.createUser({user: '${MONGO_ADMIN_USER}', pwd: '${MONGO_ADMIN_PASSWORD}', roles: ['root']})" || {
        echo "Tentative alternative de création d'utilisateur..."
        mongosh --eval "use admin; db.createUser({user: '${MONGO_ADMIN_USER}', pwd: '${MONGO_ADMIN_PASSWORD}', roles: ['root']})"
    }
    
    # Activer l'authentification
    echo "Activation de l'authentification MongoDB..."
    if ! grep -q "authorization: enabled" /etc/mongod.conf; then
        sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf
    fi
    
    # Sauvegarder la configuration
    save_config "mongodb" "/etc/mongod.conf" "Configuration MongoDB"
    
    systemctl restart mongod
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    # Créer le fichier de dépôt MongoDB
    cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<EOF
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/\$releasever/mongodb-org/7.0/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
EOF
    
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y mongodb-org
    else
        dnf install -y mongodb-org
    fi
    
    systemctl enable mongod
    systemctl start mongod
    
    sleep 5
    
    mongosh admin --eval "db.createUser({user: '${MONGO_ADMIN_USER}', pwd: '${MONGO_ADMIN_PASSWORD}', roles: ['root']})" || {
        mongosh --eval "use admin; db.createUser({user: '${MONGO_ADMIN_USER}', pwd: '${MONGO_ADMIN_PASSWORD}', roles: ['root']})"
    }
    
    if ! grep -q "authorization: enabled" /etc/mongod.conf; then
        sed -i 's/#security:/security:\n  authorization: enabled/' /etc/mongod.conf
    fi
    
    # Sauvegarder la configuration
    save_config "mongodb" "/etc/mongod.conf" "Configuration MongoDB"
    
    systemctl restart mongod
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

# Sauvegarder le mot de passe
save_password "mongodb" "$MONGO_ADMIN_USER" "$MONGO_ADMIN_PASSWORD"

echo "✓ MongoDB installé et configuré"
echo "  Utilisateur admin: ${MONGO_ADMIN_USER}"
echo "  Mot de passe sauvegardé dans ${DEVOPS_ROOT}/.passwords"
echo "  Configuration sauvegardée dans ${DEVOPS_ROOT}/configs/"
