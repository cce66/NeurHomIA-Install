#!/bin/bash
# firstboot-config.sh – Configuration interactive au premier démarrage
# Version 2.1.0 — Toutes les fonctionnalités documentées

if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root." >&2
    exit 1
fi

# --- Début logging ---
LOG_FILE="/home/${USER}/firstboot.log" 
exec > >(tee -a "$LOG_FILE") 2>&1
echo "========================================="
echo "Début de firstboot.sh : $(date)"
echo "Exécuté par : $(whoami)"
echo "========================================="
# ---------------------

# ============================================
#   VARIABLES CENTRALISÉES
# ============================================

# Nom du projet (utilisé pour hostname, dossier, label)
PROJECT_NAME="NeurHomIA"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')

# Propriétaire du github
GITHUB_OWNER_NAME="cce66"

# URLs GitHub
GITHUB_REPO="${GITHUB_OWNER_NAME}/${PROJECT_NAME}"


SERVICE_NAME="${PROJECT_NAME_LOWER}-firstboot.service"
INSTALL_DIR="/opt/${PROJECT_NAME_LOWER}"

# Détection dynamique du premier utilisateur UID >= 1000
TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="${PROJECT_NAME_LOWER}"
fi
TARGET_HOME=$(eval echo "~${TARGET_USER}")

# Fonctions utilitaires
get_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n1
}

detect_interfaces() {
    ls /sys/class/net/ | grep -v lo
}

validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -r o1 o2 o3 o4 <<< "$ip"
        if ((o1 <= 255 && o2 <= 255 && o3 <= 255 && o4 <= 255)); then
            return 0
        fi
    fi
    return 1
}

# ============================================
#   1. BIENVENUE
# ============================================
echo "=== Étape 1. BIENVENUE"
whiptail --title "${PROJECT_NAME} - Configuration initiale" \
         --msgbox "Bienvenue dans l'assistant de configuration de votre serveur ${PROJECT_NAME}.\n\nNous allons configurer le réseau, la sécurité et les services essentiels." 12 60

# ============================================
#   2. CONFIGURATION RÉSEAU
# ============================================
echo "=== Étape 2. CONFIGURATION RÉSEAU"
INTERFACES=$(detect_interfaces)
if [ -z "$INTERFACES" ]; then
    whiptail --msgbox "Aucune interface réseau filaire détectée. Vérifiez votre matériel." 8 60
    exit 1
fi

interface_list=()
for iface in $INTERFACES; do
    interface_list+=("$iface" "")
done

SELECTED_IFACE=$(whiptail --menu "Choisissez l'interface à configurer :" 15 60 4 "${interface_list[@]}" 3>&1 1>&2 2>&3)
if [ -z "$SELECTED_IFACE" ]; then
    whiptail --msgbox "Aucune interface sélectionnée. Le script va continuer avec les paramètres par défaut (DHCP)." 8 60
else
    if (whiptail --yesno "Utiliser DHCP pour $SELECTED_IFACE ?" 8 50); then
        cat > /etc/netplan/99-${PROJECT_NAME_LOWER}.yaml <<EOF
network:
  version: 2
  ethernets:
    $SELECTED_IFACE:
      dhcp4: true
      optional: true
EOF
    else
        STATIC_IP=$(whiptail --inputbox "Entrez l'adresse IP avec CIDR (ex: 192.168.1.100/24)" 8 60 3>&1 1>&2 2>&3)
        GATEWAY=$(whiptail --inputbox "Entrez l'adresse de la passerelle par défaut" 8 60 3>&1 1>&2 2>&3)
        DNS=$(whiptail --inputbox "Entrez les serveurs DNS (séparés par des virgules)" 8 60 "8.8.8.8,1.1.1.1" 3>&1 1>&2 2>&3)

        if ! validate_ip "${STATIC_IP%%/*}"; then
            whiptail --msgbox "Adresse IP invalide. Abandon." 8 60
            exit 1
        fi

        cat > /etc/netplan/99-${PROJECT_NAME_LOWER}.yaml <<EOF
network:
  version: 2
  ethernets:
    $SELECTED_IFACE:
      addresses:
        - $STATIC_IP
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [$(echo "$DNS" | sed 's/,/, /g')]
EOF
    fi

    netplan apply
    sleep 3
    CURRENT_IP=$(get_ip)
    whiptail --msgbox "Configuration réseau appliquée. Adresse IP : $CURRENT_IP" 8 60
