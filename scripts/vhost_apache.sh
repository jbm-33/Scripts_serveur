#!/bin/bash
#
# Création de vhosts Apache + pool PHP-FPM + utilisateur système + base MariaDB
# Intégré au projet Scripts_serveur - utilise DEVOPS_ROOT (utils.sh)
#
# Usage:
#   ./vhost_apache.sh -a "cust_mail" -n "vhostuwantinstall" -y "alias1 alias2" -p php_version -l 1 -i "IP"
#   -a  cust_mail (email client)
#   -n  nom du vhost (FQDN)
#   -y  alias (espaces ou virgules)
#   -p  version PHP (ex: 8.1, 8.2)
#   -l  1 = activer Let's Encrypt
#   -i  IP (optionnel, défaut: *)
#   -z  sysuser (optionnel, sinon généré)
#   -c  mot de passe sysuser (optionnel)
#   -b  mot de passe MySQL (optionnel)
#

set -e

RED='\033[38;5;160m'
NC='\033[0m'
GREEN='\033[38;1;32m'
YELLOW='\033[38;5;226m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

ROOT="${DEVOPS_ROOT}"
CUST_FILE="$ROOT/.vhost_config"
INSTALLED_DIR="$ROOT/installed"
SITES_DIR="$ROOT/sites"
MAILS_DIR="$ROOT/mails"

ncores=$(nproc 2>/dev/null || grep -c processor /proc/cpuinfo 2>/dev/null || echo 1)
pm_type='ondemand'
pm_max_children=$((ncores*16))
pm_start_servers=$((ncores*4))
pm_min_spare_servers=$((ncores*2))
pm_max_spare_servers=$((ncores*4))
pm_max_requests="1000"

# Chemins Apache (Debian/Ubuntu)
vhosts_conf='/etc/apache2/sites-available'
fpm_conf=''

options_found='0'
letsencrypt='0'
ipaddress='*'

# Charger les valeurs par défaut depuis .vhost_config
if [ -r "$CUST_FILE" ]; then
    admin_mail=$(grep -w "admin_mail" "$CUST_FILE" 2>/dev/null | cut -d ":" -f2-)
    cust_mail_default=$(grep -w "cust_mail" "$CUST_FILE" 2>/dev/null | cut -d ":" -f2-)
    [ -n "$cust_mail_default" ] && cust_mail="$cust_mail_default"
    [ -z "$ipaddress" ] && ipaddress=$(grep -w "ipaddress" "$CUST_FILE" 2>/dev/null | cut -d ":" -f2-)
    php_version=$(grep -w "php_version" "$CUST_FILE" 2>/dev/null | cut -d ":" -f2-)
fi
[ -z "$admin_mail" ] && admin_mail="admin@localhost"
mysql_root=$(get_password "mariadb")
[ -z "$php_version" ] && php_version=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")
fpm_conf="/etc/php/$php_version/fpm/pool.d"

function checkip() {
    if [[ "$1" == "*" ]] || [[ -z "$1" ]]; then
        echo -e "${GREEN} [ OK ]${NC} Using all interfaces (*)"
        return
    fi
    if [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
        echo -e "${GREEN} [ OK ]${NC} IP address $1 is ok, install in progress..."
    else
        echo -e "${RED} [ ERROR ]${NC} $1 is not a valid IP address"
        exit 1
    fi
}

function checkfqdn() {
    local fqdn="$1"
    # Au moins deux parties séparées par un point, caractères alphanumériques, tirets, points (sous-domaines autorisés)
    if [[ "$fqdn" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\.\-]*[a-zA-Z0-9])?\.([a-zA-Z0-9\-]+\.)*[a-zA-Z]{2,}$ ]]; then
        echo -e "${GREEN} [ OK ]${NC} $fqdn is a valid FQDN, install in progress..."
    else
        echo -e "${RED} [ ERROR ]${NC} $fqdn is not a valid FQDN"
        exit 1
    fi
}

function checkinstall() {
    local vhostname="$1"
    if [ -f "$INSTALLED_DIR/$vhostname.installed" ]; then
        echo -e "${RED} [ ERROR ]${NC} This vhost was already installed!"
        exit 1
    fi
    echo -e "${GREEN} [ OK ]${NC} This vhost has not been installed before, install in progress..."
}

function fixperms() {
    chown -R "$sysuser:users" /home/"$sysuser"
    chmod 705 /home/"$sysuser"
    chown -R "root:root" /home/"$sysuser"/logs
    if command -v chattr &>/dev/null; then
        chattr +a /home/"$sysuser"/logs 2>/dev/null || true
    fi
}

function writefile() {
    local option=$1
    local file2write="$2"
    local contentfile="$3"
    if [ "$option" = "add" ]; then
        echo "$contentfile" >> "$file2write"
    fi
    if [ "$option" = "create" ]; then
        cat > "$file2write" <<EOF
$contentfile
EOF
    fi
}

function servicesrestart() {
    apachectl configtest 2>/dev/null && systemctl reload apache2
    systemctl reload "php${php_version}-fpm" 2>/dev/null || true
}

