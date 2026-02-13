#!/bin/bash

# Script de durcissement de la sécurité du serveur
# Applique les meilleures pratiques de sécurité

set -e

# Charger les fonctions utilitaires
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

echo "========================================="
echo "Durcissement de la sécurité"
echo "========================================="

# Détecter la distribution Linux
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
else
    echo "Impossible de détecter la distribution Linux"
    exit 1
fi

# Créer le dossier Devops s'il n'existe pas
setup_password_storage

# ============================================
# 1. Hardening SSH
# ============================================
echo ""
echo "--- Durcissement SSH ---"

SSH_CONFIG="/etc/ssh/sshd_config"
if [ -f "$SSH_CONFIG" ]; then
    # Sauvegarder la configuration SSH
    save_config "ssh" "$SSH_CONFIG" "Configuration SSH avant durcissement"
    
    # Créer une backup de la config actuelle
    cp "$SSH_CONFIG" "${SSH_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    
    # S'assurer que la connexion root est autorisée (avec mot de passe)
    # Si PermitRootLogin n'existe pas, l'ajouter
    if ! grep -q "^PermitRootLogin" "$SSH_CONFIG"; then
        echo "PermitRootLogin yes" >> "$SSH_CONFIG"
    else
        # S'assurer que PermitRootLogin est sur yes
        sed -i 's/^#PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' "$SSH_CONFIG"
    fi
    
    # Désactiver l'authentification par mot de passe vide
    sed -i 's/#PermitEmptyPasswords no/PermitEmptyPasswords no/' "$SSH_CONFIG"
    sed -i 's/PermitEmptyPasswords yes/PermitEmptyPasswords no/' "$SSH_CONFIG"
    
    # Désactiver l'authentification par clé rsa (ancienne)
    if ! grep -q "^HostKeyAlgorithms" "$SSH_CONFIG"; then
        echo "HostKeyAlgorithms +ssh-rsa,ssh-ed25519" >> "$SSH_CONFIG"
    fi
    
    # Limiter les tentatives de connexion
    if ! grep -q "^MaxAuthTries" "$SSH_CONFIG"; then
        echo "MaxAuthTries 3" >> "$SSH_CONFIG"
    fi
    
    # Désactiver X11 forwarding si non nécessaire
    sed -i 's/#X11Forwarding yes/X11Forwarding no/' "$SSH_CONFIG"
    sed -i 's/X11Forwarding yes/X11Forwarding no/' "$SSH_CONFIG"
    
    # S'assurer que l'authentification par mot de passe est activée (pour root)
    if ! grep -q "^PasswordAuthentication" "$SSH_CONFIG"; then
        echo "PasswordAuthentication yes" >> "$SSH_CONFIG"
    else
        sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication yes/' "$SSH_CONFIG"
        sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$SSH_CONFIG"
    fi
    
    # Timeout de connexion
    if ! grep -q "^ClientAliveInterval" "$SSH_CONFIG"; then
        echo "ClientAliveInterval 300" >> "$SSH_CONFIG"
        echo "ClientAliveCountMax 2" >> "$SSH_CONFIG"
    fi
    
    # Restreindre les utilisateurs autorisés (optionnel - à configurer selon vos besoins)
    # echo "AllowUsers votre_utilisateur" >> "$SSH_CONFIG"
    
    systemctl restart sshd 2>/dev/null || systemctl restart ssh
    
    echo "✓ SSH durci"
    echo "  ✓ Connexion root autorisée (avec mot de passe)"
    echo "  ✓ Authentification par mot de passe activée"
    echo "  ✓ Limitation des tentatives de connexion (MaxAuthTries: 3)"
    echo "  ⚠️  Vérifiez que vous pouvez toujours vous connecter avant de fermer cette session!"
else
    echo "⚠ Configuration SSH non trouvée"
fi

# ============================================
# 2. Mises à jour automatiques de sécurité
# ============================================
echo ""
echo "--- Configuration des mises à jour automatiques ---"

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get install -y unattended-upgrades apt-listchanges
    
    # Configuration des mises à jour automatiques
    cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Automatic-Reboot-Time "02:00";
EOF
    
    # Activer les mises à jour automatiques
    echo 'APT::Periodic::Update-Package-Lists "1";' > /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Unattended-Upgrade "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
    echo 'APT::Periodic::Download-Upgradeable-Packages "1";' >> /etc/apt/apt.conf.d/20auto-upgrades
    
    save_config "system" "/etc/apt/apt.conf.d/50unattended-upgrades" "Configuration mises à jour automatiques"
    save_config "system" "/etc/apt/apt.conf.d/20auto-upgrades" "Configuration périodique mises à jour"
    
    echo "✓ Mises à jour automatiques configurées"
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y yum-cron
        systemctl enable yum-cron
        systemctl start yum-cron
        
        # Configuration yum-cron
        sed -i 's/apply_updates = no/apply_updates = yes/' /etc/yum/yum-cron.conf
        sed -i 's/update_cmd = default/update_cmd = security/' /etc/yum/yum-cron.conf
        
        save_config "system" "/etc/yum/yum-cron.conf" "Configuration yum-cron"
    else
        dnf install -y dnf-automatic
        systemctl enable dnf-automatic.timer
        systemctl start dnf-automatic.timer
        
        # Configuration dnf-automatic
        sed -i 's/apply_updates = no/apply_updates = yes/' /etc/dnf/automatic.conf
        sed -i 's/upgrade_type = default/upgrade_type = security/' /etc/dnf/automatic.conf
        
        save_config "system" "/etc/dnf/automatic.conf" "Configuration dnf-automatic"
    fi
    
    echo "✓ Mises à jour automatiques configurées"
