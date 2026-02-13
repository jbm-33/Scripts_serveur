#!/bin/bash
#
# Restaure des fichiers de configuration depuis ${DEVOPS_ROOT}/configs/
# vers les chemins système. Demande confirmation avant chaque restauration.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

CONFIG_BACKUP_DIR="${DEVOPS_ROOT}/configs"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -d "$CONFIG_BACKUP_DIR" ]; then
    echo "Aucun dossier configs trouvé : $CONFIG_BACKUP_DIR"
    exit 1
fi

# Mapping connu : nom du backup -> chemin cible (on devine à partir du nom quand c'est possible)
# Format des backups : service_filename.backup
get_target_path() {
    local backup_name="$1"
    # Ex: apache_apache2.conf.backup -> /etc/apache2/apache2.conf
    # Ex: php_php.ini.backup -> on ne peut pas deviner le chemin php sans version
    case "$backup_name" in
        apache_apache2.conf.backup) echo "/etc/apache2/apache2.conf" ;;
        apache_security.conf.backup) echo "/etc/apache2/conf-available/security.conf" ;;
        mongodb_mongod.conf.backup) echo "/etc/mongod.conf" ;;
        mariadb_50-server.cnf.backup) echo "/etc/mysql/mariadb.conf.d/50-server.cnf" ;;
        mariadb_my.cnf.backup) echo "/etc/mysql/my.cnf" ;;
        fail2ban_jail.local.backup) echo "/etc/fail2ban/jail.local" ;;
        ssh_sshd_config.backup) echo "/etc/ssh/sshd_config" ;;
        *) echo "" ;;
    esac
}

echo "Configurations disponibles dans ${CONFIG_BACKUP_DIR}:"
echo ""

for f in "$CONFIG_BACKUP_DIR"/*.backup; do
    [ -f "$f" ] || continue
    name=$(basename "$f")
    target=$(get_target_path "$name")
    if [ -z "$target" ]; then
        echo -e "  ${YELLOW}$name${NC} (chemin cible à saisir)"
    else
        echo "  $name → $target"
    fi
done

echo ""
echo -n "Nom du fichier .backup à restaurer (ou 'q' pour quitter) : "
read -r choice
[ "$choice" = "q" ] && exit 0

path="$CONFIG_BACKUP_DIR/$choice"
if [ ! -f "$path" ]; then
    path="$CONFIG_BACKUP_DIR/${choice%.backup}.backup"
fi
if [ ! -f "$path" ]; then
    echo "Fichier introuvable."
    exit 1
fi

target=$(get_target_path "$(basename "$path")")
if [ -z "$target" ]; then
    echo -n "Chemin cible (ex: /etc/ssh/sshd_config) : "
    read -r target
fi
[ -z "$target" ] && exit 1

if [ ! -f "$target" ]; then
    echo "Le chemin cible $target n'existe pas. Créer ? (o/n)"
    read -r rep
    [ "$rep" != "o" ] && [ "$rep" != "O" ] && exit 0
    mkdir -p "$(dirname "$target")"
fi

echo -e "Copier ${path} vers ${target} ? (o/n)"
read -r rep
if [ "$rep" = "o" ] || [ "$rep" = "O" ]; then
    cp "$path" "$target"
    chmod 600 "$target" 2>/dev/null || true
    echo -e "${GREEN}✓ Restauré : $target${NC}"
else
    echo "Annulé."
fi
