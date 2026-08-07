# ISO live « ton environnement » pour le MateBook GT.
#
# Contrairement à une ISO d'installation classique, celle-ci démarre
# directement dans niri + Noctalia avec tes applications, pour valider
# l'ensemble AVANT de toucher au disque. Rien n'est écrit sur le SSD.
#
# Contrepartie : image de 8 à 12 Go et build long. Voir la section
# « allègement » en bas si c'est trop.

{ config, pkgs, lib, modulesPath, ... }:

{
  imports = [
    # Base d'installation SANS environnement graphique : on fournit le nôtre.
    # (installation-cd-graphical-* imposerait Plasma et Calamares.)
    "${modulesPath}/installer/cd-dvd/installation-cd-base.nix"

    ./options.nix
    ./desktop.nix   # niri, noctalia, fish, alacritty, steam, vscode
    ./apps.nix      # spotify/spicetify, vesktop, onlyoffice, vlc
  ];

  # Le profil d'installation impose le compte « nixos ».
  my.username = "nixos";

  #############################################################################
  # Démarrage automatique dans niri
  #############################################################################
  # Le profil d'installation ouvre une session getty automatique ; on la coupe
  # au profit de greetd, qui lance directement la session niri sans mot de
  # passe. default_session (tuigreet) reste défini par desktop.nix et sert de
  # repli si tu quittes la session.

  services.getty.autologinUser = lib.mkForce null;

  services.greetd.settings.initial_session = {
    command = "niri-session";
    user = config.my.username;
  };

  #############################################################################
  # Matériel — de quoi tester réellement le MateBook GT
  #############################################################################

  boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

  # ZFS ne suit pas les noyaux récents et l'ISO l'embarque par défaut :
  # sans ce retrait, l'évaluation échoue sur « zfs-kernel ... is broken ».
  boot.supportedFilesystems.zfs = lib.mkForce false;

  hardware.enableAllFirmware = true;
  nixpkgs.config.allowUnfree = true;

  # Sans ça, ni « nix shell nixpkgs#... » ni l'installation depuis le flake
  # ne fonctionnent dans le live.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  boot.kernelParams = [ "pcie_ports=native" ];  # hotplug Thunderbolt / eGPU

  # iGPU Arc (Meteor Lake)
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      vpl-gpu-rt
    ];
  };

  # Webcam IPU6 : c'est LE composant qu'il faut valider en live, puisqu'il
  # ne fonctionne pas sans configuration dédiée.
  hardware.ipu6 = {
    enable = true;
    platform = "ipu6epmtl";
  };

  services.hardware.bolt.enable = true;
  hardware.sensor.iio.enable = true;

  # Le pilote NVIDIA n'est PAS inclus : il alourdirait encore l'image et
  # empêcherait la session de démarrer quand l'eGPU est débranché. Le live
  # sert à vérifier que la 4070 apparaît bien sur le bus PCIe (lspci,
  # boltctl) ; le rendu dessus se testera après installation, via la
  # spécialisation « egpu ».

  #############################################################################
  # Outils d'installation et de diagnostic
  #############################################################################

  environment.systemPackages = with pkgs; [
    pciutils usbutils lshw dmidecode lm_sensors
    hw-probe libinput alsa-utils iw powertop
    gptfdisk parted gparted ntfs3g
    git vim wget curl
    evtest        # test brut des événements d'entrée (tactile, stylet)

    # Les deux scripts du dépôt deviennent des commandes du live :
    #   test-hardware     diagnostic complet, à passer AVANT d'installer
    #   install-matebook  installation automatisée de nixosConfigurations.matebook
    (writeShellScriptBin "test-hardware" (builtins.readFile ./test-hardware.sh))
    (writeShellScriptBin "install-matebook" (builtins.readFile ./install.sh))

    # Dépendances d'install.sh. Le profil d'installation en fournit déjà la
    # plupart, mais les lister ici évite un échec en plein partitionnement.
    dosfstools     # mkfs.fat
    e2fsprogs      # mkfs.ext4
    util-linux     # lsblk, findmnt, mountpoint, mkswap, wipefs
    rsync          # copie du flake en excluant le lien « result »
    nixos-install-tools
  ];

  # Ta config embarquée : si le réseau lâche pendant l'install, les fichiers
  # sont dans /etc/nixos-flake.
  environment.etc."nixos-flake".source = ./.;

  isoImage = {
    isoName = lib.mkForce "nixos-matebook-live.iso";
    volumeID = lib.mkForce "NIXOS_MBGT";
    makeEfiBootable = true;
    makeUsbBootable = true;
    # squashfs : zstd décompresse bien plus vite que xz au boot, ce qui
    # compte pour une image de cette taille.
    squashfsCompression = "zstd -Xcompression-level 15";
  };

  #############################################################################
  # Allègement — décommente si l'image est trop grosse
  #############################################################################
  # Ces deux-là ne testent aucun matériel et pèsent plusieurs Go :
  #
  # programs.steam.enable = lib.mkForce false;
  # home-manager.users.${config.my.username}.programs.spicetify.enable =
  #   lib.mkForce false;

  system.stateVersion = "25.11";
}
