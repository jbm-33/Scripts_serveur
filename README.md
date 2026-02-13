# Scripts d'installation de serveur

Cette suite de scripts permet d'installer et de configurer automatiquement un serveur avec les services suivants :

- **PHP-FPM** : Interpréteur PHP avec FastCGI Process Manager
- **MongoDB** : Base de données NoSQL
- **MariaDB** : Base de données relationnelle
- **Apache** : Serveur web HTTP
- **Fail2ban** : Protection contre les attaques par force brute
- **Postfix** : Serveur SMTP pour l'envoi d'emails (commande `mail`, vhost, notifications)
- **iptables** : Pare-feu avec règles de sécurité

## Fonctionnalités

- Génération automatique de mots de passe sécurisés pour tous les services
- Sauvegarde sécurisée des mots de passe dans `/root/Devops/.passwords`
- Changement automatique du mot de passe root du système
- Configuration automatique de tous les services
- Configuration et sauvegarde des règles iptables
- Support des distributions Ubuntu, Debian, CentOS, RHEL et Fedora

## Prérequis

- Accès root (sudo ou utilisateur root)
- Connexion Internet active
- Distribution Linux supportée (Ubuntu, Debian, CentOS, RHEL, Fedora)

## Installation

1. **Cloner ou télécharger les scripts**

2. **Rendre les scripts exécutables** :
```bash
chmod +x install.sh
chmod +x scripts/*.sh
```

3. **Exécuter le script principal** :
```bash
sudo ./install.sh
```

**Options** :
- `-h`, `--help` : afficher l'aide
- `--skip-hostname` : ne pas demander le hostname
- `--skip=SERVICES` : ne pas installer certains services (séparés par des virgules)
- `--dry-run` : afficher les étapes sans exécuter (simulation)

Services pouvant être exclus : `php-fpm`, `mongodb`, `mariadb`, `apache`, `fail2ban`, `postfix`, `iptables`, `hardening`, `hostname`, `motd`

Exemples : `./install.sh --skip=mongodb,postfix`, `./install.sh --dry-run`.

**Logs** : chaque installation est enregistrée dans `${DEVOPS_ROOT}/logs/install_YYYYMMDD_HHMMSS.log` (affichage à l’écran + fichier). En cas d’erreur, un message indique le code de sortie.

Le script va :
- Changer le mot de passe root du système
- Installer et configurer tous les services
- Générer des mots de passe aléatoires pour chaque service
- Sauvegarder tous les mots de passe dans `/root/Devops/.passwords`
- Configurer et sauvegarder les règles iptables

## Structure des fichiers

```
Scripts_serveur/
├── install.sh                 # Script principal
├── .env.example               # Exemple de configuration (copier en .env)
├── config/
│   ├── vhost_config.example   # Exemple de config pour vhost Apache
│   ├── smtp_config.example    # Exemple de config relais SMTP
│   └── motd_config.example    # Exemple de config bandeau de connexion
├── scripts/
│   ├── utils.sh               # Fonctions utilitaires (mots de passe, configs)
│   ├── install_motd.sh        # Bandeau de connexion (MOTD) + nom du serveur
│   ├── set_hostname.sh        # Définir le hostname du serveur (saisie manuelle)
│   ├── install_php-fpm.sh     # Installation PHP-FPM
│   ├── install_mongodb.sh     # Installation MongoDB
│   ├── install_mariadb.sh     # Installation MariaDB
│   ├── install_apache.sh      # Installation Apache
│   ├── install_fail2ban.sh    # Installation Fail2ban
│   ├── install_postfix.sh     # Installation Postfix (SMTP)
│   ├── install_iptables.sh    # Installation iptables
│   ├── install_logrotate.sh   # Rotation des logs (Apache, PHP, MongoDB, MariaDB, fail2ban)
│   ├── install_certbot.sh     # Certbot / Let's Encrypt pour Apache
│   ├── vhost_apache.sh        # Création de vhosts Apache (voir ci-dessous)
│   ├── verify_services.sh    # Vérification post-install (état + connexions)
│   ├── backup_devops.sh       # Sauvegarde Devops (+ optionnel dumps MongoDB/MariaDB)
│   └── restore_configs.sh     # Restauration des .conf depuis configs/
└── README.md                  # Ce fichier
```

## Fichier .env et chemin Devops