# --- getopts ---
while getopts ":a:n:y:p:l:i:z:c:b:h" opt; do
    options_found=1
    case $opt in
        a) cust_mail="$OPTARG" ;;
        n) vhostname="$OPTARG" ;;
        y) vhostalias="$OPTARG" ;;
        p) php_version="$OPTARG"; fpm_conf="/etc/php/$php_version/fpm/pool.d" ;;
        l) letsencrypt="$OPTARG" ;;
        i) ipaddress="$OPTARG" ;;
        z) sysuser="$OPTARG" ;;
        c) sysuser_pass="$OPTARG" ;;
        b) mysql_pass="$OPTARG" ;;
        h)
            echo 'Usage: ./vhost_apache.sh -a "cust_mail" -n "vhost_fqdn" -y "alias1 alias2" -p php_version -l 1 -i "IP"'
            echo '  -a  cust_mail (email client)'
            echo '  -n  vhost FQDN'
            echo '  -y  ServerAlias (espaces ou virgules)'
            echo '  -p  php_version (ex: 8.1, 8.2)'
            echo '  -l  1 = Let''s Encrypt'
            echo '  -i  IP (optionnel, défaut: *)'
            echo '  -z  sysuser (optionnel)'
            echo '  -c  mot de passe sysuser (optionnel)'
            echo '  -b  mot de passe MySQL (optionnel)'
            exit 0
            ;;
        \?)
            echo -e "${RED} [ ERROR ]${NC} Invalid option: -$OPTARG" >&2
            exit 1
            ;;
        :)
            echo -e "${YELLOW} [ WARNING ]${NC} Option -$OPTARG requires an argument." >&2
            exit 1
            ;;
    esac
done

if [ "$options_found" -ne 1 ]; then
    echo -e "${RED} [ ERROR ]${NC} No options detected. Use -h for help."
    exit 1
fi

if [ -z "$vhostname" ]; then
    echo -e "${RED} [ ERROR ]${NC} -n vhostname is required."
    exit 1
fi

checkinstall "$vhostname"
checkfqdn "$vhostname"
checkip "$ipaddress"

# Vérification répertoires
mkdir -p "$INSTALLED_DIR" "$SITES_DIR" "$MAILS_DIR"
setup_password_storage

# Utilisateur système et mots de passe
prefix=$(genprefix 2)
tld=$(genpass 4)
usr=$(echo "$vhostname" | sed 's/\.//g' | sed 's/-//g' | cut -b 1-10)
vfixalias=$(echo "$vhostalias" | sed "s/ /,/g")

[ -z "$sysuser" ] && sysuser="${prefix}${usr}${tld}"
[ -z "$sysuser_pass" ] && sysuser_pass=$(genpass 12)
[ -z "$mysql_pass" ] && mysql_pass=$(genpass 12)

# Répertoires sous /home/$sysuser (chaque instance a ses propres logs)
mkdir -p "/home/$sysuser/data/www" "/home/$sysuser/logs/apache" "/home/$sysuser/cgi-bin"

# Contenu vhost HTTP (port 80) - utilisé pour Let's Encrypt ou seul
content_http="
# Vhost Scripts_serveur - $vhostname
<VirtualHost $ipaddress:80>
    ServerAdmin webmaster@$vhostname
    DocumentRoot /home/$sysuser/data/www
    ServerName $vhostname
    ServerAlias $vfixalias
    CustomLog /home/$sysuser/logs/apache/$vhostname.log combined
    ErrorLog /home/$sysuser/logs/apache/$vhostname-error.log
    ScriptAlias /cgi-bin/ /home/$sysuser/cgi-bin/

    <FilesMatch \\.php\$>
        SetHandler \"proxy:unix:/run/php/$vhostname.sock|fcgi://localhost/\"
    </FilesMatch>

    <Directory /home/$sysuser/data>
        Options -Indexes +FollowSymLinks +MultiViews
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
"

# Pool PHP-FPM
content_fpm="
; Pool $vhostname - Scripts_serveur
[$vhostname]

listen = /run/php/$vhostname.sock
listen.backlog = -1
listen.allowed_clients = 127.0.0.1
listen.owner = $sysuser
listen.group = www-data
listen.mode = 0660

user = $sysuser
group = users

pm = $pm_type
pm.max_children = $pm_max_children
pm.start_servers = $pm_start_servers
pm.min_spare_servers = $pm_min_spare_servers
pm.max_spare_servers = $pm_max_spare_servers
pm.max_requests = $pm_max_requests

pm.status_path = /phpfpm-status-$vhostname
ping.path = /phpfpm-ping-$vhostname
ping.response = pong

request_terminate_timeout = 0
request_slowlog_timeout = 0
slowlog = /var/log/php${php_version}-fpm/$vhostname-slow.log
chdir = /
catch_workers_output = no
"

