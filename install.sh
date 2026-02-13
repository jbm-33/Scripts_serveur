#!/bin/bash

# Script principal d'installation du serveur
# Installe: php-fpm, MongoDB, MariaDB, Apache, fail2ban, Postfix, iptables, etc.
# Génère et sauvegarde tous les mots de passe (dossier défini par DEVOPS_ROOT dans utils.sh)

set -e

# Couleurs pour les messages
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Options (valeurs par défaut)
SKIP_HOSTNAME_PROMPT=""
SKIP_SERVICES=""
DRY_RUN=""
LOG_FILE=""

# Liste des services qu'on peut exclure avec --skip=
VALID_SKIP="php-fpm|mongodb|mariadb|apache|fail2ban|postfix|iptables|hardening|hostname|motd"

# Retourne 0 si le service doit être installé, 1 si on le saute
should_install() {
    local s="$1"
    [ -z "$SKIP_SERVICES" ] && return 0
    echo ",${SKIP_SERVICES}," | grep -q ",${s}," && return 1 || return 0
}

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help            Afficher cette aide"
    echo "  --skip-hostname       Ne pas demander le hostname"
    echo "  --skip=SERVICES       Ne pas installer certains services (séparés par des virgules)"
    echo ""
    echo "Services pouvant être exclus avec --skip= :"
    echo "  php-fpm, mongodb, mariadb, apache, fail2ban, postfix, iptables, hardening, hostname, motd"
    echo ""
    echo "Exemples:"
    echo "  $0                              Installation complète"
    echo "  $0 --skip=mongodb,postfix      Sans MongoDB ni Postfix"
    echo "  $0 --skip=mongodb              Serveur avec MariaDB uniquement (pas MongoDB)"
    echo "  $0 --skip=postfix,motd         Sans envoi d'emails ni bandeau de connexion"
    echo "  $0 --dry-run                    Afficher les étapes sans exécuter"
    exit 0
}

# Analyse des arguments
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help)
            usage
            ;;
        --skip-hostname)
            SKIP_HOSTNAME_PROMPT="1"
            shift
            ;;
        --skip=*)
            SKIP_SERVICES="${1#--skip=}"
            # Normaliser : minuscules, pas d'espaces
            SKIP_SERVICES=$(echo "$SKIP_SERVICES" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
            # Vérifier que chaque service est valide
            for s in $(echo "$SKIP_SERVICES" | tr ',' '\n'); do
                if ! echo "$s" | grep -qE "^(${VALID_SKIP})$"; then
                    echo -e "${RED}Service inconnu dans --skip= : $s${NC}" >&2
                    echo "Services valides : php-fpm, mongodb, mariadb, apache, fail2ban, postfix, iptables, hardening, hostname, motd"
                    exit 1
                fi
            done
            shift
            ;;
        --dry-run)
            DRY_RUN="1"
            shift
            ;;
        *)
            echo -e "${RED}Option inconnue: $1${NC}" >&2
            echo "Utilisez --help pour l'aide."
            exit 1
            ;;
    esac
done

# Vérifier que le script est exécuté en tant que root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Erreur: Ce script doit être exécuté en tant que root${NC}"
    exit 1
fi

echo -e "${GREEN}========================================="
echo "Installation du serveur"
echo "=========================================${NC}"

# Détecter la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    echo -e "${GREEN}Distribution détectée: ${OS}${NC}"
else
    echo -e "${RED}Impossible de détecter la distribution Linux${NC}"
    exit 1
fi

# Obtenir le répertoire du script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"

# Charger les fonctions utilitaires
source "${SCRIPTS_DIR}/utils.sh"

# Initialiser le stockage des mots de passe (et créer DEVOPS_ROOT si besoin)
setup_password_storage

# Logs : redirection vers fichier daté (sauf en dry-run)
if [ -z "$DRY_RUN" ]; then
    mkdir -p "${DEVOPS_ROOT}/logs"
    LOG_FILE="${DEVOPS_ROOT}/logs/install_$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$LOG_FILE") 2>&1
    echo "Log d'installation : $LOG_FILE"
    # Trap : en cas d'échec, afficher la ligne et le code de sortie
    trap 'err=$?; echo -e "\n${RED}ERREUR: la dernière commande a échoué (code de sortie: $err)${NC}"; exit $err' ERR
