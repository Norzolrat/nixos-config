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
  ];

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
  # eGPU NVIDIA RTX 4070 — dans une spécialisation
  #############################################################################
  # Le pilote NVIDIA activé en permanence perturbe la session quand l'eGPU est
  # débranché. On garde donc un boot « portable seul » par défaut, et une entrée
  # de menu dédiée à l'eGPU. Branche le boîtier AVANT de démarrer dessus.

  specialisation.egpu.configuration = {
    system.nixos.tags = [ "egpu" ];

    services.xserver.videoDrivers = [ "nvidia" ];

    hardware.nvidia = {
      # Ada Lovelace (série 40) : les modules noyau ouverts sont recommandés.
      open = true;
      modesetting.enable = true;
      nvidiaSettings = true;
      package = config.boot.kernelPackages.nvidiaPackages.stable;

      # Pas de PRIME ici : PRIME sert aux GPU internes muxés, pas à un eGPU.
      # Branche ton écran directement sur la 4070 pour éviter le reverse PRIME
      # (qui refait passer le rendu par le lien Thunderbolt et coûte des FPS).
    };

    # X11 reste plus prévisible qu'un Wayland + eGPU. Si tu tiens à Wayland
    # (Hyprland), ajoute :
    #   environment.sessionVariables = {
    #     LIBVA_DRIVER_NAME = "nvidia";
    #     NVD_BACKEND = "direct";
    #   };
  };

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
  # Le tactile et le stylet FTSC1000 fonctionnent via i2c-hid, rien à faire.

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