Vous pouvez créer un fichier **`.env`** à la racine du projet (à côté de `install.sh`) pour centraliser la configuration. Tous les scripts qui chargent `scripts/utils.sh` le chargent automatiquement. Copier `.env.example` en `.env` et adapter (ex. `DEVOPS_ROOT=/opt/Devops`).

Tous les mots de passe, configurations et règles sont stockés dans un même dossier racine, défini par la variable **`DEVOPS_ROOT`** (défaut : `/root/Devops`).

Pour utiliser un autre chemin, exportez-la avant d’exécuter les scripts :

```bash
export DEVOPS_ROOT="/opt/Devops"
sudo -E ./install.sh
```

Tous les scripts qui chargent `scripts/utils.sh` utilisent cette variable. Priorité : variable d’environnement > fichier `.env` > défaut (`/root/Devops`).

## Gestion des mots de passe

Tous les mots de passe sont sauvegardés dans `${DEVOPS_ROOT}/.passwords` (par défaut `/root/Devops/.passwords`) avec les permissions suivantes :
- Dossier : `700` (lecture/écriture/exécution pour root uniquement)
- Fichier : `600` (lecture/écriture pour root uniquement)

### Format du fichier de mots de passe

```
service:utilisateur:mot_de_passe
```

Exemple :
```
system:root:AbCdEf123456...
mongodb:admin:XyZ789AbC...
mariadb:root:MnOp456QrS...
```

### Consulter les mots de passe

```bash
cat /root/Devops/.passwords
```

## Hostname du serveur

Le hostname peut être défini manuellement (ex. `srv01` ou `srv.example.com`). Lors de `install.sh`, répondez **o** pour le saisir ; sinon :

```bash
sudo ./scripts/set_hostname.sh
sudo ./scripts/set_hostname.sh "mon-serveur"
```

Mise à jour : hostname persistant, `/etc/hosts`, Postfix, MOTD. Reconnectez-vous en SSH après changement.

## Bandeau de connexion (MOTD)

À chaque connexion SSH, un bandeau affiche le **nom du serveur**, l’hostname, l’IP, l’uptime, la charge, la mémoire et l’OS (style « Message of the Day »).

### Configuration

- **Lors de l’installation** : le bandeau est configuré avec le hostname du serveur comme nom.
- **Personnaliser le nom** : exécuter une fois le script en donnant le nom souhaité (et optionnellement un sous-titre et une URL) :

```bash
# Nom du serveur uniquement
sudo ./scripts/install_motd.sh "Mon Serveur"

# Nom + sous-titre (ex: "by ScalarX") + URL
sudo ./scripts/install_motd.sh "StackX" "by ScalarX" "https://example.com"
```

Sans argument, le script demande le nom du serveur.

### Fichier de configuration

La configuration est enregistrée dans `/root/Devops/.motd_config` (format `clé:valeur`) :

- `server_name` : nom affiché du serveur  
- `tagline` : sous-titre (optionnel)  
- `url` : lien affiché (optionnel)  

Exemple : `config/motd_config.example`. Vous pouvez éditer `.motd_config` puis vous reconnecter pour voir le bandeau mis à jour (sur Debian/Ubuntu le MOTD est régénéré à chaque connexion).

### Compatibilité

- **Debian / Ubuntu** : script dynamique dans `/etc/update-motd.d/00-server-banner` (infos à jour à chaque connexion).
- **Autres distros** : message statique écrit dans `/etc/motd` (à régénérer en relançant le script si besoin).

## Gestion des règles iptables

Les règles iptables sont automatiquement sauvegardées dans `/root/Devops/` :
- **`.iptables.rules`** : Règles IPv4
- **`.ip6tables.rules`** : Règles IPv6
- **`.restore_iptables.sh`** : Script de restauration des règles

### Consulter les règles actuelles

```bash
# Afficher les règles IPv4
iptables -L -v -n

# Afficher les règles IPv6
ip6tables -L -v -n

# Afficher les règles sauvegardées
cat /root/Devops/.iptables.rules
```

### Sauvegarder manuellement les règles

```bash
# Sauvegarder les règles IPv4
iptables-save > /root/Devops/.iptables.rules

# Sauvegarder les règles IPv6
ip6tables-save > /root/Devops/.ip6tables.rules
```

### Restaurer les règles

```bash
# Utiliser le script de restauration
/root/Devops/.restore_iptables.sh

# Ou restaurer manuellement
iptables-restore < /root/Devops/.iptables.rules
ip6tables-restore < /root/Devops/.ip6tables.rules
```

