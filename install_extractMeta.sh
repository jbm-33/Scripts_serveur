#!/usr/bin/env bash
set -euo pipefail

# Script d'installation Extract Data (Metabase exports)
# Ordre : 1) Créer le vhost (vhost_apache.sh), 2) Créer /home/<user>/app et y ajouter .extract_data, 3) Dérouler l'installation (code, composer, .env, doctrine).
# - Argument unique : FQDN du vhost (ex. extract.gazoleen.gzl). Le vhost est créé en premier ; user système et MySQL viennent de vhost_apache.sh (sites/<FQDN>.installed).
# - Si REPO_BUCKET_URL est défini, le script télécharge le code depuis cette URL ; sinon répertoire courant ou défaut (Metabase).
# À lancer en root.

DEVOPS_DIR="/root/Devops"
VHOST_FQDN="${1:-}"

# Racine du dépôt Scripts_serveur (pour appeler scripts/vhost_apache.sh même si REPO_BUCKET_URL est utilisé)
SCRIPT_OWN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_OWN_DIR}/scripts/utils.sh"

# --- Chemin / URL du dépôt : à remplir ci-dessous (ou via variable d'environnement REPO_BUCKET_URL) ---
# Si défini, le script télécharge le code depuis cette URL. Sinon, il utilise le répertoire courant.
# Formats supportés : .zip, .tar.gz, .tgz, ou URL git (.git)
REPO_BUCKET_URL_DEFAULT="git@github.com:jbm-33/Metabase.git"
REPO_BUCKET_URL="${REPO_BUCKET_URL:-$REPO_BUCKET_URL_DEFAULT}"

# Répertoire local (si pas de REPO_BUCKET_URL) = racine du script (doit contenir app/)
INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Vérifications préalables ---
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Erreur: ce script doit être exécuté en root." >&2
  exit 1
fi

# --- Argument 1 (FQDN vhost) requis : on crée le vhost en premier ---
if [[ -z "$VHOST_FQDN" ]]; then
  echo "Erreur: le FQDN du vhost est requis. Exemple: $0 extract.gazoleen.gzl" >&2
  exit 1
fi

# --- 1) Créer le vhost Apache (vhost_apache.sh crée l'utilisateur système) ---
VHOST_SCRIPT="${SCRIPT_OWN_DIR}/scripts/vhost_apache.sh"
if [[ ! -x "$VHOST_SCRIPT" ]]; then
  echo "Erreur: $VHOST_SCRIPT introuvable ou non exécutable." >&2
  exit 1
fi
echo "Création du vhost Apache: $VHOST_FQDN..."
bash "$VHOST_SCRIPT" -a "extract@localhost" -n "$VHOST_FQDN" -y "" -p "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null || echo "8.1")" -l 0 || {
  echo "Erreur lors de la création du vhost." >&2
  exit 1
}

# --- Lire l'utilisateur créé par le vhost (fichier nommé d'après le vhost : sites/<nom_du_vhost>.installed) ---
SITES_INSTALLED="${DEVOPS_DIR}/sites/${VHOST_FQDN}.installed"
if [[ ! -f "$SITES_INSTALLED" ]]; then
  echo "Erreur: fichier $SITES_INSTALLED introuvable après création du vhost." >&2
  exit 1
fi
TARGET_USER="$(grep -E "^login:" "$SITES_INSTALLED" 2>/dev/null | cut -d: -f2- | tr -d '\r\n ')"
if [[ -z "$TARGET_USER" ]]; then
  echo "Erreur: impossible de lire le login dans $SITES_INSTALLED." >&2
  exit 1
fi
# Identifiants MySQL (créés par vhost_apache.sh, dans le même fichier)
DB_USER="$(grep -E "^loginmysql:" "$SITES_INSTALLED" 2>/dev/null | cut -d: -f2- | tr -d '\r\n ')"
DB_PASS="$(grep -E "^passsxmysql:" "$SITES_INSTALLED" 2>/dev/null | cut -d: -f2- | tr -d '\r\n ')"
if [[ -z "$DB_USER" ]]; then
  echo "Erreur: impossible de lire loginmysql dans $SITES_INSTALLED." >&2
  exit 1
