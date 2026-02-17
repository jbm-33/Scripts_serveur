#!/bin/bash
#
# Désinstalle un vhost créé par vhost_apache.sh.
# S'appuie sur le fichier ${DEVOPS_ROOT}/sites/<vhost>.installed pour connaître
# l'utilisateur système, la base MySQL, etc.
#
# Usage: ./uninstall_vhost.sh <nom_du_vhost>   # ex. extract.gazoleen.gzl
#        ./uninstall_vhost.sh                  # liste les vhosts et demande de choisir
#        ./uninstall_vhost.sh <vhost> -y       # sans confirmation
#
# À lancer en root.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ROOT="${DEVOPS_ROOT}"
SITES_DIR="${ROOT}/sites"
INSTALLED_DIR="${ROOT}/installed"
VHOSTS_AVAILABLE="/etc/apache2/sites-available"

usage() {
  echo "Usage: $0 [NOM_VHOST] [-y]"
  echo "  NOM_VHOST  Nom du vhost = FQDN (ex. extract.gazoleen.gzl), pas le nom du fichier BDD (ex. extract_data)."
  echo "             Fichier utilisé : \${DEVOPS_ROOT}/sites/<NOM_VHOST>.installed"
  echo "             Si absent, affiche la liste des vhosts installés."
  echo "  -y         Désinstaller sans demander de confirmation."
  echo "  Avec plusieurs arguments (ex. extract_data extract.gazoleen.gzl), le script prend celui qui correspond à un fichier dans sites/."
  exit 0
}

# Arguments : le nom du vhost = FQDN (ex. extract.gazoleen.gzl), pas le nom du fichier BDD (ex. extract_data)
VHOST_NAME=""
FORCE_YES=""
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "-y" ]] || [[ "$arg" == "--yes" ]]; then
    FORCE_YES="1"
  elif [[ "$arg" == "-h" ]] || [[ "$arg" == "--help" ]]; then
    usage
  elif [[ "$arg" != -* ]]; then
    ARGS+=("$arg")
  fi