### Modifier les règles

Les règles par défaut autorisent :
- **SSH** (port 22) : Accès depuis n'importe où
- **HTTP** (port 80) : Accès depuis n'importe où
- **HTTPS** (port 443) : Accès depuis n'importe où
- **Localhost** : Tous les ports
- **Connexions établies** : Trafic de retour

Pour ouvrir d'autres ports (par exemple MongoDB ou MariaDB depuis l'extérieur), modifiez le fichier `/root/Devops/.iptables.rules` ou utilisez directement `iptables` puis sauvegardez :

```bash
# Exemple : Autoriser MongoDB depuis l'extérieur
iptables -A INPUT -p tcp --dport 27017 -j ACCEPT
iptables-save > /root/Devops/.iptables.rules
```

## Gestion des fichiers de configuration (.conf)

Tous les fichiers de configuration importants sont automatiquement sauvegardés dans `/root/Devops/configs/` lors de l'installation :

### Fichiers sauvegardés

- **SSH** : `/etc/ssh/sshd_config`
- **Apache** : Configuration principale, sécurité, headers
- **PHP** : `php.ini`, `php-fpm.conf`
- **MongoDB** : `/etc/mongod.conf`
- **MariaDB** : `/etc/my.cnf`, configurations serveur
- **Fail2ban** : `/etc/fail2ban/jail.local`
- **Système** : Configurations mises à jour automatiques, sysctl, limites

### Consulter les configurations sauvegardées

```bash
# Lister toutes les configurations sauvegardées
ls -la /root/Devops/configs/

# Voir une configuration spécifique
cat /root/Devops/configs/apache_apache2.conf.backup
```

### Restaurer une configuration

```bash
# Utiliser la fonction de restauration (depuis un script)
source /path/to/scripts/utils.sh
restore_config "apache" "/etc/apache2/apache2.conf"

# Ou restaurer manuellement
cp /root/Devops/configs/apache_apache2.conf.backup /etc/apache2/apache2.conf
```

### Structure des sauvegardes

Chaque fichier est sauvegardé avec :
- Un backup avec timestamp : `service_filename.YYYYMMDD_HHMMSS`
- Un backup de la dernière version : `service_filename.backup`

Exemple :
```
/root/Devops/configs/
├── apache_apache2.conf.20241215_143022
├── apache_apache2.conf.backup
├── php_php.ini.20241215_143025
├── php_php.ini.backup
└── ...
```

## Création de vhosts Apache

Le script `scripts/vhost_apache.sh` permet de créer des vhosts Apache avec un pool PHP-FPM dédié, un utilisateur système, une base MariaDB et optionnellement Let's Encrypt.

**Prérequis** : Apache, PHP-FPM et MariaDB installés (via `install.sh`). Compatible Debian/Ubuntu (apache2, a2ensite).

### Usage

```bash
sudo ./scripts/vhost_apache.sh -a "email@client.com" -n "www.example.com" -y "example.com" -p 8.1 -l 1
```

### Options

| Option | Description |
|--------|-------------|
| `-a` | Email client (notifications) |
| `-n` | Nom du vhost (FQDN obligatoire) |
| `-y` | Alias (espaces ou virgules) |
| `-p` | Version PHP (ex: 8.1, 8.2) |
| `-l` | `1` = activer Let's Encrypt (certbot) |
| `-i` | IP (optionnel, défaut: `*`) |
| `-z` | Nom d'utilisateur système (optionnel, sinon généré) |
| `-c` | Mot de passe utilisateur (optionnel) |
| `-b` | Mot de passe MySQL (optionnel) |

### Fichier de configuration optionnel

Pour éviter de passer toutes les options à chaque fois, créez `/root/Devops/.vhost_config` (format `clé:valeur`) :

```bash
admin_mail:admin@votredomaine.com
cust_mail:client@votredomaine.com
ipaddress:*
php_version:8.1
```

Un exemple est fourni dans `config/vhost_config.example`.

### Envoi d'emails (Postfix)

Pour que le script vhost envoie les identifiants par email (et que fail2ban puisse notifier), un serveur SMTP est nécessaire. L'installation principale inclut **Postfix** :

- **Sans configuration supplémentaire** : Postfix envoie directement (mode « Internet Site »). Les mails peuvent être refusés par certains fournisseurs (SPF, réputation).
- **Avec relais** : pour une meilleure délivrabilité, configurez un relais (OVH, Gmail, SendGrid, etc.) en créant `/root/Devops/.smtp_config` :