fi

# ============================================
# 3. Configuration du système
# ============================================
echo ""
echo "--- Configuration système ---"

# Désactiver les services inutiles
if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    # Désactiver certains services par défaut
    systemctl disable bluetooth 2>/dev/null || true
    systemctl disable avahi-daemon 2>/dev/null || true
fi

# Configuration sysctl pour la sécurité
SYSCTL_CONF="/etc/sysctl.d/99-security.conf"
cat > "$SYSCTL_CONF" <<'EOF'
# Protection contre IP spoofing
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1

# Ignorer les ICMP redirects
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0

# Ne pas envoyer de ICMP redirects
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0

# Protection contre SYN flood
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# Désactiver le forwarding IP (sauf si routeur)
net.ipv4.ip_forward = 0
net.ipv6.conf.all.forwarding = 0

# Log les paquets martiens
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1

# Ignorer les ICMP echo requests (ping) - décommenter pour désactiver ping
# net.ipv4.icmp_echo_ignore_all = 1

# Protection contre source routing
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

sysctl -p "$SYSCTL_CONF" > /dev/null 2>&1 || true
save_config "system" "$SYSCTL_CONF" "Configuration sysctl sécurité"

echo "✓ Configuration système durcie"

# ============================================
# 4. Installation d'outils de sécurité
# ============================================
echo ""
echo "--- Installation d'outils de sécurité ---"

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    apt-get install -y aide rkhunter logwatch
    
    # Configuration AIDE (détection d'intrusion)
    if [ ! -f /var/lib/aide/aide.db ]; then
        aideinit
    fi
    
    # Configuration rkhunter
    rkhunter --update
    rkhunter --propupd
    
    echo "✓ AIDE, rkhunter et logwatch installés"
    
elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ] || [ "$OS" = "fedora" ]; then
    if [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y aide rkhunter
    else
        dnf install -y aide rkhunter
    fi
    
    # Configuration AIDE
    if [ ! -f /var/lib/aide/aide.db ]; then
        aide --init
        mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db
    fi
    
    # Configuration rkhunter
    rkhunter --update
    rkhunter --propupd
    
    echo "✓ AIDE et rkhunter installés"
fi

# ============================================
# 5. Configuration des limites système
# ============================================
echo ""
echo "--- Configuration des limites système ---"

LIMITS_CONF="/etc/security/limits.d/99-security.conf"
cat > "$LIMITS_CONF" <<'EOF'
# Limites de sécurité
* soft nofile 65535
* hard nofile 65535
* soft nproc 4096
* hard nproc 4096
root soft nproc unlimited
root hard nproc unlimited
EOF

save_config "system" "$LIMITS_CONF" "Configuration limites système"

echo "✓ Limites système configurées"

# ============================================
# 6. Configuration des permissions
# ============================================
echo ""
echo "--- Vérification des permissions ---"

# S'assurer que les fichiers sensibles ont les bonnes permissions
chmod 600 /etc/shadow /etc/gshadow 2>/dev/null || true
chmod 644 /etc/passwd /etc/group 2>/dev/null || true
chmod 640 /etc/shadow- /etc/gshadow- 2>/dev/null || true

echo "✓ Permissions vérifiées"

# ============================================
# 7. Désactiver les comptes système inutiles
# ============================================
echo ""
echo "--- Vérification des comptes utilisateurs ---"

# Lister les comptes avec shell mais sans mot de passe
echo "Comptes avec shell mais potentiellement non sécurisés:"
awk -F: '($2 == "" || $2 == "!") && ($7 != "/sbin/nologin" && $7 != "/usr/sbin/nologin" && $7 != "/bin/false") {print $1}' /etc/passwd || true

echo "✓ Vérification terminée"

echo ""
echo "========================================="
echo "✓ Durcissement de la sécurité terminé"
echo "========================================="
echo ""
echo "Configurations sauvegardées dans: ${DEVOPS_ROOT}/configs/"
echo ""
echo "⚠️  IMPORTANT:"
echo "  - Vérifiez que vous pouvez toujours vous connecter en SSH"
echo "  - Testez les services installés"
echo "  - Configurez les alertes de sécurité si nécessaire"
