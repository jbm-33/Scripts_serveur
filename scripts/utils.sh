#!/bin/bash

# Script utilitaire pour la gestion des mots de passe et chemins communs
# Charge .env à la racine du projet si présent (à côté de install.sh)
SCRIPT_DIR_UTILS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT_UTILS="$(dirname "$SCRIPT_DIR_UTILS")"
if [ -f "${PROJECT_ROOT_UTILS}/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    source "${PROJECT_ROOT_UTILS}/.env"
    set +a
fi

# Chemin racine Devops : .env > variable d'environnement > défaut
DEVOPS_ROOT="${DEVOPS_ROOT:-/root/Devops}"
export DEVOPS_ROOT

# Créer le dossier Devops s'il n'existe pas
setup_password_storage() {
    if [ ! -d "$DEVOPS_ROOT" ]; then
        mkdir -p "$DEVOPS_ROOT"
        chmod 700 "$DEVOPS_ROOT"
    fi
    
    PASSWORD_FILE="${DEVOPS_ROOT}/.passwords"
    if [ ! -f "$PASSWORD_FILE" ]; then
        touch "$PASSWORD_FILE"
        chmod 600 "$PASSWORD_FILE"
    fi
}

# Générer un mot de passe aléatoire sécurisé
generate_password() {
    local length=${1:-32}
    # Génère un mot de passe aléatoire avec caractères alphanumériques et spéciaux
    openssl rand -base64 48 | tr -d "=+/" | cut -c1-${length}
}

# Générer un mot de passe court (compatible script vhost, style pwgen)
genpass() {
    local length=${1:-12}
    if command -v pwgen &>/dev/null; then
        pwgen -A -B "$length" 1
    else
        openssl rand -base64 24 | tr -d "=+/" | cut -c1-"$length"
    fi
}

# Générer un préfixe lettres uniquement (pour noms d'utilisateur)
genprefix() {
    local length=${1:-2}
    if command -v pwgen &>/dev/null; then
        pwgen -A -B --no-numerals "$length" 1
    else
        LC_ALL=C tr -dc 'a-zA-Z' < /dev/urandom 2>/dev/null | head -c "$length"
    fi
}

# Sauvegarder un mot de passe dans le fichier caché
save_password() {
    local service=$1
    local username=$2
    local password=$3
    
    setup_password_storage
    
    PASSWORD_FILE="${DEVOPS_ROOT}/.passwords"
    
    # Vérifier si le service existe déjà
    if grep -q "^${service}:" "$PASSWORD_FILE"; then
        # Mettre à jour le mot de passe existant
        sed -i "/^${service}:/d" "$PASSWORD_FILE"
    fi
    
    # Ajouter le nouveau mot de passe
    echo "${service}:${username}:${password}" >> "$PASSWORD_FILE"
    
    echo "✓ Mot de passe sauvegardé pour ${service} (utilisateur: ${username})"
}

# Récupérer un mot de passe depuis le fichier
get_password() {
    local service=$1
    PASSWORD_FILE="${DEVOPS_ROOT}/.passwords"
    
    if [ -f "$PASSWORD_FILE" ]; then
        grep "^${service}:" "$PASSWORD_FILE" | cut -d: -f3
    fi
}

# Afficher tous les mots de passe sauvegardés (pour vérification)
list_passwords() {
    PASSWORD_FILE="${DEVOPS_ROOT}/.passwords"
    
    if [ -f "$PASSWORD_FILE" ] && [ -s "$PASSWORD_FILE" ]; then
        echo "=== Mots de passe sauvegardés ==="
        cat "$PASSWORD_FILE" | while IFS=: read -r service username password; do
            echo "Service: $service | Utilisateur: $username | Mot de passe: $password"
        done
    else
        echo "Aucun mot de passe sauvegardé."
    fi
}

# Sauvegarder un fichier de configuration
save_config() {
    local service=$1
    local config_file=$2
    local description=${3:-""}
    
    setup_password_storage
    
    CONFIG_BACKUP_DIR="${DEVOPS_ROOT}/configs"
    if [ ! -d "$CONFIG_BACKUP_DIR" ]; then
        mkdir -p "$CONFIG_BACKUP_DIR"
        chmod 700 "$CONFIG_BACKUP_DIR"
    fi
    
    if [ -f "$config_file" ]; then
        local backup_file="${CONFIG_BACKUP_DIR}/${service}_$(basename $config_file).backup"
        local timestamp=$(date +%Y%m%d_%H%M%S)
        local dated_backup="${CONFIG_BACKUP_DIR}/${service}_$(basename $config_file).${timestamp}"
        
        # Sauvegarder avec timestamp
        cp "$config_file" "$dated_backup"
        chmod 600 "$dated_backup"
        
        # Créer aussi un backup sans timestamp (dernière version)
        cp "$config_file" "$backup_file"
        chmod 600 "$backup_file"
        
        echo "✓ Configuration sauvegardée: $config_file -> $backup_file"
        if [ -n "$description" ]; then
            echo "  Description: $description"
        fi
    else
        echo "⚠ Fichier de configuration non trouvé: $config_file"
    fi
}

# Sauvegarder plusieurs fichiers de configuration d'un service
save_configs() {
    local service=$1
    shift
    local config_files=("$@")
    
    for config_file in "${config_files[@]}"; do
        if [ -f "$config_file" ]; then
            save_config "$service" "$config_file"
        fi
    done
}

# Restaurer un fichier de configuration
restore_config() {
    local service=$1
    local config_file=$2
    local backup_file=$3
    
    CONFIG_BACKUP_DIR="${DEVOPS_ROOT}/configs"
    
    if [ -z "$backup_file" ]; then
        # Utiliser le backup le plus récent
        backup_file="${CONFIG_BACKUP_DIR}/${service}_$(basename $config_file).backup"
    fi
    
    if [ -f "$backup_file" ]; then
        cp "$backup_file" "$config_file"
        chmod 600 "$config_file"
        echo "✓ Configuration restaurée: $backup_file -> $config_file"
    else
        echo "✗ Fichier de backup non trouvé: $backup_file"
        return 1
    fi
}