fi

# Changer le mot de passe root
echo -e "${YELLOW}========================================="
echo "Changement du mot de passe root"
echo "=========================================${NC}"

if [ -n "$DRY_RUN" ]; then
    echo "[DRY-RUN] Would change root password and save to ${DEVOPS_ROOT}/.passwords"
else
    ROOT_NEW_PASSWORD=$(generate_password 24)
    echo "root:${ROOT_NEW_PASSWORD}" | chpasswd
    save_password "system" "root" "$ROOT_NEW_PASSWORD"
    echo -e "${GREEN}✓ Mot de passe root changé et sauvegardé${NC}"
fi

# Installation des services
echo -e "${YELLOW}========================================="
echo "Installation des services"
echo "=========================================${NC}"

# 1. PHP-FPM
if should_install "php-fpm"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_php-fpm.sh"; else bash "${SCRIPTS_DIR}/install_php-fpm.sh"; fi
else
    echo ""; echo "[ --skip=php-fpm ] PHP-FPM ignoré."
fi

# 2. MongoDB
if should_install "mongodb"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_mongodb.sh"; else bash "${SCRIPTS_DIR}/install_mongodb.sh"; fi
else
    echo ""; echo "[ --skip=mongodb ] MongoDB ignoré."
fi

# 3. MariaDB
if should_install "mariadb"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_mariadb.sh"; else bash "${SCRIPTS_DIR}/install_mariadb.sh"; fi
else
    echo ""; echo "[ --skip=mariadb ] MariaDB ignoré."
fi

# 4. Apache
if should_install "apache"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_apache.sh"; else bash "${SCRIPTS_DIR}/install_apache.sh"; fi
else
    echo ""; echo "[ --skip=apache ] Apache ignoré."
fi

# 5. Fail2ban
if should_install "fail2ban"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_fail2ban.sh"; else bash "${SCRIPTS_DIR}/install_fail2ban.sh"; fi
else
    echo ""; echo "[ --skip=fail2ban ] Fail2ban ignoré."
fi

# 6. Postfix (SMTP)
if should_install "postfix"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_postfix.sh"; else bash "${SCRIPTS_DIR}/install_postfix.sh"; fi
else
    echo ""; echo "[ --skip=postfix ] Postfix ignoré."
fi

# 7. iptables
if should_install "iptables"; then
    echo ""
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/install_iptables.sh"; else bash "${SCRIPTS_DIR}/install_iptables.sh"; fi
else
    echo ""; echo "[ --skip=iptables ] iptables ignoré."
fi

# 8. Durcissement de la sécurité
if should_install "hardening"; then
    echo ""
    echo -e "${YELLOW}========================================="
    echo "Durcissement de la sécurité"
    echo "=========================================${NC}"
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: ${SCRIPTS_DIR}/harden_security.sh"; else bash "${SCRIPTS_DIR}/harden_security.sh"; fi
else
    echo ""; echo "[ --skip=hardening ] Durcissement ignoré."
fi

# 9. Hostname du serveur
if should_install "hostname"; then
    echo ""
    echo -e "${YELLOW}========================================="
    echo "Hostname du serveur"
    echo "=========================================${NC}"
    if [ -n "$DRY_RUN" ]; then
        echo "[DRY-RUN] Would prompt for hostname or run set_hostname.sh"
    elif [ -n "$SKIP_HOSTNAME_PROMPT" ]; then
        echo "Hostname : ignoré (option --skip-hostname)."
        echo "Pour définir plus tard : sudo ./scripts/set_hostname.sh \"nom-du-serveur\""
    else
        echo -n "Voulez-vous définir le hostname du serveur maintenant ? (o/n, défaut: n): "
        read -r SET_HOSTNAME
        if [ "$SET_HOSTNAME" = "o" ] || [ "$SET_HOSTNAME" = "O" ] || [ "$SET_HOSTNAME" = "y" ] || [ "$SET_HOSTNAME" = "Y" ]; then
            bash "${SCRIPTS_DIR}/set_hostname.sh" || true
        else
            echo "Vous pourrez le faire plus tard avec: sudo ./scripts/set_hostname.sh \"nom-du-serveur\""
        fi
    fi
