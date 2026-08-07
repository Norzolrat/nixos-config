#!/usr/bin/env bash
# Installation automatisée — Huawei MateBook GT.
#
# Depuis le live, une fois le matériel validé avec « test-hardware » :
#     sudo install-matebook
#
# Ce que le script enchaîne :
#   1. partitionnement + formatage, OU réutilisation de partitions existantes
#   2. montage sur /mnt
#   3. nixos-generate-config  → le hardware-configuration.nix de CE disque
#   4. copie du flake embarqué dans le live (/etc/nixos-flake)
#   5. nixos-install --flake .#matebook
#   6. mots de passe root et utilisateur
#   7. dépôt du flake dans ~/nixos, là où pointe l'alias « rebuild »
#
# Rien d'irréversible n'est fait sans confirmation : le plan de
# partitionnement est affiché avant d'être appliqué, et --dry-run montre
# toutes les commandes sans en exécuter aucune.

set -euo pipefail

#############################################################################
# Réglages
#############################################################################

ATTR=matebook          # nixosConfigurations.<attr> à installer
REPO_URL=https://github.com/Norzolrat/nixos-config.git
USERNAME=normi         # doit correspondre au my.username de options.nix
ESP_SIZE=2G            # matebook-gt.nix conserve 10 générations
MNT=/mnt
STAGE=/mnt/etc/nixos-config   # emplacement du flake pendant l'installation

MODE=""                # wipe | reuse | mounted
DISK=""; ESP=""; ROOTP=""; SWAP_SIZE=""
FLAKE_SRC=""
DRY=0
KEEP_ESP=1             # en mode reuse, on ne reformate JAMAIS l'ESP Windows

#############################################################################
# Sorties
#############################################################################

info() { printf '\033[1;34m::\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;32m==>\033[0m \033[1m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m/!\\\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m x\033[0m %s\n' "$*" >&2; exit 1; }
plan() { printf '     %-16s %-8s %s\n' "$@"; }

# Toute commande qui touche au disque passe par run(), pour que --dry-run
# soit réellement fiable. Pas de redirection ici : elle ne serait pas captée.
run() {
  if (( DRY )); then
    printf '   \033[2m[dry-run] %s\033[0m\n' "$*"
  else
    "$@"
  fi
}

confirm() {
  local reply
  (( DRY )) && { info "[dry-run] réponse supposée : oui — $1"; return 0; }
  read -r -p "$(printf '\033[1;33m?\033[0m %s [o/N] ' "$1")" reply
  [[ $reply == [oOyY]* ]]
}

usage() {
  cat <<'EOF'
install-matebook — installe nixosConfigurations.matebook sur ce portable.

  sudo install-matebook                        interactif (recommandé)
  sudo install-matebook --dry-run              montre tout, n'exécute rien

Modes non interactifs :
  --wipe DISQUE          efface tout le disque (ex: --wipe /dev/nvme0n1)
  --esp PART --root PART réutilise l'ESP existant, formate la racine
                         (dual boot Windows : l'ESP n'est PAS reformaté)
  --mounted              /mnt est déjà partitionné, formaté et monté

Options :
  --swap TAILLE          crée une partition de swap (mode --wipe seulement),
                         ex: --swap 32G pour permettre l'hibernation
  --user NOM             utilisateur principal (défaut: normi)
  --flake-source RÉP     source du flake (défaut: /etc/nixos-flake)
  --dry-run, -n          n'exécute rien
  --help, -h
EOF
}

#############################################################################
# Arguments
#############################################################################

while (( $# )); do
  case "$1" in
    --wipe)          MODE=wipe;  DISK="${2:?--wipe attend un disque}"; shift 2 ;;
    --esp)           MODE=reuse; ESP="${2:?--esp attend une partition}"; shift 2 ;;
    --root)          ROOTP="${2:?--root attend une partition}"; shift 2 ;;
    --mounted)       MODE=mounted; shift ;;
    --swap)          SWAP_SIZE="${2:?--swap attend une taille}"; shift 2 ;;
    --user)          USERNAME="${2:?--user attend un nom}"; shift 2 ;;
    --flake-source)  FLAKE_SRC="${2:?--flake-source attend un répertoire}"; shift 2 ;;
    -n|--dry-run)    DRY=1; shift ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "argument inconnu : $1 (voir --help)" ;;
  esac
