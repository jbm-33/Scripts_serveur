#!/usr/bin/env bash
set -euo pipefail

# Script d'installation Extract Data (Metabase exports)
# - Installe l'app dans /home/<user>/app
# - Repère le user via le fichier /home/<user>/.extractMeta
# - Lit user/mdp BDD dans /root/Devops/<nom>.installed (ligne 1 = user = nom de la base, ligne 2 = mdp)
#   Il peut y avoir plusieurs fichiers .installed ; passer le <nom> en argument pour en choisir un.
# - Si REPO_BUCKET_URL est défini (URL du bucket ou archive du dépôt), le script télécharge le code
#   au lieu d'utiliser le répertoire courant. Exemple: REPO_BUCKET_URL=https://storage.example.com/repo.zip
# À lancer en root (depuis la racine du dépôt si REPO_BUCKET_URL n'est pas défini).

DEVOPS_DIR="/root/Devops"
INSTALLED_NAME="${1:-}"

# --- Chemin / URL du dépôt : à remplir ci-dessous (ou via variable d'environnement REPO_BUCKET_URL) ---
# Si défini, le script télécharge le code depuis cette URL. Sinon, il utilise le répertoire courant.
# Formats supportés : .zip, .tar.gz, .tgz, ou URL git (.git)
REPO_BUCKET_URL_DEFAULT=""
REPO_BUCKET_URL="${REPO_BUCKET_URL:-$REPO_BUCKET_URL_DEFAULT}"

INSTALL_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMP_REPO_DIR=""

# --- Vérifications préalables ---
if [[ "$(id -u)" -ne 0 ]]; then
  echo "Erreur: ce script doit être exécuté en root." >&2
  exit 1
fi