else
    echo ""; echo "[ --skip=hostname ] Hostname ignoré."
fi

# 10. Bandeau de connexion (MOTD)
if should_install "motd"; then
    echo ""
    echo -e "${YELLOW}========================================="
    echo "Bandeau de connexion (MOTD)"
    echo "=========================================${NC}"
    if [ -n "$DRY_RUN" ]; then echo "[DRY-RUN] Would run: install_motd.sh"; else bash "${SCRIPTS_DIR}/install_motd.sh" "$(hostname -s 2>/dev/null || hostname)" || true; fi
else
    echo ""; echo "[ --skip=motd ] MOTD ignoré."
fi

# 11. Vérification des services (sauf en dry-run)
if [ -z "$DRY_RUN" ] && [ -x "${SCRIPTS_DIR}/verify_services.sh" ]; then
    echo ""
    echo -e "${YELLOW}========================================="
    echo "Vérification des services"
    echo "=========================================${NC}"
    bash "${SCRIPTS_DIR}/verify_services.sh" || true
fi

# 12. Logrotate (sauf en dry-run)
if [ -z "$DRY_RUN" ] && [ -x "${SCRIPTS_DIR}/install_logrotate.sh" ]; then
    echo ""
    echo -e "${YELLOW}========================================="
    echo "Rotation des logs (logrotate)"
    echo "=========================================${NC}"
    bash "${SCRIPTS_DIR}/install_logrotate.sh" || true
fi

# Afficher un résumé
echo ""
echo -e "${GREEN}========================================="
echo "Installation terminée avec succès!"
echo "=========================================${NC}"
echo ""
echo -e "${YELLOW}Résumé des services installés:${NC}"
should_install "php-fpm"    && echo "  ✓ PHP-FPM"
should_install "mongodb"    && echo "  ✓ MongoDB"
should_install "mariadb"    && echo "  ✓ MariaDB"
should_install "apache"     && echo "  ✓ Apache"
should_install "fail2ban"   && echo "  ✓ Fail2ban"
should_install "postfix"    && echo "  ✓ Postfix (SMTP)"
should_install "iptables"   && echo "  ✓ iptables"
should_install "motd"       && echo "  ✓ Bandeau de connexion (MOTD)"
should_install "hardening"  && echo "  ✓ Durcissement de la sécurité"
echo ""
echo -e "${YELLOW}Tous les mots de passe ont été sauvegardés dans:${NC}"
echo "  ${DEVOPS_ROOT}/.passwords"
echo ""
echo -e "${YELLOW}Les règles iptables ont été sauvegardées dans:${NC}"
echo "  ${DEVOPS_ROOT}/.iptables.rules"
echo "  ${DEVOPS_ROOT}/.ip6tables.rules"
echo ""
echo -e "${YELLOW}Tous les fichiers de configuration (.conf) ont été sauvegardés dans:${NC}"
echo "  ${DEVOPS_ROOT}/configs/"
echo ""
echo -e "${YELLOW}Pour consulter les mots de passe:${NC}"
echo "  cat ${DEVOPS_ROOT}/.passwords"
echo ""
echo -e "${YELLOW}Pour restaurer les règles iptables:${NC}"
echo "  ${DEVOPS_ROOT}/.restore_iptables.sh"
echo ""
echo -e "${YELLOW}Pour consulter les configurations sauvegardées:${NC}"
echo "  ls -la ${DEVOPS_ROOT}/configs/"
[ -n "$LOG_FILE" ] && echo "" && echo "Log complet : $LOG_FILE"
echo ""
echo -e "${GREEN}Installation terminée!${NC}"
