# Pistes d'amélioration

Suggestions classées par priorité et thème pour faire évoluer la suite de scripts.

---

## Priorité haute (impact direct)

### 1. Fichier de configuration central
- **Idée** : Un fichier `config.env` ou `install.conf` à la racine pour :
  - Activer/désactiver des services (`INSTALL_MONGODB=yes`, `INSTALL_MARIADB=no`, etc.)
  - Choisir le mot de passe root (ou le laisser généré)
  - Optionnel : port SSH, email pour les alertes fail2ban, etc.
- **Intérêt** : Réutiliser les scripts sur plusieurs serveurs sans modifier le code.

### 2. Mode installation partielle / idempotence
- **Idée** : Pouvoir lancer `./install.sh --only apache php-fpm` ou `--skip mongodb`.
- **Idée** : Détecter si un service est déjà installé et proposer de le sauter ou de le reconfigurer.
- **Intérêt** : Mise à jour ciblée, rejeu du script sans tout réinstaller.

### 3. Logs d’installation
- **Idée** : Rediriger toute la sortie vers un fichier daté dans `/root/Devops/logs/` (ex. `install_20250125_143022.log`) tout en affichant à l’écran.
- **Intérêt** : Audit, dépannage et traçabilité des erreurs.

### 4. Vérifications post-installation
- **Idée** : Script `scripts/verify_services.sh` qui :
  - Vérifie que chaque service est actif (`systemctl is-active`)
  - Teste une connexion minimale (HTTP, MongoDB, MariaDB, SSH)
  - Affiche un résumé OK/KO.
- **Intérêt** : S’assurer que l’installation a bien tout mis en place.

### 5. SSL/TLS pour Apache (HTTPS)
- **Idée** : Option pour configurer un vhost HTTPS avec certificat (Let’s Encrypt / certbot) : script `install_ssl_apache.sh` ou étape conditionnelle dans l’install.
- **Intérêt** : Servir les sites en HTTPS sans configuration manuelle.

---

## Priorité moyenne (robustesse et opérations)

### 6. Gestion d’erreurs plus explicite
- **Idée** : `trap` pour afficher un message en cas d’échec et éventuellement restaurer une config (ex. SSH) si l’étape de hardening échoue.
- **Idée** : En cas d’échec d’un sous-script, afficher la commande et le code de sortie avant de quitter.

### 7. Script de sauvegarde ✅
- **Fait** : `scripts/backup_devops.sh` — archive dans `${DEVOPS_ROOT}/backups/` + optionnel dumps MongoDB/MariaDB.

### 8. Script de restauration ✅
- **Fait** : `scripts/restore_configs.sh` — restaure un .backup depuis configs/ (avec confirmation).

### 9. Rotation des logs ✅
- **Fait** : `scripts/install_logrotate.sh` — logrotate pour Apache, PHP-FPM, MongoDB, MariaDB, fail2ban. En fin d'install.

### 10. Option “dry-run” ou simulation
- **Idée** : `./install.sh --dry-run` qui affiche les étapes et les commandes sans les exécuter (ou exécute uniquement les parties sans effet de bord).
- **Intérêt** : Comprendre ce que fait le script avant de lancer une vraie install.

---

## Priorité basse (confort et évolutions)

### 11. Authentification SSH par clé
- **Idée** : Option pour déposer une clé SSH dans `~root/.ssh/authorized_keys` (depuis une URL ou un fichier local) et optionnellement désactiver l’auth par mot de passe pour SSH.
- **Intérêt** : Connexion root plus sécurisée et pratique.

### 12. Utilisateur non-root + sudo
- **Idée** : Option pour créer un utilisateur dédié (ex. `deploy`) avec sudo sans mot de passe pour des commandes définies, et documenter la connexion en root vs cet utilisateur.
- **Intérêt** : Réduire l’usage direct de root au quotidien.

### 13. Monitoring basique
- **Idée** : Script ou cron qui vérifie périodiquement les services et envoie un mail ou écrit dans un log en cas de panne.
- **Intérêt** : Détection rapide des problèmes.

### 14. Uninstall / désinstallation propre
- **Idée** : Script `uninstall.sh` ou `scripts/remove_services.sh` qui arrête et désinstalle les paquets (avec confirmation), sans toucher à `/root/Devops/` pour garder les mots de passe et configs.
- **Intérêt** : Repartir proprement sur un serveur de test.

### 15. Tests automatisés
- **Idée** : Lancer les scripts dans une VM (Vagrant, LXC, cloud) et vérifier que les services répondent (script shell ou playbook simple).
- **Intérêt** : Détecter les régressions après des changements.

### 16. Documentation des variables d’environnement
- **Idée** : Dans le README, lister les variables optionnelles (ex. `SKIP_ROOT_PASSWORD=1`, `INSTALL_LOG=/var/log/install.log`) si vous les ajoutez.
- **Intérêt** : Utilisation avancée sans lire tout le code.

---

## Résumé des actions rapides

| Action | Effort | Impact |
|--------|--------|--------|
| Fichier `config.env` + lecture dans `install.sh` | Faible | Élevé |
| Logs dans `/root/Devops/logs/` | Faible | Élevé |
| Script `verify_services.sh` | Faible | Élevé |
| Option `--only` / `--skip` dans `install.sh` | Moyen | Élevé |
| Script `backup_devops.sh` | Faible | Moyen |
| Certificat SSL (certbot) optionnel | Moyen | Élevé |
| Trap + messages d’erreur explicites | Faible | Moyen |
| Dry-run | Moyen | Moyen |

---

*Document généré pour le projet Scripts_serveur. À adapter selon vos priorités.*
