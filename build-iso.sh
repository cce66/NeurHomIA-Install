#!/bin/bash
# build-iso.sh – Construction de l'ISO d'installation automatique d'Ubuntu Server et NeurHomIA
# Utilisation : ./build-iso.sh [--noforce]
#  
# - build-iso2sub
#   - autoinstall
#     - meta-data
#     - user-data
#     - user-data.template
#   - boot
#     - grub
#       - grub.cfg
#       - grub.cfg.template
#       - splash.png
#   - scripts
#     - firstboot.sh
#

set -e
clear

# ------------------------------
# Couleurs pour l'affichage
# ------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ------------------------------
# Messages echo
# ------------------------------
info()    { printf "${BLUE}  →${NC} %s\n" "$*"; }
success() { printf "${GREEN}  ✓${NC} %s\n" "$*"; }
warn()    { printf "${YELLOW}  !${NC} %s\n" "$*"; }
error()   { printf "${RED}  ✗${NC} %s\n" "$*" >&2; exit 1; }

# ------------------------------
# Paramètres personnalisables du Projet
# ------------------------------
# Nom du projet (utilisé pour hostname, dossier, label)
PROJECT_NAME="NeurHomIA"
# Propriétaire du github
GITHUB_OWNER_NAME="cce66"
# Version par défaut d'Ubuntu Server
DEFAULT_UBUNTU_VERSION="24.04.4"

# ------------------------------
# Autres Paramètres personnalisables
# ------------------------------
# Mise en forme des variables
PROJECT_NAME_LOWER=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]')
PROJECT_NAME_UPPER=$(echo "$PROJECT_NAME" | tr '[:lower:]' '[:upper:]')
# Nom de l'utilisateur système
USERNAME="${PROJECT_NAME_LOWER}"
# Mot de passe par défaut (sera hashé)
DEFAULT_PASSWORD="${PROJECT_NAME_LOWER}"

# URLs GitHub
GITHUB_URL="https://raw.githubusercontent.com/${GITHUB_OWNER_NAME}/${PROJECT_NAME}-ISO2USB/main/build-iso2usb"
# URL du script firstboot.sh
FIRSTBOOT_SCRIPT_URL="${GITHUB_URL}/scripts/firstboot.sh"
# URL du dossier autoinstall (contenant user-data.template et meta-data)
GITHUB_AUTOINSTALL_URL="${GITHUB_URL}/autoinstall"
# URL du template grub.cfg
GRUB_CFG_TEMPLATE_URL="${GITHUB_URL}/boot/grub/grub.cfg.template"

# ------------------------------
# Variables globales
# ------------------------------
FORCE_BUILD=true
SUDO_PASSWORD=""
WORK_DIR=""
ISO_VERSION=""
ISO_FILENAME=""
ISO_URL=""
EXTRACT_DIR=""
AUTOINSTALL_DIR=""
AUTOINSTALL_TEMPLATE_DIR=""
OUTPUT_ISO=""
LABEL=""
PASSWORD_HASH=""

# ------------------------------
# Fonctions
# ------------------------------

# Demande le mot de passe sudo au cas où le script n'a pas été lancé avec sudo
000_ask_sudo_password() {
    echo -e "${YELLOW}Entrez le mot de passe pour la commande sudo :${NC}"
	read -sp "=>" SUDO_PASSWORD
    echo >&2
}

# Traitement de l'option --noforce
001_parse_arguments() {
    if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        echo "Usage: $0 [--noforce] [--help]"
        echo "  --noforce  Arrêter si la validation échoue"
        echo "  --help     Afficher cette aide"
        exit 0
    fi
    if [[ "${1:-}" == "--noforce" ]]; then
        FORCE_BUILD=false
    fi
}

# Déterminer le répertoire de travail (même avec sudo)
002_setup_work_dir() {
    if [ -n "$SUDO_USER" ]; then
        REAL_USER="$SUDO_USER"
        REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
        WORK_DIR="$REAL_HOME/${PROJECT_NAME_LOWER}-key"
    else
        000_ask_sudo_password
        WORK_DIR="$HOME/${PROJECT_NAME_LOWER}-key"
    fi
    mkdir -p "$WORK_DIR"
    # Définir le dossier temporaire pour les templates autoinstall
    AUTOINSTALL_TEMPLATE_DIR="$WORK_DIR/autoinstall_template"
}

