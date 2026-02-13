#!/bin/bash
#
# Configure le bandeau de connexion (MOTD) avec le nom du serveur,
# hostname, IP, uptime, charge, mémoire, OS.
# Style type "Message of the Day" à la connexion SSH.
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
ROOT="${DEVOPS_ROOT}"
MOTD_CONFIG="${ROOT}/.motd_config"

# Créer le dossier Devops si besoin
mkdir -p "$ROOT"
chmod 700 "$ROOT" 2>/dev/null || true

echo "========================================="
echo "Configuration du bandeau de connexion (MOTD)"
echo "========================================="

# Demander le nom du serveur si fourni en argument
SERVER_NAME="${1:-}"
if [ -n "$SERVER_NAME" ]; then
    echo "Nom du serveur: $SERVER_NAME"
elif [ -r "$MOTD_CONFIG" ]; then
    SERVER_NAME=$(grep -E "^server_name:" "$MOTD_CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
fi

if [ -z "$SERVER_NAME" ]; then
    echo -n "Entrez le nom de votre serveur (ex: StackX, MonServeur): "
    read -r SERVER_NAME
fi

if [ -z "$SERVER_NAME" ]; then
    echo "Aucun nom fourni. Utilisation du hostname."
    SERVER_NAME=$(hostname -s 2>/dev/null || hostname)
fi

# Tagline et URL optionnels
TAGLINE="${2:-}"
URL="${3:-}"
if [ -r "$MOTD_CONFIG" ]; then
    [ -z "$TAGLINE" ] && TAGLINE=$(grep -E "^tagline:" "$MOTD_CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
    [ -z "$URL" ] && URL=$(grep -E "^url:" "$MOTD_CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
fi

# Créer ou mettre à jour la config
cat > "$MOTD_CONFIG" <<EOF
server_name:$SERVER_NAME
tagline:${TAGLINE:-}
url:${URL:-}
EOF
chmod 600 "$MOTD_CONFIG"

# Détecter la distribution
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-}"
    OS_PRETTY="${PRETTY_NAME:-$OS_ID $OS_VERSION}"
else
    OS_PRETTY="Linux"
fi

# Script MOTD dynamique (Debian/Ubuntu: update-motd.d)
MOTD_SCRIPT="/etc/update-motd.d/00-server-banner"

# Sur Debian/Ubuntu on utilise update-motd.d (MOTD dynamique à chaque connexion)
if [ -d /etc/update-motd.d ]; then
    [ -f /etc/update-motd.d/00-header ] && chmod -x /etc/update-motd.d/00-header 2>/dev/null || true

    cat > "$MOTD_SCRIPT" <<'MOTDSCRIPT'
#!/bin/bash
# Bandeau de connexion - Scripts_serveur

GREEN='\033[0;32m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
LIGHT_GREEN='\033[1;32m'
NC='\033[0m'

CONFIG="__DEVOPS_ROOT__/.motd_config"
[ ! -r "$CONFIG" ] && exit 0

server_name=$(grep -E "^server_name:" "$CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
tagline=$(grep -E "^tagline:" "$CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
url=$(grep -E "^url:" "$CONFIG" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')

[ -z "$server_name" ] && server_name=$(hostname -s 2>/dev/null || hostname)
hostname_fqdn=$(hostname -f 2>/dev/null || hostname)
ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}')
[ -z "$ip_addr" ] && ip_addr=$(ip -4 route get 8.8.8.8 2>/dev/null | grep -oP 'src \K[\d.]+')

uptime_info=$(uptime -p 2>/dev/null | sed 's/^up //') || uptime_info="N/A"
load=$(cat /proc/loadavg 2>/dev/null)
mem_info=$(free -m 2>/dev/null | awk '/^Mem:/{printf "%sM/%sM", $3, $2}') || mem_info="N/A"
os_info="Linux"
[ -r /etc/os-release ] && . /etc/os-release && os_info="${PRETTY_NAME:-$ID}"

echo -e "${WHITE}"
echo -e "  Welcome on a ${GREEN}${server_name}${NC} Server${tagline:+ ${LIGHT_GREEN}${tagline}${NC}}"
echo ""
echo -e "  Hostname: ${WHITE}${hostname_fqdn}${NC}"
echo -e "  IP:       ${WHITE}${ip_addr}${NC}"
[ -n "$url" ] && echo -e "  ${url}${NC}" && echo ""
echo -e "  Uptime:        ${CYAN}${uptime_info}${NC}"
echo -e "  Load Average:  ${CYAN}${load}${NC}"
echo -e "  Memory used:   ${CYAN}${mem_info}${NC}"
echo -e "  OS:            ${WHITE}${os_info}${NC}"
echo -e "${NC}"
MOTDSCRIPT
    sed -i "s|__DEVOPS_ROOT__|$DEVOPS_ROOT|g" "$MOTD_SCRIPT"

    chmod +x "$MOTD_SCRIPT"
    echo "✓ MOTD dynamique installé: $MOTD_SCRIPT"
else
    # Fallback: /etc/motd statique (autres distros)
    MOTD_STATIC="/etc/motd"
    cat > "$MOTD_STATIC" <<EOF

  Welcome on a ${SERVER_NAME} Server${TAGLINE:+ ${TAGLINE}}

  Hostname: $(hostname -f 2>/dev/null || hostname)
  IP:       $(hostname -I 2>/dev/null | awk '{print $1}')
  OS:       $OS_PRETTY

  (Re-exécutez install_motd.sh après connexion pour régénérer ce message)

EOF
    echo "✓ MOTD statique écrit dans $MOTD_STATIC"
fi

# Sauvegarder la config dans Devops
source "$SCRIPT_DIR/utils.sh" 2>/dev/null || true
setup_password_storage 2>/dev/null || true
if type save_config &>/dev/null; then
    save_config "motd" "$MOTD_CONFIG" "Configuration bandeau connexion"
fi

echo ""
echo -e "${GREEN}✓ Bandeau de connexion configuré${NC}"
echo "  Nom du serveur: $SERVER_NAME"
echo "  Config: $MOTD_CONFIG"
echo "  La prochaine connexion SSH affichera le bandeau."