done

#############################################################################
# Vérifications préalables
#############################################################################

step "Vérifications"

(( EUID == 0 )) || die "à lancer avec sudo."

# En dry-run on veut pouvoir relire le plan depuis n'importe où — typiquement
# depuis WSL, avant même d'avoir gravé l'ISO. Les contrôles qui dépendent de
# la vraie machine deviennent donc de simples avertissements.
require() { if (( DRY )); then warn "$1 (ignoré en dry-run)"; else die "$1"; fi; }

[[ -d /sys/firmware/efi ]] || require \
  "démarré en mode BIOS/CSM. Cette config est UEFI uniquement : \
repasse le BIOS en UEFI pur et redémarre le live."

# Les entrées du flake (niri, noctalia, spicetify…) sont téléchargées pendant
# l'évaluation : sans réseau, nixos-install échoue au bout de plusieurs
# minutes. Autant le savoir tout de suite.
if curl -fsS --max-time 10 https://cache.nixos.org/nix-cache-info >/dev/null 2>&1; then
  info "réseau : ok"
else
  require "pas d'accès réseau. Connecte-toi (nmtui) puis relance."
fi

# Localisation du flake.
if [[ -z $FLAKE_SRC ]]; then
  if [[ -e /etc/nixos-flake/flake.nix ]]; then
    FLAKE_SRC=/etc/nixos-flake
  else
    die "flake introuvable. Utilise --flake-source RÉPERTOIRE."
  fi
fi
[[ -e $FLAKE_SRC/flake.nix ]] || die "$FLAKE_SRC ne contient pas de flake.nix"
info "flake : $FLAKE_SRC"

# La partition 1 d'un nvme0n1 s'appelle nvme0n1p1, celle d'un sda s'appelle
# sda1 : le « p » n'apparaît que si le nom du disque finit par un chiffre.
partdev() {
  case "$1" in
    *[0-9]) printf '%sp%s' "$1" "$2" ;;
    *)      printf '%s%s'  "$1" "$2" ;;
  esac
}

#############################################################################
# Choix du mode
#############################################################################

if [[ -z $MODE ]]; then
  step "Disques détectés"
  lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
  cat <<'EOF'

Trois façons d'installer :

  1) Effacer tout un disque         — Windows et ses données disparaissent.
  2) À côté de Windows              — tu as déjà libéré de la place et créé
                                      une partition Linux ; l'ESP de Windows
                                      est réutilisé, jamais reformaté.
  3) /mnt est déjà prêt             — tu as partitionné et monté à la main.

EOF
  read -r -p "$(printf '\033[1;33m?\033[0m Ton choix [1/2/3] ')" choice
  case "$choice" in
    1) MODE=wipe ;;
    2) MODE=reuse ;;
    3) MODE=mounted ;;
    *) die "choix invalide." ;;
  esac
fi

#############################################################################
# Mode 1 — disque entier
#############################################################################

if [[ $MODE == wipe ]]; then
  step "Partitionnement — disque entier"

  if [[ -z $DISK ]]; then
    lsblk -d -o NAME,SIZE,MODEL
    read -r -p "$(printf '\033[1;33m?\033[0m Disque à effacer (ex: /dev/nvme0n1) : ')" DISK
  fi
  [[ -b $DISK ]] || die "$DISK n'est pas un périphérique bloc."

  ESP=$(partdev "$DISK" 1)
  if [[ -n $SWAP_SIZE ]]; then
    SWAPP=$(partdev "$DISK" 2)
    ROOTP=$(partdev "$DISK" 3)
  else
    SWAPP=""
    ROOTP=$(partdev "$DISK" 2)
  fi

  echo
  printf '  Plan pour \033[1m%s\033[0m :\n\n' "$DISK"
  plan "$ESP"   "$ESP_SIZE" "FAT32, /boot (ESP)"
  [[ -n $SWAPP ]] && plan "$SWAPP" "$SWAP_SIZE" "swap"
  plan "$ROOTP" "reste"     "ext4, /"
  echo
  lsblk "$DISK" -o NAME,SIZE,FSTYPE,LABEL || true
  echo
  warn "TOUT le contenu de $DISK sera détruit, Windows compris."
  confirm "Continuer ?" || die "annulé."

  run wipefs -a "$DISK"
  run sgdisk --zap-all "$DISK"
  run sgdisk -n "1:0:+$ESP_SIZE" -t 1:ef00 -c 1:ESP "$DISK"
  if [[ -n $SWAPP ]]; then
    run sgdisk -n "2:0:+$SWAP_SIZE" -t 2:8200 -c 2:swap  "$DISK"
    run sgdisk -n "3:0:0"           -t 3:8300 -c 3:nixos "$DISK"
  else
    run sgdisk -n "2:0:0"           -t 2:8300 -c 2:nixos "$DISK"
  fi
  run partprobe "$DISK"
  run udevadm settle

  step "Formatage"
  run mkfs.fat -F 32 -n BOOT "$ESP"
  run mkfs.ext4 -F -L nixos "$ROOTP"
  if [[ -n $SWAPP ]]; then
    run mkswap -L swap "$SWAPP"
    run swapon "$SWAPP"      # actif = détecté par nixos-generate-config
  fi
