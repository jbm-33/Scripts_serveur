#!/bin/bash
#
# Sauvegarde du dossier Devops (mots de passe, configs, règles iptables).
# Optionnel : dumps MongoDB et MariaDB.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"

BACKUP_DIR="${DEVOPS_ROOT}/backups"
mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

STAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/devops_${STAMP}.tar.gz"
TMPDIR=$(mktemp -d)
trap "rm -rf '$TMPDIR'" EXIT

echo "Sauvegarde Devops vers $ARCHIVE"

# Copier le contenu Devops (sans les backups pour éviter imbrication)
mkdir -p "$TMPDIR/devops"
for f in .passwords .iptables.rules .ip6tables.rules .vhost_config .motd_config .smtp_config; do
    [ -e "${DEVOPS_ROOT}/$f" ] && cp -a "${DEVOPS_ROOT}/$f" "$TMPDIR/devops/"
done
[ -d "${DEVOPS_ROOT}/configs" ] && cp -a "${DEVOPS_ROOT}/configs" "$TMPDIR/devops/"
[ -d "${DEVOPS_ROOT}/sites" ] && cp -a "${DEVOPS_ROOT}/sites" "$TMPDIR/devops/"
[ -d "${DEVOPS_ROOT}/installed" ] && cp -a "${DEVOPS_ROOT}/installed" "$TMPDIR/devops/"
[ -f "${DEVOPS_ROOT}/.restore_iptables.sh" ] && cp -a "${DEVOPS_ROOT}/.restore_iptables.sh" "$TMPDIR/devops/"

# Dump MongoDB (optionnel)
if command -v mongodump &>/dev/null && systemctl is-active --quiet mongod 2>/dev/null; then
    DUMP_MONGO="${TMPDIR}/mongodb_dump_${STAMP}"
    mkdir -p "$DUMP_MONGO"
    mongodump --out="$DUMP_MONGO" --quiet 2>/dev/null || true
    if [ -d "$DUMP_MONGO" ] && [ -n "$(find "$DUMP_MONGO" -maxdepth 1 -mindepth 1 2>/dev/null)" ]; then
        echo "  + dump MongoDB inclus"
    else
        rm -rf "$DUMP_MONGO"
    fi
fi

# Dump MariaDB (optionnel, sans mot de passe = échec silencieux)
if command -v mysqldump &>/dev/null && systemctl is-active --quiet mariadb 2>/dev/null; then
    MYSQL_PASS=$(get_password "mariadb")
    if [ -n "$MYSQL_PASS" ]; then
        MYSQL_DUMP="${TMPDIR}/mariadb_dump_${STAMP}.sql"
        mysqldump -u root -p"$MYSQL_PASS" --all-databases --single-transaction --routines --triggers > "$MYSQL_DUMP" 2>/dev/null || true
        if [ -s "$MYSQL_DUMP" ]; then
            echo "  + dump MariaDB inclus"
        else
            rm -f "$MYSQL_DUMP"
        fi
    fi
fi

tar czf "$ARCHIVE" -C "$TMPDIR" .
chmod 600 "$ARCHIVE"
echo "✓ Archive créée : $ARCHIVE"
