#!/bin/bash
# neurhomia-ins.sh — Installation autonome de NeurHomIA depuis GitHub
# Peut être appelé par firstboot.sh ou exécuté indépendamment
# Version 1.0.0

set -euo pipefail

# ============================================
#   VARIABLES CENTRALISÉES
# ============================================
PROJECT_NAME="NeurHomIA"
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
GITHUB_OWNER_NAME="cce66"
GITHUB_REPO="${GITHUB_OWNER_NAME}/${PROJECT_NAME}"
INSTALL_DIR="/opt/${PROJECT_NAME_LOWER}"

# Détection dynamique du premier utilisateur UID >= 1000
TARGET_USER=$(awk -F: '$3 >= 1000 && $3 < 65534 { print $1; exit }' /etc/passwd)
if [ -z "$TARGET_USER" ]; then
    TARGET_USER="${PROJECT_NAME_LOWER}"
fi
TARGET_HOME=$(eval echo "~${TARGET_USER}")

# Paramètres passés par firstboot.sh (optionnels)
SELECTED_TZ="${NEURHOMIA_TZ:-$(timedatectl show --property=Timezone --value 2>/dev/null || echo 'UTC')}"
MQTT_PASSWORD="${NEURHOMIA_MQTT_PASSWORD:-}"

# Fonction utilitaire
get_ip() {
    ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -n1
}

# Vérification root
if [ "$EUID" -ne 0 ]; then
    echo "Ce script doit être exécuté en tant que root." >&2
    exit 1
fi

# ============================================
#   MODE INTERACTIF (si pas appelé par firstboot)
# ============================================
INTERACTIVE=true
if [ "${NEURHOMIA_FIRSTBOOT:-}" = "1" ]; then
    INTERACTIVE=false
fi

# ============================================
#   1. VÉRIFICATION DOCKER
# ============================================
if ! command -v docker &>/dev/null; then
    if $INTERACTIVE && command -v whiptail &>/dev/null; then
        whiptail --msgbox "Docker n'est pas installé.\n\nInstallation automatique via get.docker.com..." 10 60
    fi
    echo "[INFO] Installation de Docker Engine..."
    curl -fsSL https://get.docker.com | sh
    usermod -aG docker "${TARGET_USER}"
    systemctl enable --now docker
    echo "[OK] Docker installé avec succès."
fi

# ============================================
#   2. MOT DE PASSE MQTT (si mode interactif)
# ============================================
if $INTERACTIVE && [ -z "$MQTT_PASSWORD" ] && command -v whiptail &>/dev/null; then
    if (whiptail --yesno "Voulez-vous définir un mot de passe pour le broker MQTT ?\n\n(Recommandé pour sécuriser les communications domotiques)" 10 60); then
        while true; do
            MQTT_PASS=$(whiptail --passwordbox "Mot de passe MQTT :" 8 60 3>&1 1>&2 2>&3)
            if [ $? -ne 0 ]; then
                whiptail --msgbox "Configuration MQTT annulée." 8 60
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
fi

# ============================================
#   3. CLONAGE DU DÉPÔT
# ============================================
if $INTERACTIVE && command -v whiptail &>/dev/null; then
    whiptail --infobox "Clonage du dépôt ${PROJECT_NAME} depuis GitHub..." 8 60
fi
echo "[INFO] Clonage de https://github.com/${GITHUB_REPO}.git..."

if [ -d "${INSTALL_DIR}" ]; then
    if $INTERACTIVE && command -v whiptail &>/dev/null; then
        if (whiptail --yesno "Le répertoire ${INSTALL_DIR} existe déjà.\n\nVoulez-vous le supprimer et réinstaller ?" 10 60); then
            rm -rf "${INSTALL_DIR}"
        else
            whiptail --msgbox "Installation annulée." 8 60
            exit 0
        fi
    else
        echo "[WARN] ${INSTALL_DIR} existe déjà. Suppression..."
        rm -rf "${INSTALL_DIR}"
    fi
fi

cd /opt
git clone "https://github.com/${GITHUB_REPO}.git" "${PROJECT_NAME_LOWER}"
cd "${INSTALL_DIR}"
echo "[OK] Dépôt cloné dans ${INSTALL_DIR}."

# ============================================
#   4. GÉNÉRATION DU FICHIER .env
# ============================================
echo "[INFO] Génération du fichier .env..."
cat > .env <<EOF
# ${PROJECT_NAME} — Configuration générée par neurhomia-ins.sh
TZ=${SELECTED_TZ}
MQTT_PASSWORD=${MQTT_PASSWORD}
EOF

chown "${TARGET_USER}:${TARGET_USER}" .env
chmod 600 .env
echo "[OK] Fichier .env créé."

# ============================================
#   5. SÉLECTION DES PROFILS DOCKER
# ============================================
PROFILES_CLEAN=""
if $INTERACTIVE && command -v whiptail &>/dev/null; then
    PROFILES=$(whiptail --checklist "Sélectionnez les profils à activer (ESPACE pour sélectionner) :" 15 50 4 \
        "zigbee2mqtt" "Pont Zigbee" OFF \
        "meteo" "Station météo" OFF \
        "backup" "Sauvegardes" OFF \
        3>&1 1>&2 2>&3) || true
    PROFILES_CLEAN=$(echo "$PROFILES" | sed 's/"//g')
fi

# Persistance des profils sélectionnés
echo "$PROFILES_CLEAN" > "${INSTALL_DIR}/.profiles"
chown "${TARGET_USER}:${TARGET_USER}" "${INSTALL_DIR}/.profiles"

PROFILES_ARGS=""
if [ -n "$PROFILES_CLEAN" ]; then
    PROFILES_ARGS="--profile $(echo "$PROFILES_CLEAN" | sed 's/ / --profile /g')"
fi

# ============================================
#   6. DÉMARRAGE DES CONTENEURS
# ============================================
echo "[INFO] Démarrage des conteneurs Docker..."
su - "${TARGET_USER}" -c "cd ${INSTALL_DIR} && docker compose ${PROFILES_ARGS} up -d"
echo "[OK] Conteneurs démarrés."

# ============================================
#   7. RÉSULTAT
# ============================================
CURRENT_IP=$(get_ip)

if $INTERACTIVE && command -v whiptail &>/dev/null; then
    whiptail --title "${PROJECT_NAME} — Installation terminée" \
             --msgbox "Installation réussie !\n\nAdresse IP : ${CURRENT_IP}\nRépertoire : ${INSTALL_DIR}\n\nAccédez au dashboard :\nhttp://${CURRENT_IP}:8080\n\nCommandes disponibles :\n• ${PROJECT_NAME_LOWER}-status\n• ${PROJECT_NAME_LOWER}-logs\n• ${PROJECT_NAME_LOWER}-restart\n• ${PROJECT_NAME_LOWER}-update\n• ${PROJECT_NAME_LOWER}-install (réinstallation)" 18 60
else
    echo ""
    echo "=== ${PROJECT_NAME} — Installation terminée ==="
    echo "  IP        : ${CURRENT_IP}"
    echo "  Dashboard : http://${CURRENT_IP}:8080"
    echo "  Dossier   : ${INSTALL_DIR}"
    echo ""
fi

exit 0
