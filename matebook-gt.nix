# Configuration NixOS — Huawei MateBook GT (ENZH-XX)
# Intel Core Ultra 7 155H (Meteor Lake) + eGPU NVIDIA RTX 4070 en Thunderbolt 4
#
# À importer depuis configuration.nix, en plus de ./hardware-configuration.nix
# généré par `nixos-generate-config`.

{ config, lib, pkgs, ... }:

{
  imports = [
    # nixos-hardware : pas de profil MateBook GT, on prend les génériques
    # <nixos-hardware/common/cpu/intel>
    # <nixos-hardware/common/pc/laptop/ssd>
  ];

  nixpkgs.config.allowUnfree = true;

  #############################################################################
  # Noyau et firmware
  #############################################################################

  # Meteor Lake profite encore de correctifs récents (xe, SOF, IPU6, VPU).
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.enableAllFirmware = true;
  hardware.cpu.intel.updateMicrocode = true;

  boot.kernelParams = [
    # Laisse le noyau gérer les ports PCIe : indispensable pour le hotplug
    # Thunderbolt de l'eGPU.
    "pcie_ports=native"

    # Second verrou contre nouveau : agit avant que modprobe.d ne soit lu.
    "nouveau.modeset=0"
  ];

  # Redondant depuis la réactivation de nvidia : le module NixOS blackliste déjà
  # nouveau, nova_core et nvidiafb de lui-même. On le garde comme filet — il
  # agit même si le bloc nvidia venait à être recommenté, et nouveau ne sait pas
  # initialiser une Ada Lovelace au bout d'un tunnel Thunderbolt.
  # À noter : nvidiafb existe bien dans ce noyau et n'était PAS couvert ici ;
  # c'est le module NixOS qui bouche ce trou au passage.
  boot.blacklistedKernelModules = [ "nouveau" ];

  #############################################################################
  # Boot
  #############################################################################

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # L'ESP fait 2 Go : on peut se permettre de garder des générations.
  boot.loader.systemd-boot.configurationLimit = 10;

  # Si tu gardes Secure Boot activé, remplace systemd-boot par lanzaboote.

  #############################################################################
  # Graphique intégré — Intel Arc (Meteor Lake)
  #############################################################################

  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver   # VA-API (iHD)
      vpl-gpu-rt           # oneVPL, encodage/décodage QSV sur Meteor Lake
      intel-compute-runtime # OpenCL
    ];
  };

  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  #############################################################################
  # Thunderbolt / USB4 — autorisation des périphériques (eGPU)
  #############################################################################

  services.hardware.bolt.enable = true;
  # Après le premier branchement : `boltctl list` puis `boltctl enroll <uuid>`

  #############################################################################
  # eGPU NVIDIA RTX 4070 (Thunderbolt 5)
  #############################################################################
  # Avec le module NVIDIA ouvert, la carte décrochait ~7 s après le chargement du
  # pilote : le lien Thunderbolt tombait pendant le démarrage du firmware GSP
  # (« retimer disconnected », puis Xid 79 « GPU has fallen off the bus »), et au
  # démarrage avec le dock branché la machine se coupait en boucle. Résolu le
  # 2026-09-13 en passant au module fermé sans GSP (voir hardware.nvidia).
  #
  # Écartés en chemin, sans effet : alimentation, câble, écran branché,
  # pcie_port_pm=off, thunderbolt.clx=0, ASPM en « performance ». Le matériel
  # n'a jamais été en cause : il fonctionne tel quel sous Windows.
  #
  # Ce qui rend ce bloc sûr quand l'eGPU est ABSENT : services.xserver.enable
  # vaut false (niri est du Wayland pur), or le module NixOS ne met "nvidia",
  # "nvidia_modeset" et "nvidia_drm" dans boot.kernelModules que si X11 est
  # activé. Ils ne sont donc PAS chargés au démarrage : c'est udev qui les
  # charge quand la carte apparaît sur le bus PCI. Pas de dock, pas de pilote.
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware.nvidia = {
    # Module FERMÉ sans firmware GSP — c'est ce qui fait tenir l'eGPU.
    #
    # Le module ouvert (normalement recommandé pour une Ada Lovelace) impose le
    # firmware GSP, dont le démarrage fait tomber le lien Thunderbolt ~7 s après
    # le chargement du pilote. Le module fermé est le seul capable de s'en
    # passer ; vérifié le 2026-09-13 : nvidia-smi voit la carte, aucun Xid, et
    # /proc/driver/nvidia/params indique « EnableGpuFirmware: 0 ».
    # Ne PAS repasser à open = true : le module ouvert refuse de tourner sans GSP
    # (le module NixOS l'impose d'ailleurs par une assertion).
    #
    # Coût sécurité : aucun. Le module NixOS n'ajoute « ibt=off » aux paramètres
    # noyau que si le pilote ne gère pas l'Indirect Branch Tracking ; le module
    # fermé 595.84 la gère (ibtSupport = true). À revérifier en changeant de
    # branche de pilote : `nix eval` sur boot.kernelParams, ibt=off doit en être
    # absent.
    open = false;
    gsp.enable = false;                                 # n'embarque pas le firmware
    moduleParams.nvidia.NVreg_EnableGpuFirmware = 0;    # et interdit au pilote de l'utiliser
    modesetting.enable = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;  # 595.84

    # Laissé au défaut (false) volontairement : la reprise après suspension est
    # le point faible d'un eGPU, le lien Thunderbolt pouvant disparaître pendant
    # le sommeil. À ne tenter qu'une fois le reste stabilisé.
    # powerManagement.enable = false;

    # Pas de PRIME : il sert aux GPU internes muxés et exige des identifiants de
    # bus figés — or celui de l'eGPU disparaît dès qu'on le débranche.
    # L'équivalent ici est prime-run, juste en dessous.
  };

  #############################################################################
  # Choix du GPU — l'Arc affiche, la 4070 calcule à la demande
  #############################################################################
  # niri est épinglé sur l'iGPU Intel par chemin PCI stable, dans
  # niri-config.kdl (bloc debug / render-drm-device). Ce n'est pas un détail :
  # le nommage DRM n'est pas stable — l'Arc est actuellement « card1 » et non
  # « card0 », et ça bougera encore quand la 4070 sera pilotée. Le chemin PCI,
  # lui, ne bouge jamais. C'est ce qui garantit que l'écran du portable
  # fonctionne toujours, eGPU branché ou non, et que le débranchement à chaud
  # ne fait pas tomber la session.
  #
  # Conséquence assumée : tout le rendu de la session passe par l'Arc. Pour
  # qu'un jeu s'exécute réellement sur la 4070, il faut le lancer via prime-run,
  # qui bascule ce seul processus sur la carte :
  #
  #   prime-run vkcube
  #   prime-run steam          (ou, dans les options d'un jeu : prime-run %command%)
  #
  # Sans lui, l'application tourne sur l'Arc — il n'y a pas de bascule
  # automatique, c'est le prix de la robustesse choisie ci-dessus.
  # prime-run est défini plus bas, dans environment.systemPackages.

  #############################################################################
  # Audio — SOF (Meteor Lake) + codec Realtek ALC256
  #############################################################################

  security.rtkit.enable = true;
  services.pulseaudio.enable = false;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # sof-firmware arrive via enableAllFirmware. Le diagnostic du live montre
  # que le noyau applique un correctif générique au codec ALC256 (« picked
  # fixup for PCI SSID 19e5:0000 ») et n'expose que 2 canaux, avec
  # speaker_outs=0. Si les haut-parleurs sont muets ou incomplets, essaie
  # ces modèles UN À LA FOIS :
  #   boot.extraModprobeConfig = ''
  #     options snd-hda-intel model=huawei-mbx-stereo
  #   '';
  # Autres pistes : alc298-huawei-mbx-stereo, dell-headset-multi, auto.
  # Liste complète : Documentation/sound/hd-audio/models.rst

  #############################################################################
  # Webcam IPU6 (MIPI, pas d'UVC — sans ça, aucune caméra)
  #############################################################################

  hardware.ipu6 = {
    enable = true;
    platform = "ipu6epmtl";  # Meteor Lake
  };
  # Fournit v4l2-relayd + un /dev/video virtuel exploitable par les apps.

  #############################################################################
  # Capteurs, écran, entrées
  #############################################################################

  hardware.sensor.iio.enable = true;   # capteur de luminosité (ACPI0008)
  services.libinput.enable = true;     # touchpad SP1520T

  # Écran tactile FTSC1000 : le contrôleur se coince et n'émet plus rien.
  # Symptôme exact : le périphérique reste détecté (udev le marque bien
  # ID_INPUT_TOUCHSCREEN, niri annonce « touch » dans wl_seat), mais
  # `libinput debug-events --device /dev/input/event5` reste muet — aucun
  # réglage du compositeur ne peut donc y changer quoi que ce soit.
  # La trace côté noyau, présente à chaque démarrage :
  #   i2c_hid_acpi i2c-FTSC1000:00: failed to get a report from device: -5
  #   hid-multitouch 0018:2808:5662.0002: failed to fetch feature 5
  #
  # Détacher puis rattacher le pilote i2c-hid relance le dialogue I2C et le
  # tactile repart. On le fait au démarrage et au réveil de veille, les deux
  # moments où le contrôleur peut se retrouver dans cet état.
  #
  # Le touchpad n'est pas touché : c'est un autre périphérique du même bus
  # (i2c-SP1520T:00), et seul FTSC1000 est réattaché ici.
  systemd.services.ftsc1000-rebind = {
    description = "Réinitialise le contrôleur tactile FTSC1000 (i2c-hid)";
    after = [
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    wantedBy = [
      "multi-user.target"
      "suspend.target"
      "hibernate.target"
      "hybrid-sleep.target"
      "suspend-then-hibernate.target"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ftsc1000-rebind" ''
        set -eu
        dev="i2c-FTSC1000:00"
        drv="/sys/bus/i2c/drivers/i2c_hid_acpi"

        # Machine sans cette dalle (ou pilote absent) : on ne fait rien plutôt
        # que d'échouer, le service ne doit jamais bloquer un démarrage.
        [ -d "$drv" ] || exit 0

        if [ -e "$drv/$dev" ]; then
          printf '%s' "$dev" > "$drv/unbind"
          sleep 1
        fi
        printf '%s' "$dev" > "$drv/bind"
      '';
    };
  };

  security.tpm2.enable = true;

  #############################################################################
  # Énergie
  #############################################################################

  services.power-profiles-daemon.enable = true;  # ne pas cumuler avec TLP
  services.thermald.enable = true;
  powerManagement.enable = true;

  environment.systemPackages = with pkgs; [
    powertop
    pciutils
    usbutils
    lm_sensors
    nvtopPackages.full   # affiche les deux GPU : Arc et, si branchée, la 4070
    alsa-utils
    libinput
    v4l-utils
    libva-utils

    # Exécute une seule application sur l'eGPU sans déplacer la session, qui
    # reste rendue par l'Arc (cf. la section « Choix du GPU » plus haut).
    # Refuse de s'exécuter si aucun GPU NVIDIA n'est actif, plutôt que de
    # laisser l'application démarrer silencieusement sur le mauvais GPU.
    (writeShellScriptBin "prime-run" ''
      if [ -z "$(ls -A /proc/driver/nvidia/gpus 2>/dev/null)" ]; then
        echo "prime-run : aucun GPU NVIDIA actif." >&2
        echo "            L'eGPU est-il branché et autorisé ? (boltctl list)" >&2
        exit 1
      fi
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      # La couche NV_optimus ci-dessus ne suffit PAS en Vulkan : la couche Mesa
      # device_select, chargée elle aussi, laisse l'Arc en premier dans la liste,
      # et la plupart des jeux (Proton/DXVK compris) prennent le premier GPU.
      # Vérifié le 2026-09-13 avec vulkaninfo : sans cette ligne, l'Arc reste en
      # tête ; avec, seule la RTX 4070 est visible. Filtrer au niveau du chargeur
      # Vulkan ne dépend d'aucune couche.
      # « *nvidia* » et pas « nvidia* » : le filtre porte sur le nom du fichier
      # du pilote, et le conteneur pressure-vessel des jeux Proton recopie ces
      # fichiers sous un nom préfixé. Mêmes variables dans gaming.nix (Steam).
      export VK_LOADER_DRIVERS_SELECT='*nvidia*'
      exec "$@"
    '')
  ];

  #############################################################################
  # Non supporté sur cette machine — pour mémoire
  #############################################################################
  # - Lecteur d'empreintes Goodix GXFP5130 : aucun pilote libfprint.
  #   Ne pas activer services.fprintd, il ne trouvera aucun périphérique.
  # - NFC Huawei OneHop (NTAG0001) : propriétaire, pas de pilote Linux.
  # - Accélérateur GNA (8086:7e4c) : sans pilote, sans impact.
  # - Le NPU (intel_vpu) est chargé mais nécessite intel-npu-driver côté
  #   userspace pour être exploitable via OpenVINO.
}
