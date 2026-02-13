#!/bin/bash

# Script d'installation et de configuration de PHP-FPM

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation de PHP-FPM"
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
    
    echo "Installation de PHP-FPM et extensions courantes..."
    apt-get install -y php-fpm php-cli php-common php-mysql php-mongodb php-curl \
        php-gd php-mbstring php-xml php-zip php-bcmath php-json
    
    # Configuration PHP-FPM
    PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')
    PHP_FPM_CONF="/etc/php/${PHP_VERSION}/fpm/php-fpm.conf"
    PHP_INI="/etc/php/${PHP_VERSION}/fpm/php.ini"
    PHP_CLI_INI="/etc/php/${PHP_VERSION}/cli/php.ini"
    
    # Durcissement de la sécurité PHP
    echo "Configuration de sécurité PHP..."
    
    # Désactiver les fonctions dangereuses
    sed -i 's/;disable_functions =/disable_functions =/' "$PHP_INI"
    if ! grep -q "disable_functions.*exec" "$PHP_INI"; then
        sed -i 's/disable_functions =.*/&,exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source/' "$PHP_INI"
    fi
    
    # Masquer les informations PHP
    sed -i 's/expose_php = On/expose_php = Off/' "$PHP_INI"
    
    # Désactiver l'affichage des erreurs en production
    sed -i 's/display_errors = On/display_errors = Off/' "$PHP_INI"
    sed -i 's/display_startup_errors = On/display_startup_errors = Off/' "$PHP_INI"
    
    # Limiter les uploads
    sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 10M/' "$PHP_INI"
    sed -i 's/post_max_size = 8M/post_max_size = 12M/' "$PHP_INI"
    
    # Configuration de sécurité PHP-FPM
    if [ -f "$PHP_FPM_CONF" ]; then
        # Limiter les processus
        sed -i 's/;pm.max_children = 5/pm.max_children = 50/' "$PHP_FPM_CONF"
        sed -i 's/;pm.start_servers = 2/pm.start_servers = 5/' "$PHP_FPM_CONF"
    fi
    
    # Sauvegarder les configurations
    save_config "php" "$PHP_INI" "Configuration PHP-FPM"
    save_config "php" "$PHP_CLI_INI" "Configuration PHP-CLI"
    save_config "php" "$PHP_FPM_CONF" "Configuration PHP-FPM principal"
    
    # Activer PHP-FPM au démarrage
    systemctl enable php${PHP_VERSION}-fpm
    systemctl start php${PHP_VERSION}-fpm
    
    echo "✓ PHP-FPM installé et démarré (version ${PHP_VERSION})"
    echo "  Sécurité PHP renforcée"
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y epel-release
        yum install -y php-fpm php-cli php-common php-mysql php-mongodb php-curl \
            php-gd php-mbstring php-xml php-zip php-bcmath php-json
    else
        dnf install -y php-fpm php-cli php-common php-mysql php-mongodb php-curl \
            php-gd php-mbstring php-xml php-zip php-bcmath php-json
    fi
    
    # Durcissement de la sécurité PHP
    echo "Configuration de sécurité PHP..."
    
    PHP_INI="/etc/php.ini"
    PHP_FPM_CONF="/etc/php-fpm.d/www.conf"
    
    # Désactiver les fonctions dangereuses
    if ! grep -q "disable_functions.*exec" "$PHP_INI" 2>/dev/null; then
        echo "disable_functions = exec,passthru,shell_exec,system,proc_open,popen,curl_exec,curl_multi_exec,parse_ini_file,show_source" >> "$PHP_INI"
    fi
    
    # Masquer les informations PHP
    sed -i 's/expose_php = On/expose_php = Off/' "$PHP_INI" 2>/dev/null || true
    
    # Désactiver l'affichage des erreurs
    sed -i 's/display_errors = On/display_errors = Off/' "$PHP_INI" 2>/dev/null || true
    
    # Sauvegarder les configurations
    save_config "php" "$PHP_INI" "Configuration PHP"
    if [ -f "$PHP_FPM_CONF" ]; then
        save_config "php" "$PHP_FPM_CONF" "Configuration PHP-FPM"
    fi
    
    systemctl enable php-fpm
    systemctl start php-fpm
    
    echo "✓ PHP-FPM installé et démarré"
    echo "  Sécurité PHP renforcée"
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

echo "✓ Installation de PHP-FPM terminée"
