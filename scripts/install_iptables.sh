#!/bin/bash

# Script d'installation et de configuration d'iptables
# Configure des règles de base et sauvegarde les règles

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation et configuration d'iptables"
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
    
    echo "Installation d'iptables et iptables-persistent..."
    apt-get install -y iptables iptables-persistent
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y iptables iptables-services
    else
        dnf install -y iptables iptables-services
    fi
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

# Créer le dossier Devops s'il n'existe pas
setup_password_storage

# Sauvegarder les règles (chemin depuis utils.sh)
IPTABLES_BACKUP_DIR="${DEVOPS_ROOT}"
IPTABLES_RULES_FILE="${IPTABLES_BACKUP_DIR}/.iptables.rules"
IPTABLES_RULES_V6_FILE="${IPTABLES_BACKUP_DIR}/.ip6tables.rules"
IPTABLES_RESTORE_SCRIPT="${IPTABLES_BACKUP_DIR}/.restore_iptables.sh"

echo "Sauvegarde des règles iptables existantes..."
if [ -f "$IPTABLES_RULES_FILE" ]; then
    cp "$IPTABLES_RULES_FILE" "${IPTABLES_RULES_FILE}.old.$(date +%Y%m%d_%H%M%S)"
fi

# Sauvegarder les règles actuelles
iptables-save > "$IPTABLES_RULES_FILE" 2>/dev/null || true
ip6tables-save > "$IPTABLES_RULES_V6_FILE" 2>/dev/null || true

echo "Configuration des règles iptables..."

# Flush des règles existantes
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# Politique par défaut : DROP tout le trafic entrant, ACCEPT le trafic sortant
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# Autoriser le trafic localhost
iptables -A INPUT -i lo -j ACCEPT

# Autoriser les paquets établis et connexions associées
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Autoriser SSH (port 22) - IMPORTANT : ne pas bloquer votre accès
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Autoriser HTTP (port 80)
iptables -A INPUT -p tcp --dport 80 -j ACCEPT

# Autoriser HTTPS (port 443)
iptables -A INPUT -p tcp --dport 443 -j ACCEPT

# Autoriser MongoDB (port 27017) - uniquement depuis localhost par défaut
# Décommentez la ligne suivante si vous voulez autoriser depuis l'extérieur
# iptables -A INPUT -p tcp --dport 27017 -j ACCEPT

# Autoriser MariaDB (port 3306) - uniquement depuis localhost par défaut
# Décommentez la ligne suivante si vous voulez autoriser depuis l'extérieur
# iptables -A INPUT -p tcp --dport 3306 -j ACCEPT

# Limiter les connexions ICMP (ping)
iptables -A INPUT -p icmp --icmp-type echo-request -m limit --limit 1/s -j ACCEPT

# Rejeter les autres paquets avec un message
iptables -A INPUT -j REJECT --reject-with icmp-host-prohibited

# Configuration IPv6 (similaire)
if command -v ip6tables &> /dev/null; then
    ip6tables -F
    ip6tables -X
    ip6tables -P INPUT DROP
    ip6tables -P FORWARD DROP
    ip6tables -P OUTPUT ACCEPT
    
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
    ip6tables -A INPUT -p icmpv6 --icmpv6-type echo-request -m limit --limit 1/s -j ACCEPT
    ip6tables -A INPUT -j REJECT --reject-with icmp6-adm-prohibited
fi

# Sauvegarder les nouvelles règles
echo "Sauvegarde des nouvelles règles iptables..."
iptables-save > "$IPTABLES_RULES_FILE"
chmod 600 "$IPTABLES_RULES_FILE"

if command -v ip6tables &> /dev/null; then
    ip6tables-save > "$IPTABLES_RULES_V6_FILE"
    chmod 600 "$IPTABLES_RULES_V6_FILE"
fi

# Créer un script de restauration (chemin injecté)
cat > "$IPTABLES_RESTORE_SCRIPT" <<EOF
#!/bin/bash
# Script de restauration des règles iptables
# Usage: ./restore_iptables.sh

if [ "\$EUID" -ne 0 ]; then 
    echo "Erreur: Ce script doit être exécuté en tant que root"
    exit 1
fi

IPTABLES_RULES_FILE="${DEVOPS_ROOT}/.iptables.rules"
IPTABLES_RULES_V6_FILE="${DEVOPS_ROOT}/.ip6tables.rules"

if [ -f "\$IPTABLES_RULES_FILE" ]; then
    echo "Restauration des règles iptables IPv4..."
    iptables-restore < "\$IPTABLES_RULES_FILE"
    echo "✓ Règles IPv4 restaurées"
else
    echo "Erreur: Fichier de règles IPv4 non trouvé: \$IPTABLES_RULES_FILE"
fi

if [ -f "\$IPTABLES_RULES_V6_FILE" ] && command -v ip6tables &> /dev/null; then
    echo "Restauration des règles iptables IPv6..."
    ip6tables-restore < "\$IPTABLES_RULES_V6_FILE"
    echo "✓ Règles IPv6 restaurées"
fi
EOF

chmod 700 "$IPTABLES_RESTORE_SCRIPT"

# Configurer la persistance des règles au démarrage
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    # Utiliser iptables-persistent
    echo "Configuration de la persistance des règles..."
    mkdir -p /etc/iptables
    cp "$IPTABLES_RULES_FILE" /etc/iptables/rules.v4
    if [ -f "$IPTABLES_RULES_V6_FILE" ]; then
        cp "$IPTABLES_RULES_V6_FILE" /etc/iptables/rules.v6
    fi
    
    # Activer le service
    systemctl enable netfilter-persistent 2>/dev/null || true
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    # Utiliser iptables-services
    echo "Configuration de la persistance des règles..."
    systemctl enable iptables
    systemctl enable ip6tables 2>/dev/null || true
    
    # Sauvegarder les règles dans le fichier système
    service iptables save 2>/dev/null || iptables-save > /etc/sysconfig/iptables
    if command -v ip6tables &> /dev/null; then
        service ip6tables save 2>/dev/null || ip6tables-save > /etc/sysconfig/ip6tables
    fi
fi

echo "✓ iptables installé et configuré"
echo "  Règles sauvegardées dans: $IPTABLES_RULES_FILE"
echo "  Script de restauration: $IPTABLES_RESTORE_SCRIPT"
echo ""
echo "Règles configurées:"
echo "  ✓ SSH (port 22) autorisé"
echo "  ✓ HTTP (port 80) autorisé"
echo "  ✓ HTTPS (port 443) autorisé"
echo "  ✓ Trafic localhost autorisé"
echo "  ✓ Connexions établies autorisées"
echo "  ✗ Tout le reste est bloqué par défaut"