# 1) Demande interactive de la version d'Ubuntu Server à installer
01_ask_ubuntu_version() {
    echo -e "${YELLOW}1) Quelle version d'Ubuntu Server souhaitez-vous installer ? (défaut : $DEFAULT_UBUNTU_VERSION)${NC}"
    read -p "   Version : " USER_VERSION

    if [ -z "$USER_VERSION" ]; then
        ISO_VERSION="$DEFAULT_UBUNTU_VERSION"
        echo -e "${GREEN}   Version par défaut sélectionnée : $ISO_VERSION${NC}"
    else
        if [[ "$USER_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            ISO_VERSION="$USER_VERSION"
            echo -e "${GREEN}   Version sélectionnée : $ISO_VERSION${NC}"
        else
            echo -e "${RED}   Format de version invalide. Utilisation de la version par défaut $DEFAULT_UBUNTU_VERSION.${NC}"
            ISO_VERSION="$DEFAULT_UBUNTU_VERSION"
        fi
    fi

    # Configuration basée sur la version
    ISO_FILENAME="ubuntu-${ISO_VERSION}-live-server-amd64.iso"
    ISO_URL="https://releases.ubuntu.com/${ISO_VERSION%.*}/ubuntu-${ISO_VERSION}-live-server-amd64.iso"
    EXTRACT_DIR="$WORK_DIR/extracted"
    AUTOINSTALL_DIR="$WORK_DIR/autoinstall"
    OUTPUT_ISO="$WORK_DIR/${PROJECT_NAME_LOWER}-server-${ISO_VERSION}-auto.iso"
    LABEL="${PROJECT_NAME_UPPER}_SRV"
    # Troncature si le label dépasse 32 caractères (norme ISO)
    if [ ${#LABEL} -gt 32 ]; then
        LABEL="${LABEL:0:32}"
    fi
	echo ""
	echo -e "${GREEN}   Variables du script: "
	echo -e "   FORCE_BUILD: ${FORCE_BUILD}"
	echo -e "   SUDO_PASSWORD: ********"
	echo -e "   WORK_DIR: ${WORK_DIR}"
	echo -e "   ISO_VERSION: ${ISO_VERSION}"
	echo -e "   ISO_FILENAME: ${ISO_FILENAME}"
	echo -e "   ISO_URL: ${ISO_URL}"
	echo -e "   EXTRACT_DIR: ${EXTRACT_DIR}"
	echo -e "   AUTOINSTALL_DIR: ${AUTOINSTALL_DIR}"
	echo -e "   AUTOINSTALL_TEMPLATE_DIR: ${AUTOINSTALL_TEMPLATE_DIR}"
	echo -e "   OUTPUT_ISO: ${OUTPUT_ISO}"
	echo -e "   LABEL: ${LABEL}${NC}"
}

# 2) Validation de firstboot.sh (sections requises)
02_validate_firstboot_script() {
    echo ""
    echo -e "${YELLOW}2) Validation de firstboot.sh...${NC}"

    local FIRSTBOOT_TMP=$(mktemp /tmp/firstboot-check.XXXXXX)
    if wget -q -O "$FIRSTBOOT_TMP" "$FIRSTBOOT_SCRIPT_URL" 2>/dev/null; then
        declare -A SECTIONS=(
            ["01-Bienvenue"]="BIENVENUE"
            ["02-Configuration réseau"]="CONFIGURATION RÉSEAU"
            ["03-Fuseau horaire"]="FUSEAU HORAIRE"
            ["04-Mot de passe"]="MOT DE PASSE"
            ["05-Configuration SSH"]="CONFIGURATION SSH"
            ["06-Pare-feu UFW"]="PARE-FEU UFW"
            ["07-Fail2ban"]="FAIL2BAN"
            ["08-Mises à jour automatiques"]="MISES À JOUR AUTOMATIQUES"
            ["09-Mot de passe MQTT"]="MOT DE PASSE MQTT"
            ["10-Installation Docker"]="INSTALLATION"
            ["11-Utilitaires CLI"]="UTILITAIRES CLI"
            ["12-Finalisation"]="FINALISATION"
        )

        local MISSING=0
        for key in $(echo "${!SECTIONS[@]}" | tr ' ' '\n' | sort); do
            section="${key#*-}"
            marker="${SECTIONS[$key]}"
            if grep -qi "$marker" "$FIRSTBOOT_TMP" 2>/dev/null; then
			    printf "   ${GREEN}✔ $section${NC}"
                # echo -e "   ${GREEN}✔ $section${NC}"
            else
                printf "   ${RED}✘ $section${NC}"
                # echo -e "   ${RED}✘ $section (marqueur '$marker' absent)${NC}"
                MISSING=$((MISSING + 1))
            fi
        done
        printf "\n"
        if [ "$MISSING" -gt 0 ]; then
            echo ""
            echo -e "   ${RED}⚠ $MISSING section(s) manquante(s) dans firstboot.sh${NC}"
            if [ "$FORCE_BUILD" = true ]; then
                echo -e "   ${YELLOW}--force activé : construction forcée malgré les sections manquantes.${NC}"
            else
                echo -e "   ${RED}Build annulé. Utilisez --force pour passer outre.${NC}"
                rm -f "$FIRSTBOOT_TMP"
                exit 1
            fi
        else
            echo -e "   ${GREEN}✅ Toutes les sections requises sont présentes (12/12)${NC}"
        fi
    else
        echo -e "${RED}   Impossible de télécharger firstboot.sh pour validation. URL : $FIRSTBOOT_SCRIPT_URL${NC}"
        rm -f "$FIRSTBOOT_TMP"
        exit 1
    fi
    rm -f "$FIRSTBOOT_TMP"
}

# 3) Vérification des dépendances
03_check_dependencies() {
    echo ""
    echo -e "${YELLOW}3) Vérification des dépendances...${NC}"
    
    local deps=(
        wget
        p7zip-full
        openssl
        xorriso
        squashfs-tools
        schroot
        rsync
        syslinux-utils
        isolinux
        genisoimage
    )
    
    local missing=()
    for dep in "${deps[@]}"; do
        if ! dpkg -s "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}   Toutes les dépendances sont installées.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}   Dépendances manquantes : ${missing[*]}${NC}"
    
    # Mode non interactif (CI / SaaS)
    if [ "${AUTO_INSTALL_DEPS:-true}" = true ]; then
        echo -e "${CYAN}   Installation automatique en cours...${NC}"
    
        export DEBIAN_FRONTEND=noninteractive
    
        apt-get update -y
        apt-get install -y "${missing[@]}"
    
        # Vérification finale
        for dep in "${missing[@]}"; do
            if ! dpkg -s "$dep" >/dev/null 2>&1; then
                echo -e "${RED}   Échec installation : $dep${NC}"
                exit 1
            fi
        done
    
        echo -e "${GREEN}   Dépendances installées avec succès.${NC}"
    
    else
        echo -e "${RED}   Installation automatique désactivée.${NC}"
        echo -e "${YELLOW}   Lancez : sudo apt install ${missing[*]}${NC}"
        exit 1
    fi
}

# 4) Préparation des dossiers avec sauvegarde de l'ancien autoinstall
04_prepare_directories() {
    echo ""
    echo -e "${YELLOW}4) Préparation de l'espace de travail...${NC}"

    # Sauvegarde de l'ancien dossier autoinstall s'il existe
    if [ -d "$AUTOINSTALL_DIR" ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_AUTOINSTALL="${AUTOINSTALL_DIR}_${TIMESTAMP}"
        mv "$AUTOINSTALL_DIR" "$BACKUP_AUTOINSTALL"
        echo -e "${GREEN}   Ancien dossier autoinstall sauvegardé sous : $BACKUP_AUTOINSTALL${NC}"
    fi

    # Suppression de l'ancien répertoire d'extraction s'il existe
    if [ -d "$EXTRACT_DIR" ]; then
      rm -rf "$EXTRACT_DIR"
    fi

    # Création du répertoire pour l'extraction et du répertoire pour les fichiers d'autoinstall
    mkdir -p "$EXTRACT_DIR" "$AUTOINSTALL_DIR"
}

# 5) Téléchargement de l'ISO (si non existante)
05_download_iso() {
    echo ""
    echo -e "${YELLOW}5) Téléchargement de l'ISO Ubuntu Server ${ISO_VERSION}...${NC}"
    if [ ! -f "$WORK_DIR/$ISO_FILENAME" ]; then
        echo -e "${CYAN}   Début du téléchargement...${NC}"
        wget -O "$WORK_DIR/$ISO_FILENAME" "$ISO_URL"
        echo -e "${GREEN}   Téléchargement terminé."
    else
        echo -e "${GREEN}   L'ISO $ISO_FILENAME existe déjà dans $WORK_DIR. Utilisation de la copie locale.${NC}"
    fi
}

# 6) Extraction de l'ISO
06_extract_iso() {
    echo ""
    echo -e "${YELLOW}6) Extraction de l'ISO Ubuntu Server ${ISO_VERSION}...${CYAN}"
    echo -e "${CYAN}   Début de l'extraction...${NC}"
    7z x "$WORK_DIR/$ISO_FILENAME" -o"$EXTRACT_DIR"
    echo -e "${GREEN}   Extraction terminée.${NC}"
}

# 7) Génération du hash du mot de passe
07_generate_password_hash() {
    echo ""
    echo -e "${YELLOW}7) Génération du hash du mot de passe par défaut...${NC}"
    PASSWORD_HASH=$(openssl passwd -6 "$DEFAULT_PASSWORD")
    echo -e "${GREEN}   Hash généré.${NC}"
}

# 8) Création des fichiers d'autoinstall (téléchargement depuis GitHub)
08_create_autoinstall_files() {
    echo ""
    echo -e "${YELLOW}8) Création des fichiers d'autoinstall...${NC}"

    # Nettoyage du dossier temporaire
    rm -rf "$AUTOINSTALL_TEMPLATE_DIR"

	# Création du dossier temporaire pour les templates
    mkdir -p "$AUTOINSTALL_TEMPLATE_DIR"
    if [ ! -d "$AUTOINSTALL_TEMPLATE_DIR" ]; then
        echo -e "${RED}   Erreur : impossible de créer $AUTOINSTALL_TEMPLATE_DIR${NC}"
        exit 1
    fi

    # Téléchargement des fichiers depuis GitHub
    echo -e "${CYAN}   Téléchargement des templates depuis GitHub...${NC}"
    wget -O "$AUTOINSTALL_TEMPLATE_DIR/user-data.template" "${GITHUB_AUTOINSTALL_URL}/user-data.template"
    wget -O "$AUTOINSTALL_TEMPLATE_DIR/meta-data" "${GITHUB_AUTOINSTALL_URL}/meta-data"

    if [ ! -f "$AUTOINSTALL_TEMPLATE_DIR/user-data.template" ] || [ ! -f "$AUTOINSTALL_TEMPLATE_DIR/meta-data" ]; then
        echo -e "${RED}   Erreur : téléchargement des templates autoinstall échoué.${NC}"
        exit 1
    fi

    echo -e "${GREEN}   Templates téléchargés avec succès. Personnalisation en cours...${NC}"
    
    # Personnalisation avec sed (remplacement des placeholders)
    sed -e "s|__HOSTNAME__|${PROJECT_NAME_LOWER}-box|g" \
        -e "s|__USERNAME__|${USERNAME}|g" \
        -e "s|__PASSWORD_HASH__|${PASSWORD_HASH}|g" \
        -e "s|__PROJECT_LOWER__|${PROJECT_NAME_LOWER}|g" \
        -e "s|__PROJECT_NAME__|${PROJECT_NAME}|g" \
        -e "s|__FIRSTBOOT_URL__|${FIRSTBOOT_SCRIPT_URL}|g" \
        "$AUTOINSTALL_TEMPLATE_DIR/user-data.template" > "$AUTOINSTALL_DIR/user-data"

    cp "$AUTOINSTALL_TEMPLATE_DIR/meta-data" "$AUTOINSTALL_DIR/"

    if [ ! -f "$AUTOINSTALL_DIR/user-data" ] || [ ! -f "$AUTOINSTALL_DIR/meta-data" ]; then
        echo -e "${RED}   Erreur : échec de la copie des fichiers personnalisés.${NC}"
        exit 1
    fi
    echo -e "${GREEN}   Fichiers d'autoinstall personnalisés et prêts.${NC}"

}

# 8.5) Validation du fichier user-data (YAML)
08_validate_yaml() {
    echo ""
    echo -e "${YELLOW}8.5) Validation de la syntaxe YAML du fichier user-data...${NC}"
    
    local user_data_file="$AUTOINSTALL_DIR/user-data"
    
    if [ ! -f "$user_data_file" ]; then
        echo -e "${RED}   Fichier user-data introuvable !${NC}"
        exit 1
    fi
    
    # Utiliser python3 avec PyYAML si disponible, sinon utiliser yamllint
    if command -v yamllint &>/dev/null; then
        echo -e "${CYAN}   Validation avec yamllint...${NC}"
        if yamllint -d "{extends: relaxed, rules: {line-length: disable, indentation: {spaces: 2}}}" "$user_data_file"; then
            echo -e "${GREEN}   ✅ Syntaxe YAML valide (yamllint)${NC}"
            return 0
        else
            echo -e "${RED}   ❌ Erreur YAML détectée par yamllint${NC}"
            exit 1
        fi
    fi
    
    # Fallback : Python + PyYAML
    if ! command -v python3 &>/dev/null; then
        echo -e "${RED}   Python3 non installé. Impossible de valider.${NC}"
        exit 1
    fi
    
    if ! python3 -c "import yaml" 2>/dev/null; then
        echo -e "${CYAN}   Installation de python3-yaml...${NC}"
        apt-get update -qq && apt-get install -y python3-yaml 2>/dev/null
        if ! python3 -c "import yaml" 2>/dev/null; then
            echo -e "${RED}   Impossible d'installer python3-yaml. Validation ignorée.${NC}"
            return 0
        fi
    fi
    
    echo -e "${CYAN}   Validation avec Python/yaml...${NC}"
    
    local tmp_script=$(mktemp /tmp/validate-yaml.XXXXXX.py)
    
    cat > "$tmp_script" <<'PYEOF'
import yaml
import sys
import re

filepath = sys.argv[1]

with open(filepath, 'r', encoding='utf-8') as f:
    content = f.read()

# Nettoyer les éventuels placeholders restants (pour la validation uniquement)
content = re.sub(r'\$\{?[A-Z_][A-Z0-9_]*\}?', 'testvalue', content)
content = re.sub(r'__[A-Z_]+__', 'testvalue', content)

try:
    data = yaml.safe_load(content)
    if data is None:
        # Fichier vide ou contenant uniquement des commentaires
        print("ERREUR: Le fichier YAML est vide")
        sys.exit(1)
    if not isinstance(data, dict):
        print("ERREUR: La racine n'est pas un dictionnaire")
        sys.exit(1)
    # Vérification spécifique pour late-commands avec heredoc
    if 'autoinstall' in data and 'late-commands' in data['autoinstall']:
        late_cmds = data['autoinstall']['late-commands']
        if not isinstance(late_cmds, list):
            print("ERREUR: late-commands n'est pas une liste")
            sys.exit(1)
        # Pas d'erreur supplémentaire, le heredoc est déjà dans une chaîne multiligne
    print("OK")
    sys.exit(0)
except yaml.YAMLError as e:
    print(f"ERREUR YAML: {e}")
    sys.exit(1)
except Exception as e:
    print(f"ERREUR: {e}")
    sys.exit(1)
PYEOF

    local output
    output=$(python3 "$tmp_script" "$user_data_file" 2>&1)
    local ret=$?
    
    if [ $ret -eq 0 ] && echo "$output" | grep -q "OK"; then
        echo -e "${GREEN}   ✅ Syntaxe YAML valide !${NC}"
        rm -f "$tmp_script"
        return 0
    else
        echo -e "${RED}   ❌ Erreur de syntaxe YAML détectée !${NC}"
        echo "$output"
        echo -e "${YELLOW}   Affichage des 20 premières lignes du fichier :${NC}"
        head -20 "$user_data_file"
        rm -f "$tmp_script"
        exit 1
    fi
}

# 9) Intégration de l'autoinstall dans l'ISO extraite
09_integrate_autoinstall() {
    cp -r "$AUTOINSTALL_DIR" "$EXTRACT_DIR/"
}

# 10) Modification du fichier grub.cfg avec le template GitHub
10_modify_grub_cfg() {
    echo ""
    echo -e "${YELLOW}10) Configuration du menu GRUB...${NC}"
    GRUB_CFG="$EXTRACT_DIR/boot/grub/grub.cfg"

    if [ ! -f "$GRUB_CFG" ]; then
        echo -e "${RED}   Fichier grub.cfg introuvable dans l'ISO extraite !${NC}"
        exit 1
    fi

    # Sauvegarde de l'original
    cp "$GRUB_CFG" "$GRUB_CFG.orig"

    # Téléchargement du template depuis GitHub
    local TEMPLATE_DIR=$(mktemp -d)
    local TEMPLATE_FILE="$TEMPLATE_DIR/grub.cfg.template"

    echo -e "${CYAN}   Téléchargement du template GRUB depuis GitHub...${NC}"
    wget -O "$TEMPLATE_FILE" "$GRUB_CFG_TEMPLATE_URL"
    WGET_RET=$?

    if [ $WGET_RET -ne 0 ] || [ ! -f "$TEMPLATE_FILE" ]; then
        echo -e "${RED}   Erreur : téléchargement du template GRUB échoué.${NC}"
        rm -rf "$TEMPLATE_DIR"
        exit 1
    fi

    echo -e "${GREEN}   Template téléchargé avec succès. Personnalisation...${NC}"
    
    # Personnalisation du template avec les variables du projet
    sed -e "s|__PROJECT_NAME__|${PROJECT_NAME}|g" \
        -e "s|__PROJECT_LOWER__|${PROJECT_NAME_LOWER}|g" \
        -e "s|__PROJECT_UPPER__|${PROJECT_NAME_UPPER}|g" \
        "$TEMPLATE_FILE" > "$GRUB_CFG"

    # Vérification que l'entrée autoinstall est présente
    if ! grep -q "Autoinstallation Ubuntu Server" "$GRUB_CFG"; then
        echo -e "${RED}   ERREUR : L'entrée autoinstall n'a pas été ajoutée dans le template.${NC}"
        rm -rf "$TEMPLATE_DIR"
        exit 1
    fi

    # Copie vers les répertoires UEFI
    for uefi_dir in "$EXTRACT_DIR/EFI/BOOT" "$EXTRACT_DIR/EFI/ubuntu"; do
        mkdir -p "$uefi_dir"
        cp "$GRUB_CFG" "$uefi_dir/grub.cfg"
        echo -e "${GREEN}   Copie vers $uefi_dir/grub.cfg${NC}"
    done

    # Téléchargement du splash GRUB
    SPLASH_URL="${GITHUB_URL}/boot/grub/splash.png"
    wget -O "$EXTRACT_DIR/boot/grub/splash.png" "$SPLASH_URL" 2>/dev/null
    if [ -f "$EXTRACT_DIR/boot/grub/splash.png" ]; then
        echo -e "${GREEN}   Splash GRUB installé.${NC}"
    else
        echo -e "${YELLOW}   ⚠ Splash non disponible, menu GRUB sans fond.${NC}"
    fi

    # Nettoyage
    rm -rf "$TEMPLATE_DIR"
    echo -e "${GREEN}   GRUB configuré avec le template personnalisé.${NC}"
}

# 11) Création de l'ISO avec xorriso (détection automatique)
11_create_iso() {
    echo ""
    echo -e "${YELLOW}11) Création de la nouvelle ISO (avec xorriso)...${NC}"

    # Vérification du fichier de boot BIOS
    if [ ! -f "$EXTRACT_DIR/boot/grub/i386-pc/eltorito.img" ]; then
        echo -e "${RED}   Erreur : fichier 'boot/grub/i386-pc/eltorito.img' introuvable. Vérifiez la structure de l'ISO extraite.${NC}"
        exit 1
    fi

    # Sauvegarde de l'ancienne ISO si elle existe
    if [ -f "$OUTPUT_ISO" ]; then
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_ISO="${OUTPUT_ISO%.*}_${TIMESTAMP}.${OUTPUT_ISO##*.}"
        mv "$OUTPUT_ISO" "$BACKUP_ISO"
        echo ""
        echo -e "${GREEN}   Ancienne ISO sauvegardée sous : $BACKUP_ISO${NC}"
    fi

    # Création de l'ISO hybride (BIOS + UEFI)
    echo ""
    echo -e "${GREEN}   Création de l'ISO bootable hybride (BIOS + UEFI)...${NC}"

    # Détection du fichier EFI réel
    if [ -f "$EXTRACT_DIR/EFI/boot/bootx64.efi" ]; then
        EFI_BOOT="EFI/boot/bootx64.efi"
    else
        echo -e "${RED}   ERREUR : bootx64.efi introuvable !${NC}"
        exit 1
    fi

    # Vérification de la présence du fichier isohdpfx.bin pour l'hybridation MBR
    ISOLINUX_MBR="/usr/lib/ISOLINUX/isohdpfx.bin"
    if [ ! -f "$ISOLINUX_MBR" ]; then
        echo -e "${RED}   ERREUR : isohdpfx.bin manquant (installer syslinux-common)${NC}"
        exit 1
    fi

    # Commande xorriso pour générer l'ISO hybride
    xorriso -as mkisofs \
        -r -V "$LABEL" \
        -o "$OUTPUT_ISO" \
        -J -joliet-long -l \
        -iso-level 3 \
        -isohybrid-mbr "$ISOLINUX_MBR" \
        -partition_offset 16 \
        -c boot.catalog \
        -b boot/grub/i386-pc/eltorito.img \
            -no-emul-boot \
            -boot-load-size 4 \
            -boot-info-table \
        -eltorito-alt-boot \
        -e "$EFI_BOOT" \
            -no-emul-boot \
        -isohybrid-gpt-basdat \
        "$EXTRACT_DIR"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}   ISO créée avec succès : $OUTPUT_ISO${NC}"
    else
        echo -e "${RED}   Échec de la création de l'ISO. Vérifiez les messages ci-dessus.${NC}"
        exit 1
    fi

    # Vérification que le dossier autoinstall a bien été intégré
    if command -v isoinfo &>/dev/null; then
        echo ""
        echo -e "${YELLOW}   Vérification du contenu de l'ISO avec isoinfo...${NC}"
        if isoinfo -R -l -i "$OUTPUT_ISO" | grep -q "autoinstall"; then
            echo -e "${GREEN}   ✅ Dossier autoinstall présent dans l'ISO.${NC}"
        else
            echo -e "${RED}   ❌ Dossier autoinstall non trouvé dans l'ISO !${NC}"
            exit 1
        fi
    fi
}

# 12) Validation de l'ISO générée
12_validate_iso() {
    local iso_path="$1"
    local mount_dir="/tmp/${PROJECT_NAME_LOWER}-iso-check"
    local checks_passed=0
    local checks_failed=0

    echo ""
    echo -e "${YELLOW}12) Validation de l'ISO générée...${NC}"
    echo ""

    # Montage de l'ISO
    mkdir -p "$mount_dir"
    if ! mount -o loop,ro "$iso_path" "$mount_dir" 2>/dev/null; then
        # Fallback avec sudo et mot de passe
        if ! printf '%s\n' "$SUDO_PASSWORD" | sudo -S mount -o loop,ro "$iso_path" "$mount_dir" 2>/dev/null; then
            echo -e "  ${YELLOW}⚠ Impossible de monter l'ISO pour validation (droits insuffisants).${NC}"
            echo -e "  ${YELLOW}  Vérification par taille et checksum uniquement.${NC}"
            
            # Vérification taille minimale (> 1 Go)
            local iso_bytes=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
            if [ -n "$iso_bytes" ] && [ "$iso_bytes" -gt 1073741824 ]; then
                echo -e "  ${GREEN}✔ Taille cohérente ($iso_bytes octets > 1 Go)${NC}"
            else
                echo -e "  ${RED}✘ Taille suspecte ($iso_bytes octets < 1 Go)${NC}"
            fi

            # SHA256
            local sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
            echo -e "  ${CYAN}🔑 SHA256 : $sha256${NC}"
            echo ""
            return
        fi
    fi

    # 1. Vérifier autoinstall/user-data
    if [ -f "$mount_dir/autoinstall/user-data" ]; then
        echo -e "  ${GREEN}✔ autoinstall/user-data présent${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ autoinstall/user-data MANQUANT${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 2. Vérifier autoinstall/meta-data
    if [ -f "$mount_dir/autoinstall/meta-data" ]; then
        echo -e "  ${GREEN}✔ autoinstall/meta-data présent${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ autoinstall/meta-data MANQUANT${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 3. Vérifier que firstboot.sh est référencé dans user-data
    if grep -q "firstboot.sh" "$mount_dir/autoinstall/user-data" 2>/dev/null; then
        echo -e "  ${GREEN}✔ firstboot.sh référencé dans user-data${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ firstboot.sh NON référencé dans user-data${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 4. Vérifier structure boot UEFI
    if [ -d "$mount_dir/EFI" ] || [ -f "$mount_dir/boot/grub/efi.img" ]; then
        echo -e "  ${GREEN}✔ Structure boot UEFI présente${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ Structure boot UEFI MANQUANTE${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # 5. Vérifier structure boot BIOS
    if [ -d "$mount_dir/boot/grub/i386-pc" ] || [ -d "$mount_dir/isolinux" ] || [ -f "$mount_dir/boot/grub/i386-pc/eltorito.img" ]; then
        echo -e "  ${GREEN}✔ Structure boot BIOS présente${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${YELLOW}⚠ Structure boot BIOS absente (UEFI uniquement)${NC}"
    fi

    # 6. Vérification taille minimale
    local iso_bytes=$(stat -c%s "$iso_path" 2>/dev/null || stat -f%z "$iso_path" 2>/dev/null)
    if [ -n "$iso_bytes" ] && [ "$iso_bytes" -gt 1073741824 ]; then
        echo -e "  ${GREEN}✔ Taille cohérente ($(du -h "$iso_path" | cut -f1) > 1 Go)${NC}"
        checks_passed=$((checks_passed + 1))
    else
        echo -e "  ${RED}✘ Taille suspecte ($(du -h "$iso_path" | cut -f1) < 1 Go attendu)${NC}"
        checks_failed=$((checks_failed + 1))
    fi

    # Démontage
    umount "$mount_dir" 2>/dev/null || sudo umount "$mount_dir" 2>/dev/null || true
    rmdir "$mount_dir" 2>/dev/null || true

    # 7. SHA256
    echo ""
    local sha256=$(sha256sum "$iso_path" | cut -d' ' -f1)
    echo -e "  ${CYAN}🔑 SHA256 : $sha256${NC}"

    # Résumé
    echo ""
    if [ "$checks_failed" -eq 0 ]; then
        echo -e "  ${GREEN}✅ Validation réussie ($checks_passed/$checks_passed vérifications OK)${NC}"
    else
        echo -e "  ${RED}⚠ Validation partielle ($checks_passed OK, $checks_failed échouée(s))${NC}"
        echo -e "  ${RED}  L'ISO peut ne pas fonctionner correctement.${NC}"
    fi
    echo ""
}

# 13) Demande de gravure sur clé USB
13_burn_iso() {
    local iso_path="$1"
    echo ""
    echo -e "${YELLOW}13) Voulez-vous graver cette ISO sur une clé USB ? (o/n)${NC}"
    read -r answer
    if [[ ! "$answer" =~ ^[OoYy]$ ]]; then
        echo -e "${GREEN}   Vous pourrez graver l'ISO plus tard avec la commande :${NC}"
        echo -e "  sudo dd if=$iso_path of=/dev/sdX bs=4M status=progress conv=fsync"
        return
    fi

    # Vérifier les droits sudo
    if ! sudo -v &>/dev/null; then
        echo -e "${RED}   Vous devez avoir les droits sudo pour graver une clé USB.${NC}"
        return
    fi

    # Calculer un hash de vérification (SHA256 des 10 premiers Mo de l'ISO)
    echo ""
    echo -e "${GREEN}   Calcul de l'empreinte de vérification de l'ISO...${NC}"
    local iso_hash=$(dd if="$iso_path" bs=1M count=10 2>/dev/null | sha256sum | awk '{print $1}')
    echo -e "${GREEN}   Empreinte (10 premiers Mo) : $iso_hash"

    while true; do
        echo ""
        echo -e "${YELLOW}   Recherche des périphériques USB...${NC}"
        
        # Liste des périphériques de type disk, avec transport USB, et taille < 64 Go
        mapfile -t devices < <(lsblk -d -o NAME,SIZE,TYPE,TRAN -n -l 2>/dev/null | grep -E 'disk.*usb' | awk '$2 ~ /^[0-9.]+[GM]?/ { if ($2 ~ /G/ && $2+0 < 64) print; else if ($2 ~ /M/ && $2+0 < 64000) print }')
        
        # Si pas de périphérique USB détecté, élargir à tout disk de taille < 64G
        if [ ${#devices[@]} -eq 0 ]; then
            mapfile -t devices < <(lsblk -d -o NAME,SIZE,TYPE -n -l 2>/dev/null | grep disk | awk '$2 ~ /^[0-9.]+[GM]?/ { if ($2 ~ /G/ && $2+0 < 64) print; else if ($2 ~ /M/ && $2+0 < 64000) print }')
        fi

        if [ ${#devices[@]} -eq 0 ]; then
            echo -e "${RED}   Aucune clé USB détectée.${NC}"
            echo -e "${YELLOW}  Insérez une clé USB, puis appuyez sur Entrée pour réessayer, ou tapez 'q' pour quitter.${NC}"
            read -r retry
            if [[ "$retry" == "q" ]]; then
                echo -e "${GREEN}   Gravure annulée.${NC}"
                return
            fi
            continue
        fi

        # Afficher les périphériques trouvés
        echo -e "${GREEN}   Périphériques détectés :"
        local i=1
        for dev in "${devices[@]}"; do
            name=$(echo "$dev" | awk '{print $1}')
            size=$(echo "$dev" | awk '{print $2}')
            echo "   $i) /dev/$name ($size)"
            ((i++))
        done
        echo -e "${YELLOW}   Choisissez le numéro du périphérique à utiliser, ou 'q' pour annuler :${NC}"
        read -r choice
        if [[ "$choice" == "q" ]]; then
            echo -e "${GREEN}   Gravure annulée.${NC}"
            return
        fi
        if ! [[ "$choice" =~ ^[0-9]+$ ]] || [ "$choice" -lt 1 ] || [ "$choice" -gt ${#devices[@]} ]; then
            echo -e "${RED}   Choix invalide.${NC}"
            continue
        fi

        selected_dev="/dev/$(echo "${devices[$((choice-1))]}" | awk '{print $1}')"

        # Vérifier que le périphérique existe toujours
        if [ ! -e "$selected_dev" ]; then
            echo -e "${RED}   Le périphérique $selected_dev n'existe plus. Il a peut-être été retiré.${NC}"
            continue
        fi

        # Vérifier la taille de la clé par rapport à l'ISO via sysfs
        iso_size=$(stat -c%s "$iso_path")
        devname=$(basename "$selected_dev")
        if [ -e "/sys/block/$devname/size" ]; then
            sectors=$(cat "/sys/block/$devname/size")
            dev_size=$((sectors * 512))
        else
            echo -e "${RED}   Impossible de déterminer la taille du périphérique $selected_dev.${NC}"
            continue
        fi

        if [ "$iso_size" -gt "$dev_size" ]; then
            echo -e "${RED}   L'ISO ($(numfmt --to=iec $iso_size)) est plus grande que la clé ($(numfmt --to=iec $dev_size)). Impossible de graver.${NC}"
            continue
        fi

        # Vérifier si le périphérique a des partitions montées
        # Correction : utiliser -l pour éviter les caractères graphiques
        mounted_partitions=$(lsblk -lno NAME,MOUNTPOINT "$selected_dev" 2>/dev/null | awk '$2 {print $1, $2}')
        if [ -n "$mounted_partitions" ]; then
            echo -e "${RED}  Le périphérique $selected_dev a des partitions montées :${NC}"
            echo "$mounted_partitions"
            echo -e "${YELLOW}  Voulez-vous démonter automatiquement ces partitions ? (o/N)${NC}"
            read -r unmount_answer
            if [[ "$unmount_answer" =~ ^[OoYy]$ ]]; then
                # On traite chaque partition montée
                while IFS= read -r line; do
                    dev=$(echo "$line" | awk '{print $1}')          # ex: sdb1
                    mp=$(echo "$line" | awk '{print $2}')           # ex: /media/claude/PHILIPS
                    echo -e "   Démontage de $mp (périphérique /dev/$dev)..."

                    # Quitter le point de montage si on est dedans (seulement si le répertoire existe)
                    if [ -d "$mp" ] && [[ "$PWD" == "$mp"* ]]; then
                        echo "   ⚠️ Vous êtes dans $mp → déplacement vers /tmp"
                        cd /tmp || exit 1
                    fi

                    # Tentative de démontage : d'abord par point de montage s'il existe, sinon par périphérique
                    if [ -d "$mp" ]; then
                        # Le point de montage existe
                        if sudo umount "$mp"; then
                            echo "   ✅ Démonté proprement"
                            continue
                        fi
                        echo "   ⚠️ Échec, tentative lazy unmount..."
                        if sudo umount -l "$mp"; then
                            echo "   ✅ Démonté (lazy)"
                            continue
                        fi
                    else
                        # Le point de montage n'existe pas, on passe directement au démontage par périphérique
                        echo "   ⚠️ Le point de montage $mp n'existe pas, tentative par périphérique /dev/$dev..."
                        if sudo umount "/dev/$dev"; then
                            echo "   ✅ Démonté par périphérique"
                            continue
                        fi
                        echo "   ⚠️ Échec, tentative lazy unmount sur périphérique..."
                        if sudo umount -l "/dev/$dev"; then
                            echo "   ✅ Démonté (lazy par périphérique)"
                            continue
                        fi
                    fi

                    # Si on arrive ici, aucun démontage n'a réussi
                    echo "   ❌ Toujours bloqué → processus utilisant le disque :"
                    if [ -d "$mp" ]; then
                        fuser -vm "$mp"
                    else
                        fuser -vm "/dev/$dev"
                    fi
                    echo -e "${RED}   Échec définitif du démontage.${NC}"
                    continue 2   # retourne au choix du périphérique
                done <<< "$mounted_partitions"
            else
                echo -e "${RED}   Veuillez démonter manuellement les partitions avant de continuer.${NC}"
                continue
            fi
        fi

        echo -e "${RED}   Attention : vous allez écraser toutes les données sur $selected_dev.${NC}"
        echo -e "${YELLOW}   Êtes-vous sûr de vouloir continuer ? (o/n)${NC}"
        read -r confirm
        if [[ ! "$confirm" =~ ^[OoYy]([Ee][Ss]?)?$ ]]; then
            echo -e "${GREEN}   Gravure annulée.${NC}"
            return
        fi

        # Exécuter la gravure
        echo ""
        echo -e "${YELLOW}   Gravure de l'ISO sur $selected_dev...${NC}"
        sudo dd if="$iso_path" of="$selected_dev" bs=4M status=progress conv=fsync

        if [ $? -ne 0 ]; then
            echo -e "${RED}   Erreur lors de la gravure. Vérifiez que vous avez les droits sudo et que le périphérique n'est pas monté.${NC}"
            continue
        fi

        # Vider les caches et forcer l'écriture
        sync
        sudo blockdev --flushbufs "$selected_dev" 2>/dev/null || true  # Ignorer si échec

        # Vérification par hash (10 premiers Mo)
        echo ""
        echo -e "${YELLOW}   Vérification de l'écriture par comparaison d'empreinte...${NC}"
        local dev_hash=$(sudo dd if="$selected_dev" bs=1M count=10 2>/dev/null | sha256sum | awk '{print $1}')
        if [ "$dev_hash" = "$iso_hash" ]; then
            echo -e "${GREEN}   Vérification réussie : l'empreinte correspond. La gravure est valide."
            echo -e "   Vous pouvez maintenant installer Ubuntu Server sur votre mini-PC avec cette clé.${NC}"
        else
            echo -e "${RED}   Échec de la vérification : l'empreinte ne correspond pas."
            echo -e "   ISO hash   : $iso_hash"
            echo -e "   Clé hash   : $dev_hash"
            echo -e "${YELLOW}   Voulez-vous réessayer la gravure sur le même périphérique ? (o/n)${NC}"
            read -r retry_write
            if [[ "$retry_write" =~ ^[OoYy]$ ]]; then
                continue
            else
                echo -e "${GREEN}   Gravure annulée.${NC}"
            fi
        fi
        break
    done
}

# ------------------------------
# Nettoyage après usage (important !)
# ------------------------------
cleanup() {
    unset SUDO_PASSWORD
}
trap cleanup EXIT

# ------------------------------
# Exécution principale
# ------------------------------
main() {

    001_parse_arguments "$@"
    002_setup_work_dir

	# --- Début logging ---
	LOG_FILE="${WORK_DIR}/neurhomia-build-$(date +%Y%m%d_%H%M%S).log"

	exec > >(tee >(sed -E 's/\x1b\[[0-9;]*m//g' >> "$LOG_FILE")) 2>&1
	echo -e "${GREEN}Log enregistré dans : $LOG_FILE${NC}"
    echo "========================================="
	echo "Début de build-iso.sh : $(date)"
	echo "Exécuté par : $(whoami)"
	echo "========================================="
	# ---------------------

    
    01_ask_ubuntu_version
    02_validate_firstboot_script
    03_check_dependencies
    04_prepare_directories
    05_download_iso
    06_extract_iso
    07_generate_password_hash
    08_create_autoinstall_files
    08_validate_yaml
    09_integrate_autoinstall
    10_modify_grub_cfg
    11_create_iso
    12_validate_iso "$OUTPUT_ISO"
    13_burn_iso "$OUTPUT_ISO"

    # Conseils pour vérification manuelle
    echo -e "${YELLOW}"
    echo -e "========================================"
    echo -e "Pour vérifier la présence du dossier autoinstall sur la clé, vous pouvez monter sa première partition avec la commande :"
    echo -e " sudo mount /dev/sdX1 /mnt && ls /mnt/autoinstall"
    echo -e "(Remplacez 'sdX' par le périphérique de votre clé, par exemple sdb)"
    echo -e "========================================${NC}"

    # Installation terminée
    echo -e "${GREEN}"
    echo -e "========================================"
    echo -e "Processus terminé."
    echo -e "ISO disponible : $OUTPUT_ISO"
    echo -e "========================================${NC}"
    echo ""
}

# Lancer le script
main "$@"