fi

#############################################################################
# Mode 2 — à côté de Windows
#############################################################################

if [[ $MODE == reuse ]]; then
  step "Partitionnement — réutilisation de l'existant"

  if [[ -z $ESP ]]; then
    lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME
    echo
    info "L'ESP est la partition FAT32 d'environ 100 Mo à 2 Go, type « EFI System »."
    read -r -p "$(printf '\033[1;33m?\033[0m Partition ESP existante : ')" ESP
  fi
  if [[ -z $ROOTP ]]; then
    read -r -p "$(printf '\033[1;33m?\033[0m Partition racine à formater en ext4 : ')" ROOTP
  fi
  [[ -b $ESP ]]   || die "$ESP n'est pas un périphérique bloc."
  [[ -b $ROOTP ]] || die "$ROOTP n'est pas un périphérique bloc."
  [[ $ESP != "$ROOTP" ]] || die "l'ESP et la racine ne peuvent pas être la même partition."

  # Garde-fou : reformater l'ESP effacerait le Boot Manager de Windows.
  if [[ $(lsblk -no FSTYPE "$ESP") != vfat ]]; then
    warn "$ESP n'est pas en FAT32 — ce n'est probablement pas l'ESP."
    confirm "Continuer quand même ?" || die "annulé."
  fi

  echo
  printf '     %-16s %s\n' "$ESP"   "monté sur /boot, CONSERVÉ tel quel"
  printf '     %-16s %s\n' "$ROOTP" "FORMATÉ en ext4, monté sur /"
  echo
  lsblk -o NAME,SIZE,FSTYPE,LABEL "$ROOTP"
  echo
  warn "Le contenu de $ROOTP sera détruit. $ESP ne sera pas touché."
  confirm "Continuer ?" || die "annulé."

  step "Formatage"
  run mkfs.ext4 -F -L nixos "$ROOTP"
fi

#############################################################################
# Montage
#############################################################################

if [[ $MODE != mounted ]]; then
  step "Montage sur $MNT"
  run mount "$ROOTP" "$MNT"
  run mkdir -p "$MNT/boot"
  # umask=0077 : sans ça, systemd-boot (et plus tard lanzaboote) protestent
  # que l'ESP est lisible par tout le monde.
  run mount -o umask=0077 "$ESP" "$MNT/boot"
else
  step "Vérification du montage existant"
  mountpoint -q "$MNT"      || die "$MNT n'est pas monté."
  mountpoint -q "$MNT/boot" || die "$MNT/boot n'est pas monté (l'ESP doit y être)."
fi
findmnt -R "$MNT" -o TARGET,SOURCE,FSTYPE || true

#############################################################################
# hardware-configuration.nix
#############################################################################

step "Génération du hardware-configuration.nix"

# C'est le seul fichier que le dépôt ne peut pas contenir à l'avance : il
# décrit les UUID des partitions qu'on vient de créer.
run nixos-generate-config --root "$MNT"

HW="$MNT/etc/nixos/hardware-configuration.nix"
if (( ! DRY )); then
  [[ -f $HW ]] || die "hardware-configuration.nix non généré."
  grep -q 'fileSystems."/"' "$HW" || die "le fichier généré ne décrit aucune racine."
  info "racine et /boot détectés :"
  grep -E 'device = |fsType = |swapDevices' "$HW" | sed 's/^/     /'
