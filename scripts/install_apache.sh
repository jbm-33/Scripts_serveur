#!/bin/bash

# Script d'installation et de configuration d'Apache

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation d'Apache"
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
    
    echo "Installation d'Apache..."
    apt-get install -y apache2
    
    # Activer les modules nécessaires
    a2enmod rewrite
    a2enmod ssl
    a2enmod headers
    a2enmod proxy
    a2enmod proxy_fcgi
    
    # Configuration pour PHP-FPM
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
    
    # Créer une configuration pour PHP-FPM
    cat > /etc/apache2/conf-available/php-fpm.conf <<EOF
<FilesMatch \.php$>
    SetHandler "proxy:unix:/var/run/php/php${PHP_VERSION}-fpm.sock|fcgi://localhost"
</FilesMatch>
EOF
    
    a2enconf php-fpm
    
    # Configuration de sécurité Apache
    echo "Configuration de sécurité Apache..."
    
    # Désactiver les informations serveur
    if ! grep -q "ServerTokens" /etc/apache2/conf-available/security.conf; then
        sed -i 's/ServerTokens.*/ServerTokens Prod/' /etc/apache2/conf-available/security.conf
        sed -i 's/ServerSignature.*/ServerSignature Off/' /etc/apache2/conf-available/security.conf
    fi
    
    # Headers de sécurité
    a2enmod headers
    cat > /etc/apache2/conf-available/security-headers.conf <<'EOF'
# Headers de sécurité
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
EOF
    a2enconf security-headers
    
    # Sauvegarder les configurations
    save_config "apache" "/etc/apache2/apache2.conf" "Configuration principale Apache"
    save_config "apache" "/etc/apache2/conf-available/security.conf" "Configuration sécurité Apache"
    save_config "apache" "/etc/apache2/conf-available/security-headers.conf" "Headers de sécurité Apache"
    
    # Démarrer Apache
    systemctl enable apache2
    systemctl start apache2
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y httpd
    else
        dnf install -y httpd
    fi
    
    # Configuration pour PHP-FPM
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
    
    # Ajouter la configuration PHP-FPM dans httpd.conf
    if ! grep -q "php-fpm" /etc/httpd/conf.d/php-fpm.conf 2>/dev/null; then
        cat >> /etc/httpd/conf.d/php-fpm.conf <<EOF
<FilesMatch \.php$>
    SetHandler "proxy:unix:/var/run/php-fpm/www.sock|fcgi://localhost"
</FilesMatch>
EOF
    fi
    
    # Configuration de sécurité Apache
    echo "Configuration de sécurité Apache..."
    
    # Désactiver les informations serveur
    sed -i 's/ServerTokens.*/ServerTokens Prod/' /etc/httpd/conf/httpd.conf
    sed -i 's/ServerSignature.*/ServerSignature Off/' /etc/httpd/conf/httpd.conf
    
    # Headers de sécurité
    cat > /etc/httpd/conf.d/security-headers.conf <<'EOF'
# Headers de sécurité
Header always set X-Content-Type-Options "nosniff"
Header always set X-Frame-Options "SAMEORIGIN"
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Permissions-Policy "geolocation=(), microphone=(), camera=()"
EOF
    
    # Sauvegarder les configurations
    save_config "apache" "/etc/httpd/conf/httpd.conf" "Configuration principale Apache"
    save_config "apache" "/etc/httpd/conf.d/security-headers.conf" "Headers de sécurité Apache"
    
    # Démarrer Apache
    systemctl enable httpd
    systemctl start httpd
    
    # Configuration du firewall
    if command -v firewall-cmd &> /dev/null; then
        firewall-cmd --permanent --add-service=http
        firewall-cmd --permanent --add-service=https
        firewall-cmd --reload
    fi
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

echo "✓ Apache installé et configuré"
echo "  Apache est démarré et configuré pour fonctionner avec PHP-FPM"
echo "  Headers de sécurité configurés"
echo "  Informations serveur masquées"
