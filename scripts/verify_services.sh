#!/bin/bash
#
# Vérifications post-installation : état des services et tests de connexion.
# Affiche un résumé OK/KO pour chaque service installé.
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "Vérification des services..."
echo ""

OK=0
KO=0

# Retourne 0 si le service systemd est actif
check_systemd() {
    local name="$1"
    local unit="$2"
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} $name (systemd: $unit)"
        return 0
    else
        echo -e "  ${RED}✗${NC} $name (systemd: $unit) — inactif ou absent"
        return 1
    fi
}

# PHP-FPM (plusieurs versions possibles)
for u in php*-fpm; do
    if systemctl list-units --type=service --all 2>/dev/null | grep -q "$u"; then
        if systemctl is-active --quiet "$u" 2>/dev/null; then
            echo -e "  ${GREEN}✓${NC} PHP-FPM ($u)"; OK=$((OK+1))
        else
            echo -e "  ${RED}✗${NC} PHP-FPM ($u) — inactif"; KO=$((KO+1))
        fi
        break
    fi
done

# MongoDB
if systemctl list-units --type=service --all 2>/dev/null | grep -q mongod; then
    if systemctl is-active --quiet mongod 2>/dev/null; then
        if command -v mongosh &>/dev/null; then
            if mongosh --quiet --eval "db.adminCommand('ping')" &>/dev/null; then
                echo -e "  ${GREEN}✓${NC} MongoDB (actif + connexion OK)"; OK=$((OK+1))
            else
                echo -e "  ${YELLOW}~${NC} MongoDB (actif, connexion non testée ou auth requise)"; OK=$((OK+1))
            fi
        else
            echo -e "  ${GREEN}✓${NC} MongoDB (mongod actif)"; OK=$((OK+1))
        fi
    else
        echo -e "  ${RED}✗${NC} MongoDB (mongod inactif)"; KO=$((KO+1))
    fi
fi

# MariaDB / MySQL
if systemctl is-active --quiet mariadb 2>/dev/null || systemctl is-active --quiet mysql 2>/dev/null; then
    if command -v mysql &>/dev/null; then
        if mysql -e "SELECT 1" &>/dev/null 2>&1; then
            echo -e "  ${GREEN}✓${NC} MariaDB (actif + connexion OK)"; OK=$((OK+1))
        else
            echo -e "  ${YELLOW}~${NC} MariaDB (actif, connexion refusée sans mot de passe)"; OK=$((OK+1))
        fi
    else
        echo -e "  ${GREEN}✓${NC} MariaDB (service actif)"; OK=$((OK+1))
    fi
elif systemctl list-units --type=service --all 2>/dev/null | grep -qE 'mariadb|mysql'; then
    echo -e "  ${RED}✗${NC} MariaDB (service inactif)"; KO=$((KO+1))
fi

# Apache
if systemctl list-units --type=service --all 2>/dev/null | grep -qE 'apache2|httpd'; then
    if systemctl is-active --quiet apache2 2>/dev/null || systemctl is-active --quiet httpd 2>/dev/null; then
        code=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1/ 2>/dev/null || echo "000")
        if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ] || [ "$code" = "403" ]; then
            echo -e "  ${GREEN}✓${NC} Apache (actif + HTTP $code)"; OK=$((OK+1))
        else
            echo -e "  ${YELLOW}~${NC} Apache (actif, HTTP $code)"; OK=$((OK+1))
        fi
    else
        echo -e "  ${RED}✗${NC} Apache (inactif)"; KO=$((KO+1))
    fi
fi

# Fail2ban
if systemctl list-units --type=service --all 2>/dev/null | grep -q fail2ban; then
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Fail2ban"; OK=$((OK+1))
    else
        echo -e "  ${RED}✗${NC} Fail2ban (inactif)"; KO=$((KO+1))
    fi
fi

# Postfix
if systemctl list-units --type=service --all 2>/dev/null | grep -q postfix; then
    if systemctl is-active --quiet postfix 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Postfix"; OK=$((OK+1))
    else
        echo -e "  ${RED}✗${NC} Postfix (inactif)"; KO=$((KO+1))
    fi
fi

# SSH (écoute sur 22)
if ss -tlnp 2>/dev/null | grep -q ':22 '; then
    echo -e "  ${GREEN}✓${NC} SSH (port 22 ouvert)"; OK=$((OK+1))
else
    echo -e "  ${YELLOW}~${NC} SSH (port 22 non détecté ou ss indisponible)"
fi

# iptables (règles présentes)
if command -v iptables &>/dev/null && iptables -L -n 2>/dev/null | head -1 | grep -q Chain; then
    echo -e "  ${GREEN}✓${NC} iptables (règles chargées)"; OK=$((OK+1))
fi

echo ""
echo -e "Résumé : ${GREEN}$OK OK${NC} — ${RED}$KO KO${NC}"