# --- Télécharger le dépôt depuis le bucket si REPO_BUCKET_URL est défini ---
if [[ -n "$REPO_BUCKET_URL" ]]; then
  TEMP_REPO_DIR=$(mktemp -d)
  trap "rm -rf '$TEMP_REPO_DIR'" EXIT
  echo "Téléchargement du dépôt depuis: $REPO_BUCKET_URL"
  if [[ "$REPO_BUCKET_URL" == *.git ]]; then
    git clone --depth 1 "$REPO_BUCKET_URL" "$TEMP_REPO_DIR" || {
      echo "Erreur: échec du clone git." >&2
      exit 1
    }
  elif [[ "$REPO_BUCKET_URL" == *.zip ]]; then
    (cd "$TEMP_REPO_DIR" && curl -sL "$REPO_BUCKET_URL" -o archive.zip && unzip -q -o archive.zip && rm -f archive.zip) || {
      echo "Erreur: échec du téléchargement ou extraction du zip." >&2
      exit 1
    }
  elif [[ "$REPO_BUCKET_URL" == *.tar.gz ]] || [[ "$REPO_BUCKET_URL" == *.tgz ]]; then
    curl -sL "$REPO_BUCKET_URL" | tar xz -C "$TEMP_REPO_DIR" || {
      echo "Erreur: échec du téléchargement ou extraction de l'archive." >&2
      exit 1
    }
  else
    echo "Erreur: REPO_BUCKET_URL doit être une URL .zip, .tar.gz, .tgz ou .git" >&2
    exit 1
  fi
  # Trouver le répertoire qui contient app/ (extraction peut créer un sous-dossier)
  if [[ -d "${TEMP_REPO_DIR}/app" ]]; then
    INSTALL_SCRIPT_DIR="$TEMP_REPO_DIR"
  else
    FOUND=$(find "$TEMP_REPO_DIR" -maxdepth 2 -type d -name app 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
      INSTALL_SCRIPT_DIR="$(dirname "$FOUND")"
    else
      echo "Erreur: archive invalide (aucun dossier app/ trouvé)." >&2
      exit 1
    fi
  fi
  echo "Source du code: $INSTALL_SCRIPT_DIR"
fi

if [[ ! -d "${INSTALL_SCRIPT_DIR}/app" ]]; then
  echo "Erreur: répertoire app/ introuvable (exécuter depuis la racine du dépôt ou définir REPO_BUCKET_URL)." >&2
  exit 1
fi

# --- Trouver le répertoire home cible (présence de .extractMeta) ---
TARGET_HOME=""
for home_dir in /home/*/; do
  if [[ -f "${home_dir}.extractMeta" ]]; then
    if [[ -n "$TARGET_HOME" ]]; then
      echo "Erreur: plusieurs répertoires /home/*/ contiennent .extractMeta." >&2
      exit 1
    fi
    TARGET_HOME="${home_dir%/}"
  fi
done

if [[ -z "$TARGET_HOME" ]]; then
  echo "Erreur: aucun répertoire /home/<user> ne contient .extractMeta." >&2
  echo "Créez par exemple: mkdir -p /home/deploy && touch /home/deploy/.extractMeta" >&2
  exit 1
fi

TARGET_USER="$(basename "$TARGET_HOME")"
APP_DIR="${TARGET_HOME}/app"

echo "Cible: $APP_DIR (utilisateur: $TARGET_USER)"

# --- Choisir le fichier .installed (plusieurs possibles dans /root/Devops/) ---
if [[ -n "$INSTALLED_NAME" ]]; then
  INSTALLED_FILE="${DEVOPS_DIR}/${INSTALLED_NAME}.installed"
  if [[ ! -f "$INSTALLED_FILE" ]]; then
    echo "Erreur: fichier $INSTALLED_FILE introuvable." >&2
    exit 1
  fi
else
  INSTALLED_FILES=("${DEVOPS_DIR}"/*.installed)
  if [[ ! -e "${INSTALLED_FILES[0]}" ]]; then
    echo "Erreur: aucun fichier *.installed dans $DEVOPS_DIR." >&2
    echo "Créez par exemple $DEVOPS_DIR/extract_data.installed (ligne 1 = user BDD, ligne 2 = mdp)." >&2
    exit 1
  fi
  if [[ ${#INSTALLED_FILES[@]} -gt 1 ]]; then
    echo "Plusieurs fichiers .installed trouvés. Indiquez lequel utiliser en argument:" >&2
    for f in "${INSTALLED_FILES[@]}"; do
      echo "  $(basename "$f" .installed)" >&2
    done
    echo "Exemple: $0 $(basename "${INSTALLED_FILES[0]}" .installed)" >&2
    exit 1
  fi
  INSTALLED_FILE="${INSTALLED_FILES[0]}"
fi

echo "Fichier BDD: $INSTALLED_FILE"

# --- Lire les identifiants BDD (ligne 1 = user = nom de la base, ligne 2 = mdp) ---
DB_USER="$(sed -n '1p' "$INSTALLED_FILE" | tr -d '\r\n' | xargs)"
DB_PASS="$(sed -n '2p' "$INSTALLED_FILE" | tr -d '\r\n' | xargs)" || true

if [[ -z "$DB_USER" ]]; then
  echo "Erreur: la première ligne de $INSTALLED_FILE doit contenir le nom d'utilisateur (et nom de base)." >&2
  exit 1
fi

# Nom de la base = user
DB_NAME="$DB_USER"
# Encodage du mot de passe pour l'URI (éviter caractères spéciaux)
DB_PASS_ENC="$DB_PASS"
if command -v python3 &>/dev/null && [[ -n "$DB_PASS" ]]; then
  DB_PASS_ENC=$(printf '%s' "$DB_PASS" | python3 -c "import sys, urllib.parse; print(urllib.parse.quote(sys.stdin.read().strip()))" 2>/dev/null) || DB_PASS_ENC="$DB_PASS"
fi

DATABASE_URL="mysql://${DB_USER}:${DB_PASS_ENC}@127.0.0.1:3306/${DB_NAME}?serverVersion=mariadb-10.6"

# --- Copie ou mise à jour du code ---
if [[ -d "$APP_DIR" ]]; then
  echo "Mise à jour de $APP_DIR..."
  rsync -a --delete --exclude='.env' --exclude='var/' "${INSTALL_SCRIPT_DIR}/app/" "$APP_DIR/"
else
  echo "Création de $APP_DIR..."
  mkdir -p "$APP_DIR"
  rsync -a --exclude='.env' --exclude='var/' "${INSTALL_SCRIPT_DIR}/app/" "$APP_DIR/"
fi

# --- Dépendances PHP ---
echo "Installation des dépendances Composer..."
(cd "$APP_DIR" && composer install --no-dev --optimize-autoloader --no-interaction 2>/dev/null) || {
  echo "Composer install a échoué (vérifier PHP et composer)." >&2
  exit 1
}

# --- Fichier .env ---
if [[ ! -f "${APP_DIR}/.env" ]]; then
  cp "${APP_DIR}/.env.example" "${APP_DIR}/.env"
fi

# Remplacer ou ajouter DATABASE_URL (éviter sed avec caractères spéciaux)
if grep -q '^DATABASE_URL=' "${APP_DIR}/.env"; then
  grep -v '^DATABASE_URL=' "${APP_DIR}/.env" > "${APP_DIR}/.env.tmp"
  echo "DATABASE_URL=\"${DATABASE_URL}\"" >> "${APP_DIR}/.env.tmp"
  mv "${APP_DIR}/.env.tmp" "${APP_DIR}/.env"
else
  echo "DATABASE_URL=\"${DATABASE_URL}\"" >> "${APP_DIR}/.env"
fi

# APP_ENV prod si pas déjà défini
if ! grep -q '^APP_ENV=' "${APP_DIR}/.env"; then
  echo "APP_ENV=prod" >> "${APP_DIR}/.env"
fi
if ! grep -q '^APP_DEBUG=' "${APP_DIR}/.env"; then
  echo "APP_DEBUG=0" >> "${APP_DIR}/.env"
fi

# --- Schéma BDD ---
echo "Mise à jour du schéma Doctrine..."
(cd "$APP_DIR" && php bin/console doctrine:schema:update --force --no-interaction) || true

# --- Droits ---
mkdir -p "${APP_DIR}/var"
chown -R "${TARGET_USER}:${TARGET_USER}" "$APP_DIR"
chmod -R 775 "${APP_DIR}/var" 2>/dev/null || true

echo "Installation terminée: $APP_DIR"
echo "Document root à configurer: ${APP_DIR}/public"
echo "Base de données: ${DB_NAME} (user: ${DB_USER})"
