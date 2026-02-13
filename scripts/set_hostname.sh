#!/bin/bash
#
# Définit le hostname du serveur (saisie manuelle).
# Met à jour /etc/hostname et /etc/hosts de façon persistante.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Hostname fourni en argument ou demandé
NEW_HOSTNAME="${1:-}"

if [ -z "$NEW_HOSTNAME" ]; then
    echo "========================================="
    echo "Définition du hostname du serveur"
    echo "========================================="
    echo -n "Entrez le hostname (ex: serveur1, srv.example.com): "
    read -r NEW_HOSTNAME
fi

NEW_HOSTNAME=$(echo "$NEW_HOSTNAME" | tr -d '[:space:]')
if [ -z "$NEW_HOSTNAME" ]; then
    echo -e "${RED}Erreur: hostname vide.${NC}"
    exit 1
fi

# Validation : lettres, chiffres, tirets, points (FQDN ou nom court)
if ! echo "$NEW_HOSTNAME" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,62}[a-zA-Z0-9])?$'; then
    echo -e "${RED}Erreur: hostname invalide (utilisez lettres, chiffres, tirets, points).${NC}"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}Ce script doit être exécuté en root (sudo).${NC}"
    exit 1
fi

OLD_HOSTNAME=$(hostname -s 2>/dev/null || hostname)
echo "Hostname actuel : $OLD_HOSTNAME"
echo "Nouveau hostname : $NEW_HOSTNAME"
echo ""

# 1. Persistance du hostname (selon distro)
if command -v hostnamectl &>/dev/null; then
    hostnamectl set-hostname "$NEW_HOSTNAME"
    echo -e "${GREEN}✓ hostnamectl set-hostname $NEW_HOSTNAME${NC}"
else
    echo "$NEW_HOSTNAME" > /etc/hostname
    hostname "$NEW_HOSTNAME" 2>/dev/null || true
    echo -e "${GREEN}✓ /etc/hostname mis à jour${NC}"
fi

# 2. Mise à jour de /etc/hosts
# Supprimer l'ancienne ligne 127.0.1.1 (hostname précédent)
sed -i.bak '/^127\.0\.1\.1[[:space:]]/d' /etc/hosts 2>/dev/null || true
# Ajouter la nouvelle entrée pour le hostname (résolution locale)
echo "127.0.1.1	$NEW_HOSTNAME" >> /etc/hosts
echo -e "${GREEN}✓ /etc/hosts mis à jour (127.0.1.1 → $NEW_HOSTNAME)${NC}"

# 3. Postfix : myhostname (optionnel)
if [ -f /etc/postfix/main.cf ] && command -v postconf &>/dev/null; then
    postconf -e "myhostname = $NEW_HOSTNAME" 2>/dev/null && echo -e "${GREEN}✓ Postfix myhostname mis à jour${NC}" || true
fi

# 4. Mettre à jour le MOTD pour utiliser le nouveau hostname
if [ -f "$SCRIPT_DIR/install_motd.sh" ]; then
    echo "Mise à jour du bandeau de connexion (MOTD)..."
    bash "$SCRIPT_DIR/install_motd.sh" "$NEW_HOSTNAME" 2>/dev/null || true
fi

echo ""
echo -e "${GREEN}✓ Hostname défini : $NEW_HOSTNAME${NC}"
echo "  Pour une prise en compte complète, une déconnexion/reconnexion SSH est recommandée."
echo "  (Sur certaines configurations, un redémarrage peut être nécessaire.)"