done
# Un seul argument = nom du vhost. Plusieurs arguments = prendre celui pour lequel sites/<arg>.installed existe (le FQDN)
if [[ ${#ARGS[@]} -eq 1 ]]; then
  VHOST_NAME="${ARGS[0]}"
elif [[ ${#ARGS[@]} -gt 1 ]]; then
  for a in "${ARGS[@]}"; do
    if [[ -f "${SITES_DIR}/${a}.installed" ]]; then
      VHOST_NAME="$a"
      break
    fi
  done
  # Aucun ne correspond : prendre celui qui ressemble à un FQDN (contient un point)
  if [[ -z "$VHOST_NAME" ]]; then
    for a in "${ARGS[@]}"; do
      if [[ "$a" == *.* ]]; then
        VHOST_NAME="$a"
        break
      fi
    done
  fi
  if [[ -z "$VHOST_NAME" ]]; then
    VHOST_NAME="${ARGS[0]}"
  fi
fi

# Vérifier root
if [[ "$(id -u)" -ne 0 ]]; then
  echo -e "${RED}Erreur: ce script doit être exécuté en root.${NC}" >&2
  exit 1
fi

# Dossier sites
if [[ ! -d "$SITES_DIR" ]]; then
  echo -e "${RED}Erreur: $SITES_DIR introuvable. Aucun vhost géré par ce script.${NC}" >&2
  exit 1
fi

# Choisir le vhost si non fourni
if [[ -z "$VHOST_NAME" ]]; then
  echo "Vhosts installés (fichiers dans $SITES_DIR) :"
  list=()
  while IFS= read -r -d '' f; do
    list+=("$(basename "$f" .installed)")
  done < <(find "$SITES_DIR" -maxdepth 1 -name "*.installed" -print0 2>/dev/null | sort -z)
  if [[ ${#list[@]} -eq 0 ]]; then
    echo "Aucun fichier .installed trouvé."
    exit 1
  fi
  for i in "${!list[@]}"; do
    echo "  $((i+1))) ${list[$i]}"
  done
  echo -n "Numéro ou nom du vhost à désinstaller : "
  read -r choice
  if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#list[@]} ]]; then
    VHOST_NAME="${list[$((choice-1))]}"
  else
    VHOST_NAME="$choice"
  fi
  if [[ -z "$VHOST_NAME" ]]; then
    echo "Annulé."
    exit 0
  fi
fi

# Fichier .installed du vhost
INSTALLED_FILE="${SITES_DIR}/${VHOST_NAME}.installed"
if [[ ! -f "$INSTALLED_FILE" ]]; then
  echo -e "${RED}Erreur: $INSTALLED_FILE introuvable.${NC}" >&2
  echo "Vhosts disponibles : $(find "$SITES_DIR" -maxdepth 1 -name "*.installed" -exec basename {} .installed \; 2>/dev/null | tr '\n' ' ')"
  exit 1
fi

# Lire les infos (même format que vhost_apache.sh)
sysuser=""
while IFS= read -r line; do
  key="${line%%:*}"
  val="${line#*:}"
  val="${val#"${val%%[![:space:]]*}"}"
  case "$key" in
    login)     sysuser="$val" ;;
    loginmysql) ;; # même que login
  esac
done < "$INSTALLED_FILE"

if [[ -z "$sysuser" ]]; then
  echo -e "${RED}Erreur: impossible de lire le login dans $INSTALLED_FILE${NC}" >&2
  exit 1
fi

echo ""
echo "Vhost à désinstaller : $VHOST_NAME"
echo "  Utilisateur système : $sysuser"
echo "  Base MySQL          : $sysuser (sera supprimée)"
echo "  Dossier home        : /home/$sysuser (sera supprimé)"
echo ""

if [[ -z "$FORCE_YES" ]]; then
  echo -n "Continuer ? (o/N) "
  read -r rep
  if [[ "$rep" != "o" && "$rep" != "O" && "$rep" != "y" && "$rep" != "Y" ]]; then
    echo "Annulé."
    exit 0
  fi
fi

# 1) Désactiver et supprimer le site Apache
if [[ -d "$VHOSTS_AVAILABLE" ]]; then
  if a2dissite "$VHOST_NAME.conf" 2>/dev/null; then
    echo -e "${GREEN}✓ Site Apache $VHOST_NAME désactivé${NC}"
  fi
  if [[ -f "${VHOSTS_AVAILABLE}/${VHOST_NAME}.conf" ]]; then
    rm -f "${VHOSTS_AVAILABLE}/${VHOST_NAME}.conf"
    echo -e "${GREEN}✓ Config Apache supprimée${NC}"
  fi
fi

# 2) Supprimer le pool PHP-FPM
for fpm_pool in /etc/php/*/fpm/pool.d/"${VHOST_NAME}.conf"; do
  if [[ -f "$fpm_pool" ]]; then
    rm -f "$fpm_pool"
    echo -e "${GREEN}✓ Pool PHP-FPM supprimé : $fpm_pool${NC}"
    php_svc=$(echo "$fpm_pool" | sed -n 's|/etc/php/\([^/]*\)/fpm/pool.d/.*|php\1-fpm|p')
    [[ -n "$php_svc" ]] && systemctl reload "$php_svc" 2>/dev/null || true
  fi
done
# Recharger tous les php*-fpm au cas où
for s in /etc/init.d/php*-fpm; do
  [[ -x "$s" ]] && systemctl reload "$(basename "$s")" 2>/dev/null || true
done

# 3) Recharger Apache
if command -v apachectl &>/dev/null; then
  apachectl configtest 2>/dev/null && systemctl reload apache2 2>/dev/null || true
  echo -e "${GREEN}✓ Apache rechargé${NC}"
fi

# 4) Supprimer la base et l'utilisateur MariaDB
mysql_root=$(get_password "mariadb")
if [[ -n "$mysql_root" ]]; then
  mysql -u root -p"$mysql_root" -e "DROP DATABASE IF EXISTS \`$sysuser\`; DROP USER IF EXISTS '$sysuser'@'localhost'; FLUSH PRIVILEGES;" 2>/dev/null && \
    echo -e "${GREEN}✓ Base et utilisateur MySQL supprimés${NC}" || \
    echo -e "${YELLOW}Attention: échec ou partiel MySQL (base/user $sysuser)${NC}"
else
  echo -e "${YELLOW}Mot de passe MariaDB non trouvé dans ${ROOT}/.passwords — base/user $sysuser non supprimés.${NC}"
fi

# 5) Supprimer le dossier home et l'utilisateur système
# Retirer les attributs chattr (+a append-only, +i immutable) posés par vhost_apache.sh sur logs/
if [[ -d "/home/$sysuser" ]] && command -v chattr &>/dev/null; then
  chattr -R -a -i "/home/$sysuser" 2>/dev/null || true
fi
if getent passwd "$sysuser" &>/dev/null; then
  userdel -r -f "$sysuser" 2>/dev/null && echo -e "${GREEN}✓ Utilisateur et /home/$sysuser supprimés${NC}" || {
    echo -e "${YELLOW}userdel a échoué (processus en cours ?). Suppression manuelle du home.${NC}"
    rm -rf "/home/$sysuser" || echo -e "${YELLOW}Impossible de supprimer tout /home/$sysuser (vérifier attributs/permissions).${NC}"
  }
else
  if [[ -d "/home/$sysuser" ]]; then
    rm -rf "/home/$sysuser" && echo -e "${GREEN}✓ Dossier /home/$sysuser supprimé${NC}" || echo -e "${YELLOW}Impossible de supprimer /home/$sysuser.${NC}"
  fi
fi

# 6) Supprimer les fichiers .installed
rm -f "$INSTALLED_FILE"
rm -f "${INSTALLED_DIR}/${VHOST_NAME}.installed"
echo -e "${GREEN}✓ Fichiers .installed supprimés${NC}"

echo ""
echo -e "${GREEN}Vhost $VHOST_NAME désinstallé.${NC}"