# SQL MariaDB (localhost + 127.0.0.1 : l'app peut se connecter en TCP via 127.0.0.1)
content_genmysql2="
CREATE USER IF NOT EXISTS '$sysuser'@'localhost' IDENTIFIED BY '$mysql_pass';
CREATE USER IF NOT EXISTS '$sysuser'@'127.0.0.1' IDENTIFIED BY '$mysql_pass';
CREATE DATABASE IF NOT EXISTS \`$sysuser\`;
GRANT ALL PRIVILEGES ON \`$sysuser\`.* TO '$sysuser'@'localhost';
GRANT ALL PRIVILEGES ON \`$sysuser\`.* TO '$sysuser'@'127.0.0.1';
FLUSH PRIVILEGES;
"

# S'assurer que le groupe users existe, puis créer ou rattacher l'utilisateur
getent group users &>/dev/null || groupadd users
if ! getent passwd "$sysuser" &>/dev/null; then
    useradd "$sysuser" --shell /bin/bash -g users -m -d /home/"$sysuser"
    echo -e "${sysuser_pass}\n${sysuser_pass}" | passwd "$sysuser"
else
    # Utilisateur existant (ex. -z passé par install_extractMeta) : le rattacher au groupe users
    usermod -a -G users "$sysuser" 2>/dev/null || true
fi

# Fichier vhost Apache
writefile "create" "$vhosts_conf/$vhostname.conf" "$content_http"
a2ensite "$vhostname.conf" 2>/dev/null || true
apachectl configtest && systemctl reload apache2

# Let's Encrypt
if [ "$letsencrypt" = "1" ]; then
    if command -v certbot &>/dev/null; then
        a2enmod ssl 2>/dev/null || true
        certbot -n --agree-tos --email "$admin_mail" --apache -d "$vhostname" 2>/dev/null || true
    else
        echo -e "${YELLOW} [ WARNING ]${NC} certbot not found. Install with: apt install certbot python3-certbot-apache"
    fi
fi

# Pool PHP-FPM
writefile "create" "$fpm_conf/$vhostname.conf" "$content_fpm"

# MariaDB : créer utilisateur et base (root avec ou sans mdp : socket Unix ou .passwords)
echo "$content_genmysql2" > "$ROOT/sql2.sql"
if [ -n "$mysql_root" ]; then
    if mysql --database=mysql -u root -p"$mysql_root" < "$ROOT/sql2.sql" 2>/dev/null; then
        echo -e "${GREEN}✓ Utilisateur et base MySQL $sysuser créés${NC}"
    else
        echo -e "${YELLOW}Attention: création MySQL échouée (vérifier mot de passe root dans ${ROOT}/.passwords).${NC}" >&2
    fi
else
    if mysql --database=mysql -u root < "$ROOT/sql2.sql" 2>/dev/null; then
        echo -e "${GREEN}✓ Utilisateur et base MySQL $sysuser créés${NC}"
    else
        echo -e "${YELLOW}Attention: création MySQL échouée (root sans mdp attendu ? Vérifier ${ROOT}/.passwords si root a un mot de passe).${NC}" >&2
    fi
fi
rm -f "$ROOT/sql2.sql"

echo '<?php echo "OK"; ?>' > "/home/$sysuser/data/www/index.php"
fixperms
servicesrestart

# Marquer comme installé et sauvegarder les identifiants
touch "$INSTALLED_DIR/$vhostname.installed"

content_installed="vhost:$vhostname
ipaddress:$ipaddress
login:$sysuser
password:$sysuser_pass
loginmysql:$sysuser
passsxmysql:$mysql_pass"

writefile "create" "$SITES_DIR/$vhostname.installed" "$content_installed"
chmod 600 "$SITES_DIR/$vhostname.installed"

# Sauvegarde des configs dans Devops
save_config "vhost_$vhostname" "$vhosts_conf/$vhostname.conf" "Vhost Apache $vhostname"
save_config "vhost_$vhostname" "$fpm_conf/$vhostname.conf" "Pool PHP-FPM $vhostname"

# Email (optionnel)
content_mail="
Your website $vhostname has been correctly installed

Hostname: $vhostname
IP address: $ipaddress

Credentials:
------------------------------------------------------------------------
User SSH/FTP: $sysuser
Password: $sysuser_pass
Directory for web: data/www
------------------------------------------------------------------------
User MySQL: $sysuser
Database: $sysuser
MySQL password: $mysql_pass
------------------------------------------------------------------------
"
writefile "create" "$MAILS_DIR/$vhostname.installed.txt" "$content_mail"
if command -v mail &>/dev/null; then
    mail -s "[ $vhostname ] installed" "$cust_mail" < "$MAILS_DIR/$vhostname.installed.txt" 2>/dev/null || true
    [ -n "$admin_mail" ] && mail -s "[ $vhostname ] installed" "$admin_mail" < "$MAILS_DIR/$vhostname.installed.txt" 2>/dev/null || true
fi

echo -e "${GREEN} [ OK ]${NC} Vhost $vhostname installed."
echo "  User: $sysuser | Pass: $sysuser_pass | MySQL: $sysuser / $mysql_pass"
echo "  Credentials: $SITES_DIR/$vhostname.installed"
exit 0