fi

#############################################################################
# Mise en place du flake
#############################################################################

step "Copie du flake vers $STAGE"

# --copy-links : /etc/nixos-flake est un lien vers le store.
# --chmod : le store est en lecture seule, on veut une copie modifiable.
# --exclude result : IMPÉRATIF. C'est un lien vers le store, et le suivre
#   copierait la closure entière d'un système NixOS sur /mnt.
run rm -rf "$STAGE"
run mkdir -p "$STAGE"
run rsync -a --copy-links --chmod=Du+w,Fu+w \
  --exclude=result --exclude=.direnv --exclude=.git \
  "$FLAKE_SRC/" "$STAGE/"
run cp "$HW" "$STAGE/hardware-configuration.nix"
info "flake.nix, modules et hardware-configuration.nix en place"

#############################################################################
# Installation
#############################################################################

step "nixos-install — .#$ATTR"

cat <<EOF

  La plupart des paquets (niri, noctalia, steam…) sont déjà dans le store du
  live : ils seront copiés, pas retéléchargés. Seules les sources des entrées
  du flake sont récupérées sur le réseau. Compte tout de même 10 à 30 min.

EOF

# --no-root-password : on gère les deux mots de passe nous-mêmes, juste après,
# pour que l'échec éventuel de l'un n'annule pas l'installation entière.
run nixos-install --root "$MNT" --flake "$STAGE#$ATTR" --no-root-password

#############################################################################
# Mots de passe
#############################################################################

step "Mots de passe"

if (( DRY )); then
  info "[dry-run] passwd root puis passwd $USERNAME dans le système installé"
else
  echo "  Mot de passe root :"
  until nixos-enter --root "$MNT" -c "passwd root"; do
    warn "échec, on recommence."
  done
  echo "  Mot de passe de $USERNAME :"
  until nixos-enter --root "$MNT" -c "passwd $USERNAME"; do
    warn "échec, on recommence."
  done
fi

#############################################################################
# Le flake dans ~/nixos
#############################################################################

step "Dépôt du flake dans /home/$USERNAME/nixos"

# desktop.nix définit l'alias : rebuild = nixos-rebuild switch --flake ~/nixos#matebook
# Le flake doit donc finir là, et appartenir à l'utilisateur.
run nixos-enter --root "$MNT" -c \
  "mkdir -p /home/$USERNAME && cp -r /etc/nixos-config /home/$USERNAME/nixos && chown -R $USERNAME:users /home/$USERNAME/nixos"
run rm -rf "$STAGE"

#############################################################################
# Fin
#############################################################################

step "Terminé"

cat <<EOF

  Redémarre, retire la clé USB, et connecte-toi en « $USERNAME ».

  Ensuite, dans l'ordre :

    1. Rebrancher ~/nixos sur le dépôt Git. La copie posée par l'installeur
       vient de l'ISO : elle n'a pas d'historique. Pour la reconnecter sans
       perdre le hardware-configuration.nix qu'on vient de générer :

         cd ~/nixos
         git init -b main
         git remote add origin $REPO_URL
         git fetch origin && git reset origin/main
         git add hardware-configuration.nix
         git commit -m "hardware: matebook"

       (hardware-configuration.nix décrit les UUID de CE disque : il doit être
       versionné, sinon une réinstallation repart de zéro.)

    2. Vérifier le matériel une dernière fois : test-hardware

    3. eGPU — brancher le boîtier, puis :

         boltctl list
         sudo boltctl enroll <uuid>

       et redémarrer sur l'entrée « egpu » du menu (spécialisation définie
       dans matebook-gt.nix).

    4. Secure Boot : seulement une fois que tout le reste fonctionne. La
       procédure complète, étape par étape, est en tête de secureboot.nix.

  Pour toute modification ultérieure : édite ~/nixos puis tape « rebuild ».

EOF

if [[ $MODE == reuse ]]; then
  cat <<'EOF'
  Dual boot : systemd-boot détecte seul le Windows Boot Manager présent sur
  l'ESP partagé et l'ajoute au menu. Si l'entrée manque au premier démarrage,
  vérifie que /boot/EFI/Microsoft existe toujours.

EOF
fi