fi

# S'assurer que l'utilisateur et la base MySQL existent (au cas où vhost_apache.sh n'a pas pu les créer)
MYSQL_ROOT="$(get_password "mariadb")"
if [[ -n "$MYSQL_ROOT" ]] && [[ -n "$DB_PASS" ]]; then
  MYSQL_SQL="CREATE USER IF NOT EXISTS '${DB_USER}'@'localhost' IDENTIFIED BY '${DB_PASS}';
CREATE USER IF NOT EXISTS '${DB_USER}'@'127.0.0.1' IDENTIFIED BY '${DB_PASS}';
CREATE DATABASE IF NOT EXISTS \`${DB_USER}\`;
GRANT ALL PRIVILEGES ON \`${DB_USER}\`.* TO '${DB_USER}'@'localhost';
GRANT ALL PRIVILEGES ON \`${DB_USER}\`.* TO '${DB_USER}'@'127.0.0.1';
FLUSH PRIVILEGES;"
  if echo "$MYSQL_SQL" | mysql --database=mysql -u root -p"$MYSQL_ROOT" 2>/dev/null; then
    echo "✓ Utilisateur et base MySQL ${DB_USER} créés ou déjà présents."
  else
    echo "Attention: création MySQL échouée (vérifier mot de passe root dans ${DEVOPS_ROOT}/.passwords)." >&2
  fi
elif [[ -z "$MYSQL_ROOT" ]]; then
  echo "Attention: mot de passe MariaDB root non trouvé dans ${DEVOPS_ROOT}/.passwords — si l'utilisateur ${DB_USER} n'existe pas, doctrine:schema:update échouera." >&2
fi

TARGET_HOME="/home/${TARGET_USER}"
# Répertoire du dépôt (clone Git) ou de l’app (copie) ; évite /home/user/app/app quand le dépôt a un sous-dossier app/
APP_DIR="${TARGET_HOME}/app"
APPLICATION_ROOT=""

# --- 2) Créer /home/<user>/app (dépôt Git ou copie) ---
echo "Cible: $APP_DIR (utilisateur: $TARGET_USER)"
if [[ -n "$REPO_BUCKET_URL" ]]; then
  if [[ "$REPO_BUCKET_URL" == *.git ]]; then
    # Clone Git dans app/ : on garde .git pour git pull
    rm -rf "$APP_DIR"
    echo "Clone du dépôt Git dans $APP_DIR depuis: $REPO_BUCKET_URL"
    git clone --depth 1 "$REPO_BUCKET_URL" "$APP_DIR" || {
      echo "Erreur: échec du clone git." >&2
      exit 1
    }
    if [[ -d "${APP_DIR}/app" ]] && [[ -f "${APP_DIR}/app/composer.json" ]]; then
      APPLICATION_ROOT="${APP_DIR}/app"
    else
      APPLICATION_ROOT="${APP_DIR}"
    fi
    touch "${APPLICATION_ROOT}/.extract_data"
    DEPLOY_ROOT="$APP_DIR"
    echo "Code déployé dans $APP_DIR (dépôt Git ; application dans ${APPLICATION_ROOT})"
  else
    # Archive (zip, tar) : téléchargement puis copie (sans .git)
    DOWNLOAD_DIR="${TARGET_HOME}/.repo_extract_meta"
    rm -rf "$DOWNLOAD_DIR"
    mkdir -p "$DOWNLOAD_DIR" "$APP_DIR"
    echo "Téléchargement dans ${DOWNLOAD_DIR} depuis: $REPO_BUCKET_URL"
    if [[ "$REPO_BUCKET_URL" == *.zip ]]; then
      (cd "$DOWNLOAD_DIR" && curl -sL "$REPO_BUCKET_URL" -o archive.zip && unzip -q -o archive.zip && rm -f archive.zip) || {
        echo "Erreur: échec du téléchargement ou extraction du zip." >&2
        exit 1
      }
    elif [[ "$REPO_BUCKET_URL" == *.tar.gz ]] || [[ "$REPO_BUCKET_URL" == *.tgz ]]; then
      curl -sL "$REPO_BUCKET_URL" | tar xz -C "$DOWNLOAD_DIR" || {
        echo "Erreur: échec du téléchargement ou extraction de l'archive." >&2
        exit 1
      }
    else
      echo "Erreur: REPO_BUCKET_URL doit être une URL .zip, .tar.gz, .tgz ou .git" >&2
      exit 1
    fi
    if [[ -d "${DOWNLOAD_DIR}/app" ]]; then
      SOURCE_APP="${DOWNLOAD_DIR}/app"
    else
      FOUND=$(find "$DOWNLOAD_DIR" -maxdepth 2 -type d -name app 2>/dev/null | head -1)
      if [[ -n "$FOUND" ]]; then
        SOURCE_APP="$FOUND"
      else
        echo "Erreur: archive invalide (aucun dossier app/ trouvé)." >&2
        rm -rf "$DOWNLOAD_DIR"
        exit 1
      fi
    fi
    rsync -a --exclude='.env' --exclude='var/' "$SOURCE_APP/" "$APP_DIR/"
    rm -rf "$DOWNLOAD_DIR"
    APPLICATION_ROOT="${APP_DIR}"
    DEPLOY_ROOT="${APP_DIR}"
    touch "${APPLICATION_ROOT}/.extract_data"
    echo "Code déployé dans $APP_DIR"
  fi
else
  if [[ ! -d "${INSTALL_SCRIPT_DIR}/app" ]]; then
    echo "Erreur: répertoire app/ introuvable (exécuter depuis la racine du dépôt ou définir REPO_BUCKET_URL)." >&2
    exit 1
  fi
  mkdir -p "$APP_DIR"
  APPLICATION_ROOT="${APP_DIR}"
  DEPLOY_ROOT="${APP_DIR}"
  touch "${APPLICATION_ROOT}/.extract_data"
fi
echo "Cible: $APPLICATION_ROOT (utilisateur: $TARGET_USER)"

# Nom de la base = user MySQL (créé par vhost_apache.sh)
DB_NAME="$DB_USER"
# Encodage du mot de passe pour l'URI (éviter caractères spéciaux)
DB_PASS_ENC="$DB_PASS"
if command -v python3 &>/dev/null && [[ -n "$DB_PASS" ]]; then
  DB_PASS_ENC=$(printf '%s' "$DB_PASS" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null) || DB_PASS_ENC="$DB_PASS"
fi

DATABASE_URL="mysql://${DB_USER}:${DB_PASS_ENC}@127.0.0.1:3306/${DB_NAME}?serverVersion=mariadb-11.8.3"

# --- 3) Déploiement du code local (si pas d’URL) ---
if [[ -z "$REPO_BUCKET_URL" ]]; then
  echo "Déploiement du code (local) vers $APP_DIR..."
  rsync -a --exclude='.env' --exclude='var/' --exclude='.extract_data' "${INSTALL_SCRIPT_DIR}/app/" "$APP_DIR/"
  touch "${APPLICATION_ROOT}/.extract_data"
fi

# --- Document root du vhost : pointer data/www vers application/public ---
DATA_WWW="${TARGET_HOME}/data/www"
if [[ -d "$DATA_WWW" ]]; then
  rm -rf "$DATA_WWW"
  ln -sfn "${APPLICATION_ROOT}/public" "$DATA_WWW"
  chown -h "${TARGET_USER}:users" "$DATA_WWW" 2>/dev/null || true
  echo "Document root du vhost pointé vers: ${APPLICATION_ROOT}/public"
fi

# --- Composer : installé en système si absent (disponible pour l'utilisateur du vhost) ---
COMPOSER_BIN="/usr/local/bin/composer"
if [[ ! -x "$COMPOSER_BIN" ]]; then
  echo "Installation de Composer dans $COMPOSER_BIN..."
  COMPOSER_SETUP="/tmp/composer-setup.php"
  if command -v curl &>/dev/null; then
    curl -sS https://getcomposer.org/installer -o "$COMPOSER_SETUP"
  elif command -v wget &>/dev/null; then
    wget -q https://getcomposer.org/installer -O "$COMPOSER_SETUP"
  else
    php -r "copy('https://getcomposer.org/installer', '$COMPOSER_SETUP');"
  fi
  php "$COMPOSER_SETUP" -- --install-dir="$(dirname "$COMPOSER_BIN")" --filename=composer
  rm -f "$COMPOSER_SETUP"
  chmod 755 "$COMPOSER_BIN"
  echo "✓ Composer installé."
fi
COMPOSER_CMD="$COMPOSER_BIN"

# --- Dépendances PHP (composer doit pouvoir écrire composer.lock et vendor/) ---
chown -R "${TARGET_USER}:users" "$DEPLOY_ROOT"
echo "Installation des dépendances Composer..."
if ! su -s /bin/bash "$TARGET_USER" -c "cd '$APPLICATION_ROOT' && $COMPOSER_CMD install --no-dev --optimize-autoloader --no-interaction"; then
  echo "Composer install a échoué (voir message ci-dessus ; vérifier PHP et extensions)." >&2
  exit 1
fi

# --- Fichier .env ---
if [[ ! -f "${APPLICATION_ROOT}/.env" ]]; then
  cp "${APPLICATION_ROOT}/.env.dist" "${APPLICATION_ROOT}/.env"
fi

# Remplacer ou ajouter DATABASE_URL (éviter sed avec caractères spéciaux)
if grep -q '^DATABASE_URL=' "${APPLICATION_ROOT}/.env"; then
  grep -v '^DATABASE_URL=' "${APPLICATION_ROOT}/.env" > "${APPLICATION_ROOT}/.env.tmp"
  echo "DATABASE_URL=\"${DATABASE_URL}\"" >> "${APPLICATION_ROOT}/.env.tmp"
  mv "${APPLICATION_ROOT}/.env.tmp" "${APPLICATION_ROOT}/.env"
else
  echo "DATABASE_URL=\"${DATABASE_URL}\"" >> "${APPLICATION_ROOT}/.env"
fi

# APP_ENV prod si pas déjà défini
if ! grep -q '^APP_ENV=' "${APPLICATION_ROOT}/.env"; then
  echo "APP_ENV=prod" >> "${APPLICATION_ROOT}/.env"
fi
if ! grep -q '^APP_DEBUG=' "${APPLICATION_ROOT}/.env"; then
  echo "APP_DEBUG=0" >> "${APPLICATION_ROOT}/.env"
fi

# --- Schéma BDD ---
echo "Mise à jour du schéma Doctrine..."
(cd "$APPLICATION_ROOT" && php bin/console doctrine:schema:update --force --no-interaction) || true

# --- Droits ---
mkdir -p "${APPLICATION_ROOT}/var"
chown -R "${TARGET_USER}:users" "$DEPLOY_ROOT"
chmod -R 775 "${APPLICATION_ROOT}/var" 2>/dev/null || true

echo "Installation terminée: $APPLICATION_ROOT"
echo "Document root: ${APPLICATION_ROOT}/public"
[[ -d "${DEPLOY_ROOT}/.git" ]] && echo "Pour mettre à jour le code : cd $DEPLOY_ROOT && git pull ; cd $APPLICATION_ROOT && /usr/local/bin/composer install --no-dev --optimize-autoloader"
echo "Base de données: ${DB_NAME} (user: ${DB_USER})"
[[ -n "$VHOST_FQDN" ]] && echo "Vhost Apache: $VHOST_FQDN"