```bash
relay_host:smtp.votre-fournisseur.com
smtp_user:votre-email@domaine.com
smtp_pass:mot-de-passe-application
```

Exemple : `config/smtp_config.example`. Après création de `.smtp_config`, relancer Postfix : `systemctl restart postfix`.

### Ce que le script crée

- **Apache** : un vhost dans `/etc/apache2/sites-available/<vhost>.conf` (port 80 ; Let's Encrypt ajoute le 443 si `-l 1`)
- **PHP-FPM** : un pool dédié dans `/etc/php/<version>/fpm/pool.d/<vhost>.conf`
- **Utilisateur Linux** : compte dédié, répertoire web `/home/<user>/data/www`, logs Apache par instance dans `/home/<user>/logs/apache/` (chaque vhost a ses propres logs ; logrotate les fait tourner)
- **MariaDB** : utilisateur et base du même nom (mot de passe MariaDB root lu depuis `/root/Devops/.passwords`)

### Identifiants et sauvegardes

- Un fichier d’identifiants par vhost : `/root/Devops/sites/<vhost>.installed` (10 vhosts = 10 fichiers)
- Configs Apache et PHP-FPM sauvegardées dans `/root/Devops/configs/`
- Envoi d’un récapitulatif par email si la commande `mail` est configurée

### Exemples

```bash
# Vhost avec Let's Encrypt
./scripts/vhost_apache.sh -a "client@example.com" -n "www.example.com" -y "example.com" -p 8.1 -l 1

# Sans SSL (HTTP uniquement)
./scripts/vhost_apache.sh -a "client@example.com" -n "site.example.com" -p 8.2

# Avec IP spécifique
./scripts/vhost_apache.sh -a "client@example.com" -n "site.example.com" -p 8.1 -i "192.168.1.10"
```

## Services installés

### PHP-FPM
- Version : Dernière version disponible dans les dépôts
- Extensions installées : mysql, mongodb, curl, gd, mbstring, xml, zip, bcmath, json
- Socket : `/var/run/php/php[VERSION]-fpm.sock`

### MongoDB
- Version : 7.0
- Utilisateur admin créé : `admin`
- Authentification activée
- Service : `mongod`

### MariaDB
- Version : Dernière version stable
- Utilisateur root configuré avec mot de passe sécurisé
- Configuration sécurisée (suppression des utilisateurs anonymes, etc.)
- Service : `mariadb` ou `mysql`

### Apache
- Version : Dernière version disponible
- Modules activés : rewrite, ssl, headers, proxy, proxy_fcgi
- Configuration pour PHP-FPM
- Service : `apache2` (Debian/Ubuntu) ou `httpd` (CentOS/RHEL/Fedora)

### Fail2ban
- Protection SSH activée
- Protection Apache activée
- Temps de bannissement : 1 heure
- Nombre de tentatives : 5 (SSH : 3)

### Postfix (SMTP)
- MTA pour l'envoi d'emails (commande `mail`, cron, scripts)
- Utilisé par le script vhost (envoi des identifiants) et par fail2ban (alertes)
- Mode par défaut : envoi direct (« Internet Site »)
- Relais optionnel : créer `/root/Devops/.smtp_config` (voir `config/smtp_config.example`)
- Service : `postfix`

### iptables
- Règles de pare-feu configurées
- Ports ouverts : SSH (22), HTTP (80), HTTPS (443)
- Politique par défaut : DROP pour INPUT et FORWARD
- Règles sauvegardées dans `/root/Devops/.iptables.rules`
- Script de restauration disponible : `/root/Devops/.restore_iptables.sh`
- Persistance des règles au démarrage configurée

### Durcissement de la sécurité
- **SSH** : Connexion root autorisée avec mot de passe, limitation des tentatives (MaxAuthTries: 3), timeout de connexion
- **Mises à jour automatiques** : Configuration pour installer automatiquement les mises à jour de sécurité
- **Configuration système** : Protection contre IP spoofing, SYN flood, paquets martiens
- **Outils de sécurité** : AIDE (détection d'intrusion), rkhunter (détection rootkits)
- **Limites système** : Configuration des limites de ressources
- **Permissions** : Vérification et correction des permissions des fichiers sensibles
- **Apache** : Headers de sécurité, masquage des informations serveur
- **PHP** : Désactivation des fonctions dangereuses, masquage des informations PHP

## Scripts utilitaires

- **Vérification** : `./scripts/verify_services.sh` — état systemd et tests de connexion (HTTP, MongoDB, MariaDB, SSH). Exécuté automatiquement en fin d’installation.
- **Sauvegarde** : `./scripts/backup_devops.sh` — crée une archive datée dans `${DEVOPS_ROOT}/backups/` (passwords, configs, iptables, optionnellement dumps MongoDB et MariaDB).
- **Restauration de configs** : `./scripts/restore_configs.sh` — restaure un fichier `.backup` depuis `${DEVOPS_ROOT}/configs/` vers le chemin système (avec confirmation).
- **Rotation des logs** : `./scripts/install_logrotate.sh` — configure logrotate pour Apache, PHP-FPM, MongoDB, MariaDB, fail2ban et les logs d’installation. Exécuté en fin d’install.
- **SSL (Let's Encrypt)** : `./scripts/install_certbot.sh` — installe certbot pour Apache. Ensuite, `vhost_apache.sh -l 1` permet d’obtenir un certificat HTTPS pour un vhost.

## Dépannage

### Vérifier le statut des services

```bash
# PHP-FPM
systemctl status php*-fpm

# MongoDB
systemctl status mongod

# MariaDB
systemctl status mariadb

# Apache
systemctl status apache2  # ou httpd sur CentOS/RHEL

# Fail2ban
systemctl status fail2ban

# iptables
iptables -L -v -n
```

### Consulter les logs

```bash
# Logs Apache
tail -f /var/log/apache2/error.log  # ou /var/log/httpd/error_log

# Logs PHP-FPM
tail -f /var/log/php*-fpm.log

# Logs MongoDB
tail -f /var/log/mongodb/mongod.log

# Logs MariaDB
tail -f /var/log/mysql/error.log

# Logs Fail2ban
tail -f /var/log/fail2ban.log
```

### Réinstaller un service spécifique

Vous pouvez exécuter individuellement chaque script d'installation :

```bash
sudo ./scripts/install_php-fpm.sh
sudo ./scripts/install_mongodb.sh
sudo ./scripts/install_iptables.sh
# etc.
```

## Sécurité

### Mots de passe et configurations
- Tous les mots de passe sont générés de manière aléatoire (32 caractères par défaut)
- Le fichier de mots de passe est protégé (permissions 600)
- Le dossier Devops est protégé (permissions 700)
- **Tous les fichiers de configuration (.conf) sont sauvegardés** dans `/root/Devops/configs/`

### Pare-feu et protection
- Fail2ban est configuré pour protéger SSH et Apache
- iptables est configuré avec une politique restrictive (DROP par défaut)
- Les règles iptables sont sauvegardées et peuvent être restaurées

### SSH
- **Connexion root autorisée** avec authentification par mot de passe
- Limitation des tentatives de connexion (MaxAuthTries: 3)
- Timeout de connexion configuré (300 secondes)
- X11 forwarding désactivé
- Configuration sauvegardée dans `/root/Devops/configs/`

### Services
- Apache : Headers de sécurité, informations serveur masquées
- PHP : Fonctions dangereuses désactivées, informations PHP masquées
- MongoDB : Authentification activée
- MariaDB : Configuration sécurisée (utilisateurs anonymes supprimés)

### Système
- Mises à jour automatiques de sécurité configurées
- Protection contre IP spoofing et SYN flood
- Outils de détection d'intrusion (AIDE, rkhunter) installés
- Limites système configurées

## Notes importantes

- ⚠️ **Sauvegardez le fichier `/root/Devops/.passwords`** dans un endroit sûr après l'installation
- ⚠️ **Sauvegardez les fichiers `/root/Devops/.iptables.rules`** pour pouvoir restaurer les règles
- ⚠️ **Sauvegardez le dossier `/root/Devops/configs/`** qui contient toutes les configurations (.conf)
- ⚠️ Le mot de passe root du système est changé automatiquement
- ⚠️ **La connexion SSH root est autorisée** - assurez-vous d'utiliser un mot de passe fort
- ⚠️ Assurez-vous d'avoir un accès de secours au serveur avant d'exécuter le script
- ⚠️ Les règles iptables bloquent tout le trafic par défaut sauf SSH, HTTP et HTTPS

## Support

Pour toute question ou problème, vérifiez :
1. Les logs des services concernés
2. Le statut des services avec `systemctl status`
3. Les permissions du fichier de mots de passe