fi

# ============================================
#   3. FUSEAU HORAIRE
# ============================================
echo "=== Étape 3. FUSEAU HORAIRE"
CURRENT_TZ=$(timedatectl show --property=Timezone --value 2>/dev/null || echo "UTC")
TZ_CHOICE=$(whiptail --menu "Sélectionnez votre fuseau horaire (actuel : $CURRENT_TZ) :" 18 60 8 \
    "Europe/Paris"      "France métropolitaine" \
    "Europe/Brussels"   "Belgique" \
    "Europe/Zurich"     "Suisse" \
    "America/Montreal"  "Québec / Canada Est" \
    "America/New_York"  "USA Est" \
    "America/Chicago"   "USA Centre" \
    "America/Los_Angeles" "USA Ouest" \
    "Autre"             "Saisie libre" \
    3>&1 1>&2 2>&3)

if [ "$TZ_CHOICE" = "Autre" ]; then
    TZ_CHOICE=$(whiptail --inputbox "Entrez le fuseau horaire (ex: Asia/Tokyo) :" 8 60 "$CURRENT_TZ" 3>&1 1>&2 2>&3)
fi

if [ -n "$TZ_CHOICE" ] && [ "$TZ_CHOICE" != "Autre" ]; then
    timedatectl set-timezone "$TZ_CHOICE"
    whiptail --msgbox "Fuseau horaire configuré : $TZ_CHOICE" 8 60
    SELECTED_TZ="$TZ_CHOICE"
else
    SELECTED_TZ="$CURRENT_TZ"
fi

