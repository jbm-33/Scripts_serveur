#!/bin/bash
#
# Installation et configuration de Postfix (MTA) pour l'envoi d'emails
# Utilisé par le script vhost (mail des identifiants), fail2ban, cron, etc.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Installation de Postfix (SMTP)"
echo "========================================="

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Impossible de détecter la distribution."
    exit 1
fi

# Installation
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get update
    # postfix = MTA, mailutils = commande "mail", libsasl2-modules = relais SMTP authentifié
    DEBIAN_FRONTEND=noninteractive apt-get install -y postfix mailutils libsasl2-modules
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y postfix mailx
    else
        dnf install -y postfix mailx
    fi
else
    echo "Distribution non supportée: $OS"
    exit 1
fi

# Répertoire Devops (DEVOPS_ROOT depuis utils.sh)
ROOT="${DEVOPS_ROOT}"
SMTP_CONFIG="${ROOT}/.smtp_config"
setup_password_storage

# Sauvegarder la config Postfix actuelle avant modification
if [ -f /etc/postfix/main.cf ]; then
    save_config "postfix" "/etc/postfix/main.cf" "Configuration Postfix"
fi

# Configuration de base : envoi direct (Internet Site)
# Utiliser le hostname du serveur pour les enveloppes
MAILNAME="${MAILNAME:-$(hostname -f 2>/dev/null || hostname)}"
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "$MAILNAME" > /etc/mailname 2>/dev/null || true
fi

postconf -e "myhostname = $MAILNAME"
postconf -e "mydomain = ${MAILNAME#*.}"
postconf -e "myorigin = \$mydomain"
postconf -e "inet_interfaces = all"
postconf -e "inet_protocols = all"

# Relais SMTP optionnel : si ${DEVOPS_ROOT}/.smtp_config existe
if [ -r "$SMTP_CONFIG" ]; then
    relay_host=$(grep -E "^relay_host:" "$SMTP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    smtp_user=$(grep -E "^smtp_user:" "$SMTP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    smtp_pass=$(grep -E "^smtp_pass:" "$SMTP_CONFIG" 2>/dev/null | cut -d: -f2- | tr -d ' ')
    if [ -n "$relay_host" ]; then
        echo "Configuration du relais SMTP: $relay_host"
        postconf -e "relayhost = [$relay_host]:587"
        postconf -e "smtp_sasl_auth_enable = yes"
        postconf -e "smtp_sasl_security_options = noanonymous"
        postconf -e "smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd"
        postconf -e "smtp_tls_security_level = encrypt"
        postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
        mkdir -p /etc/postfix
        echo "[$relay_host]:587 $smtp_user:$smtp_pass" > /etc/postfix/sasl_passwd
        chmod 600 /etc/postfix/sasl_passwd
        postmap /etc/postfix/sasl_passwd
        save_password "smtp" "relay" "$smtp_pass"
    fi
fi

# Démarrer / recharger
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    systemctl enable postfix
    systemctl restart postfix
else
    systemctl enable postfix
    systemctl restart postfix
fi

# Test minimal
echo "Test d'envoi (localhost)..."
echo "Test Postfix Scripts_serveur" | mail -s "Test SMTP" root 2>/dev/null || true

echo "✓ Postfix installé et configuré"
echo "  Commande 'mail' disponible pour les scripts (vhost, cron, etc.)"
if [ -r "$SMTP_CONFIG" ] && [ -n "$relay_host" ]; then
    echo "  Relais SMTP actif: $relay_host"
else
    echo "  Mode: envoi direct (Internet). Pour utiliser un relais (OVH, Gmail, etc.), créez $SMTP_CONFIG"
fi
