# 🚀 NeurHomIA — Construction d'ISO Ubuntu Server

> 🔥 Génération automatisée d'une ISO Ubuntu Server prête à l’emploi avec **autoinstall**, **LVM**, **Docker** et configuration post-install.

<p align="center">
  <img src="https://img.shields.io/badge/Ubuntu-24.04_LTS-E95420?logo=ubuntu&logoColor=white">
  <img src="https://img.shields.io/badge/License-Apache_2.0-blue">
  <img src="https://img.shields.io/badge/Boot-BIOS%20%2B%20UEFI-green">
  <img src="https://img.shields.io/badge/Automation-100%25-success">
</p>

---

## 📚 Sommaire

* [✨ Fonctionnalités](#-fonctionnalités)
* [⚡ Quick Start](#-quick-start)
* [🧰 Prérequis](#-prérequis)
* [🪜 Installation détaillée](#-installation-détaillée)
* [⚙️ Fonctionnement du script](#-fonctionnement-du-script)
* [🔱 Gravure USB](#-gravure-usb)
* [📁 Structure du dépôt](#-structure-du-dépôt)
* [🧩 Placeholders](#-placeholders)
* [🖼️ Splash GRUB](#-splash-grub)
* [🚀 Script firstboot](#-script-firstboot)
* [⚙️ Options CLI](#-options-cli)
* [📝 Journalisation](#-journalisation)
* [🛠️ Dépannage](#-dépannage)

---

## ✨ Fonctionnalités

* 🤖 Installation **100% automatisée** via autoinstall
* 💾 Partitionnement **LVM prêt à l’emploi**
* 🔐 Sécurisation automatique (**SSH, UFW, fail2ban**)
* 📦 Installation de **Docker + outils essentiels**
* ⚡ Script **firstboot interactif** via systemd (console TTY)
* 💿 ISO **hybride BIOS + UEFI**
* 🖼️ **Splash GRUB** personnalisé avec logo du projet
* 📝 **Journalisation** automatique dans un fichier log horodaté

---

## ⚡ Quick Start

```bash
mkdir -p ~/NeurHomIA-Key
wget -O ~/NeurHomIA-Key/build-iso.sh https://raw.githubusercontent.com/cce66/NeurHomIA-ISO2USB/main/build-iso.sh
chmod +x ~/NeurHomIA-Key/build-iso.sh
cd ~/NeurHomIA-Key
sudo bash build-iso.sh
```

---

## 🧰 Prérequis

* 💻 Ubuntu 20.04 / 22.04 / 24.04
* 🌐 Connexion Internet
* 💾 ~6 Go disque
* 🔐 Accès sudo

### 📦 Dépendances

Installées automatiquement si absentes :

```bash
wget p7zip-full openssl xorriso squashfs-tools schroot rsync syslinux-utils isolinux genisoimage
```

---

## 🪜 Installation détaillée

### 1. 📁 Créer le répertoire

```bash
mkdir -p ~/NeurHomIA-Key
```

### 2. 📶 Télécharger le script

```bash
wget -O ~/NeurHomIA-Key/build-iso.sh https://raw.githubusercontent.com/cce66/NeurHomIA/main/build-iso.sh
```

### 3. 🛠️ Rendre exécutable

```bash
chmod +x ~/NeurHomIA-Key/build-iso.sh
```

### 4. ▶️ Exécuter

```bash
cd ~/NeurHomIA-Key
sudo bash build-iso.sh
```

💡 Si lancé sans sudo, le script demandera le mot de passe lorsque nécessaire.

---

## ⚙️ Fonctionnement du script

Le script exécute les étapes suivantes :

1. 🔍 Validation du script `firstboot.sh`
2. 📦 Installation des dépendances
3. 🌐 Téléchargement de l’ISO Ubuntu
4. 📂 Extraction de l’ISO
5. 🔐 Génération du hash mot de passe
6. 🧩 Génération des fichiers autoinstall
7. ✅ Validation YAML
8. 💉 Injection dans l’ISO
9. ⚙️ Configuration GRUB
10. 💿 Construction ISO finale
11. 🔎 Vérification SHA256
12. 💽 Proposition de gravure USB

---

## 💿 Gravure USB

```bash
sudo dd if=~/neurhomia-key/neurhomia-server-24.04.4-auto.iso \
  of=/dev/sdX bs=4M status=progress conv=fsync
```

⚠️ **Attention : destruction complète des données sur le disque cible**

---

## 📁 Structure du dépôt

```text
build-iso2usb/
├── build-iso.sh
├── autoinstall/
│   ├── user-data.template
│   └── meta-data
├── boot/grub/
│   ├── grub.cfg.template
│   └── splash.png
└── scripts/
    └── firstboot.sh
```

---

## 🧩 Placeholders

### autoinstall

| Placeholder         | Description   |
| ------------------- | ------------- |
| `__HOSTNAME__`      | neurhomia-box |
| `__USERNAME__`      | utilisateur   |
| `__PASSWORD_HASH__` | hash openssl  |
| `__PROJECT_LOWER__` | neurhomia     |
| `__PROJECT_NAME__`  | NeurHomIA     |
| `__FIRSTBOOT_URL__` | URL script    |

### GRUB

| Placeholder         | Valeur    |
| ------------------- | --------- |
| `__PROJECT_NAME__`  | NeurHomIA |
| `__PROJECT_LOWER__` | neurhomia |
| `__PROJECT_UPPER__` | NEURHOMIA |

---

## 🖼️ Splash GRUB

Le menu de boot GRUB affiche une image de fond personnalisée avec le logo NeurHomIA.

* 📍 Image source : `build-iso2usb/boot/grub/splash.png`
* 📐 Résolution recommandée : **1024x768** (PNG)
* ⚙️ Configuré automatiquement via `grub.cfg.template`

Le splash est téléchargé depuis GitHub et injecté dans l'ISO à l'étape 10 du build. Si l'image n'est pas disponible, le menu GRUB s'affiche sans fond (dégradation gracieuse).

Pour personnaliser : remplacer `splash.png` par votre propre image PNG.

---

## 🚀 Script firstboot

📍 `/opt/neurhomia/firstboot.sh`

### Actions exécutées

* 🌍 Configuration timezone
* 🔐 Sécurisation accès
* 🔑 Configuration SSH (fichier dédié `99-neurhomia.conf`)
* 🔥 UFW + fail2ban
* 🐳 Installation Docker Engine (via `get.docker.com`)
* 📡 Configuration MQTT

### ⚡ Exécution interactive

Le service systemd est configuré pour s'exécuter sur la **console physique `tty1`**, permettant l'affichage interactif des dialogues `whiptail` au premier démarrage :

```ini
StandardInput=tty
TTYPath=/dev/tty1
TTYReset=yes
TTYVHangup=yes
```

### 🔑 Configuration SSH

Un fichier de configuration dédié `/etc/ssh/sshd_config.d/99-neurhomia.conf` est créé automatiquement. Si une clé SSH est ajoutée lors du firstboot, l'authentification par mot de passe est désactivée automatiquement.

ℹ️ Le script est validé automatiquement lors du build.

---

## ⚙️ Options CLI

```bash
./build-iso.sh --help
./build-iso.sh --noforce
```

| Option | Description |
| --- | --- |
| `--help`, `-h` | Afficher l'aide et quitter |
| `--noforce` | Arrêter le build si la validation échoue |

---

## 📝 Journalisation

Chaque exécution du script génère automatiquement un fichier log horodaté :

```text
~/neurhomia-build-20250329_143022.log
```

Le log contient l'intégralité de la sortie console et facilite le diagnostic en cas de problème.

---

## 🛠️ Dépannage

### Dépendances

```bash
sudo apt update
sudo apt install wget p7zip-full openssl xorriso
```

### YAML

```bash
sudo apt install python3-yaml
```

### Erreurs fréquentes

* ❌ `eltorito.img` → ISO incompatible
* ❌ GRUB ignoré → vérifier template

---

## 📜 Licence

Apache 2.0

---

## 🤝 Contribuer

PR bienvenues 👍

---

## 🔗 Liens

* GitHub : [https://github.com/cce66/NeurHomIA](https://github.com/cce66/NeurHomIA)
