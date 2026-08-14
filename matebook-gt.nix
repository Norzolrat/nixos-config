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

  # nouveau ne gère pas une Ada Lovelace derrière un lien Thunderbolt : init
  # GSP en timeout, erreurs AER, gel puis redémarrage — typiquement au
  # lancement du compositeur, qui est ce qui ouvre les nœuds DRM en premier.
  # Le pilote NVIDIA étant désactivé pour le moment (cf. plus bas), c'est ce
  # blacklist qui empêche tout module de réclamer la carte au branchement.
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
  # eGPU NVIDIA RTX 4070 — DÉSACTIVÉ pour le moment (freeze au boot/branchement)
  #############################################################################
  # Tentative « toujours installé, actif seulement si branché » : a provoqué
  # un freeze. Tout le bloc nvidia est coupé le temps de comprendre pourquoi.
  # nouveau reste blacklisté juste en dessous (section noyau) comme filet de
  # sécurité : sans lui ET sans nvidia, brancher l'eGPU ne ferait rien planter,
  # la carte serait juste inutilisée.

  # services.xserver.videoDrivers = [ "nvidia" ];
  #
  # hardware.nvidia = {
  #   # Ada Lovelace (série 40) : les modules noyau ouverts sont recommandés.
  #   open = true;
  #   modesetting.enable = true;
  #   nvidiaSettings = true;
  #   package = config.boot.kernelPackages.nvidiaPackages.stable;
  #
  #   # Pas de PRIME ici : PRIME sert aux GPU internes muxés, pas à un eGPU.
  #   # Branche ton écran directement sur la 4070 pour éviter le reverse PRIME
  #   # (qui refait passer le rendu par le lien Thunderbolt et coûte des FPS).
  # };

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
    nvtopPackages.full
    alsa-utils
    libinput
    v4l-utils
    libva-utils
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