# ============================================
#   4. CHANGEMENT DU MOT DE PASSE PAR DÉFAUT
# ============================================
echo "=== Étape 4. CHANGEMENT DU MOT DE PASSE PAR DÉFAUT"
if (whiptail --yesno "Le mot de passe par défaut pour l'utilisateur '${TARGET_USER}' est '${PROJECT_NAME_LOWER}'.\n\nPour des raisons de sécurité, il est fortement recommandé de le changer.\n\nVoulez-vous le modifier maintenant ?" 12 60); then
    while true; do
        NEW_PASS=$(whiptail --passwordbox "Nouveau mot de passe :" 8 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            whiptail --msgbox "Changement de mot de passe annulé. Vous pourrez le faire plus tard avec la commande 'passwd'." 8 60
            break
        fi
        NEW_PASS2=$(whiptail --passwordbox "Confirmation :" 8 60 3>&1 1>&2 2>&3)
        if [ "$NEW_PASS" != "$NEW_PASS2" ]; then
            whiptail --msgbox "Les mots de passe ne correspondent pas. Veuillez réessayer." 8 60
        elif [ -z "$NEW_PASS" ]; then
            whiptail --msgbox "Le mot de passe ne peut pas être vide." 8 60
        else
            echo "${TARGET_USER}:${NEW_PASS}" | chpasswd
            if [ $? -eq 0 ]; then
                whiptail --msgbox "Mot de passe changé avec succès." 8 60
                break
            else
                whiptail --msgbox "Erreur lors du changement de mot de passe. Veuillez réessayer." 8 60
            fi
        fi
    done
else
    whiptail --msgbox "Attention : vous conservez le mot de passe par défaut. Pensez à le changer rapidement après la configuration." 8 60
fi

# ============================================
#   5. CONFIGURATION SSH
# ============================================
echo "=== Étape 5. CONFIGURATION SSH"
if (whiptail --yesno "Voulez-vous ajouter une clé publique SSH pour l'utilisateur ${TARGET_USER} ?" 8 60); then
    SSH_KEY=$(whiptail --inputbox "Collez votre clé publique (ssh-rsa AAAA...)" 10 60 3>&1 1>&2 2>&3)
    if [ -n "$SSH_KEY" ]; then
        mkdir -p "${TARGET_HOME}/.ssh"
        echo "$SSH_KEY" >> "${TARGET_HOME}/.ssh/authorized_keys"
        chown -R "${TARGET_USER}:${TARGET_USER}" "${TARGET_HOME}/.ssh"
        chmod 700 "${TARGET_HOME}/.ssh"
        chmod 600 "${TARGET_HOME}/.ssh/authorized_keys"
        sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config.d/99-${PROJECT_NAME_LOWER}.conf 2>/dev/null
        systemctl restart sshd
        whiptail --msgbox "Clé SSH ajoutée. L'authentification par mot de passe a été désactivée." 8 60
    fi
fi

# ============================================
#   6. PARE-FEU UFW
# ============================================
echo "=== Étape 6. PARE-FEU UFW"
whiptail --infobox "Configuration du pare-feu UFW..." 8 40
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow 22/tcp comment 'SSH'
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 1883/tcp comment 'MQTT'
ufw allow 8080/tcp comment "${PROJECT_NAME}"
ufw allow 9001/tcp comment 'MQTT WebSocket'
whiptail --msgbox "Pare-feu UFW activé. Règles par défaut appliquées." 8 60

# ============================================
#   7. FAIL2BAN
# ============================================
echo "=== Étape 7. FAIL2BAN"
whiptail --infobox "Configuration de fail2ban..." 8 40
cat > /etc/fail2ban/jail.local <<EOF
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
filter   = sshd
logpath  = /var/log/auth.log
maxretry = 5
EOF

systemctl enable --now fail2ban
whiptail --msgbox "fail2ban activé. Les tentatives SSH abusives seront bloquées (5 essais max, ban 1h)." 8 60

# ============================================
#   8. MISES À JOUR AUTOMATIQUES
# ============================================
echo "=== Étape 8. MISES À JOUR AUTOMATIQUES"
if (whiptail --yesno "Activer les mises à jour de sécurité automatiques (unattended-upgrades) ?" 8 60); then
    dpkg-reconfigure -f noninteractive unattended-upgrades
    whiptail --msgbox "Mises à jour automatiques de sécurité activées." 8 60
fi

# ============================================
#   9. MOT DE PASSE MQTT
# ============================================
echo "=== Étape 9. MOT DE PASSE MQTT"
MQTT_PASSWORD=""
if (whiptail --yesno "Voulez-vous définir un mot de passe pour le broker MQTT ?\n\n(Recommandé pour sécuriser les communications domotiques)" 10 60); then
    while true; do
        MQTT_PASS=$(whiptail --passwordbox "Mot de passe MQTT :" 8 60 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            whiptail --msgbox "Configuration MQTT annulée. Le broker utilisera la configuration par défaut." 8 60
            break
        fi
        MQTT_PASS2=$(whiptail --passwordbox "Confirmation du mot de passe MQTT :" 8 60 3>&1 1>&2 2>&3)
        if [ "$MQTT_PASS" != "$MQTT_PASS2" ]; then
            whiptail --msgbox "Les mots de passe ne correspondent pas." 8 60
        elif [ -z "$MQTT_PASS" ]; then
            whiptail --msgbox "Le mot de passe ne peut pas être vide." 8 60
        else
            MQTT_PASSWORD="$MQTT_PASS"
            whiptail --msgbox "Mot de passe MQTT configuré." 8 60
            break
        fi
    done
fi

# ============================================
#   10. INSTALLATION (DOCKER COMPOSE)
# ============================================
echo "=== Étape 10. INSTALLATION (DOCKER COMPOSE)"
whiptail --infobox "Clonage du dépôt ${PROJECT_NAME} et démarrage des conteneurs..." 8 60
cd /opt
if [ -d "${PROJECT_NAME_LOWER}" ]; then
    rm -rf "${PROJECT_NAME_LOWER}"
fi
git clone "https://github.com/${GITHUB_REPO}.git" "${PROJECT_NAME_LOWER}"
cd "${PROJECT_NAME_LOWER}"

# Génération du fichier .env
cat > .env <<EOF
# ${PROJECT_NAME} — Configuration générée par firstboot
TZ=${SELECTED_TZ}
MQTT_PASSWORD=${MQTT_PASSWORD}
EOF

chown "${TARGET_USER}:${TARGET_USER}" .env
chmod 600 .env

# Sélection des profils Docker
PROFILES=$(whiptail --checklist "Sélectionnez les profils à activer (ESPACE pour sélectionner) :" 15 50 4 \
    "zigbee2mqtt" "Pont Zigbee" OFF \
    "meteo" "Station météo" OFF \
    "backup" "Sauvegardes" OFF \
    3>&1 1>&2 2>&3)

PROFILES_CLEAN=$(echo "$PROFILES" | sed 's/"//g')

# Persistance des profils sélectionnés
echo "$PROFILES_CLEAN" > "${INSTALL_DIR}/.profiles"
chown "${TARGET_USER}:${TARGET_USER}" "${INSTALL_DIR}/.profiles"

if [ -n "$PROFILES_CLEAN" ]; then
    PROFILES_ARGS="--profile $(echo "$PROFILES_CLEAN" | sed 's/ / --profile /g')"
else
    PROFILES_ARGS=""
fi

# Lancement Docker via l'utilisateur cible
su - "${TARGET_USER}" -c "cd ${INSTALL_DIR} && docker compose ${PROFILES_ARGS} up -d"

# ============================================
#   11. UTILITAIRES CLI
# ============================================
echo "=== Étape 11. UTILITAIRES CLI"
whiptail --infobox "Installation des utilitaires CLI..." 8 40

# neurhomia-status
cat > /usr/local/bin/${PROJECT_NAME_LOWER}-status <<EOF
#!/bin/bash
echo "=== ${PROJECT_NAME} — État du système ==="
echo ""
echo "--- Conteneurs Docker ---"
cd ${INSTALL_DIR} && docker compose ps
echo ""
echo "--- Espace disque ---"
df -h /
echo ""
echo "--- Mémoire ---"
free -h
echo ""
echo "--- Uptime ---"
uptime
EOF

# neurhomia-logs
cat > /usr/local/bin/${PROJECT_NAME_LOWER}-logs <<EOF
#!/bin/bash
SERVICE=\${1:-""}
cd ${INSTALL_DIR}
if [ -n "\$SERVICE" ]; then
    docker compose logs -f "\$SERVICE"
else
    docker compose logs -f
fi
EOF

# neurhomia-restart
cat > /usr/local/bin/${PROJECT_NAME_LOWER}-restart <<EOF
#!/bin/bash
echo "Redémarrage des services ${PROJECT_NAME}..."
cd ${INSTALL_DIR}
PROFILES_FILE="${INSTALL_DIR}/.profiles"
PROFILES_ARGS=""
if [ -f "\$PROFILES_FILE" ] && [ -s "\$PROFILES_FILE" ]; then
    for p in \$(cat "\$PROFILES_FILE"); do
        PROFILES_ARGS="\$PROFILES_ARGS --profile \$p"
    done
fi
docker compose \$PROFILES_ARGS restart
echo "Redémarrage terminé."
EOF

# neurhomia-update
cat > /usr/local/bin/${PROJECT_NAME_LOWER}-update <<EOF
#!/bin/bash
echo "Mise à jour de ${PROJECT_NAME}..."
cd ${INSTALL_DIR}
git pull
docker compose pull
PROFILES_FILE="${INSTALL_DIR}/.profiles"
PROFILES_ARGS=""
if [ -f "\$PROFILES_FILE" ] && [ -s "\$PROFILES_FILE" ]; then
    for p in \$(cat "\$PROFILES_FILE"); do
        PROFILES_ARGS="\$PROFILES_ARGS --profile \$p"
    done
fi
docker compose \$PROFILES_ARGS up -d
echo "Mise à jour terminée."
EOF

chmod +x /usr/local/bin/${PROJECT_NAME_LOWER}-{status,logs,restart,update}

whiptail --msgbox "Utilitaires CLI installés :\n\n• ${PROJECT_NAME_LOWER}-status  — État du système\n• ${PROJECT_NAME_LOWER}-logs    — Journaux des services\n• ${PROJECT_NAME_LOWER}-restart — Redémarrer les services\n• ${PROJECT_NAME_LOWER}-update  — Mettre à jour ${PROJECT_NAME}" 14 60

# ============================================
#   12. FINALISATION
# ============================================
echo "=== Étape 12. FINALISATION"

CURRENT_IP=$(get_ip)
whiptail --title "Terminé" \
         --msgbox "Configuration terminée !\n\nAdresse IP : $CURRENT_IP\nFuseau horaire : $SELECTED_TZ\n\nAccédez au dashboard : http://$CURRENT_IP:8080\n\nLe service de premier démarrage va maintenant se désactiver." 14 60

systemctl disable "${SERVICE_NAME}"
rm -f "/etc/systemd/system/${SERVICE_NAME}"
systemctl daemon-reload

exit 0
