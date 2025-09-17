{ config, pkgs, noctalia, ... }:

{
  networking.hostName = "Veronica";
  networking.networkmanager.enable = true;

  time.timeZone = "Europe/Paris";

  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_IDENTIFICATION = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  ################
  # Bootloader   #
  ################
  boot = {
    loader = {
      timeout = 2;
      efi.canTouchEfiVariables = true;
      systemd-boot = {
        enable = true;
        consoleMode = "max";
      };
    };

    plymouth.enable = true;
    plymouth.theme = "spinner";
    initrd.verbose = false;
    kernelParams = [ "quiet" "splash" ];

    # Module loopback vidéo pour compat applis
    extraModulePackages = [ config.boot.kernelPackages.v4l2loopback ];
    kernelModules = [ "v4l2loopback" ];

    # Reste sur un noyau récent (tes modules IPU6 existent déjà en 6.16)
    kernelPackages = pkgs.linuxPackages_latest;
  };

  ################
  # Matériel     #
  ################
  hardware.cpu.intel.updateMicrocode = true;
  hardware.enableRedistributableFirmware = true;
  services.fwupd.enable = true;
  services.upower.enable = true;

  # Pile graphique moderne + VA-API Intel
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
    extraPackages = with pkgs; [
      intel-media-driver
      libva-utils
      mesa
      libva
      vaapiVdpau
      vulkan-loader
    ];
    extraPackages32 = with pkgs.pkgsi686Linux; [
      mesa
      vulkan-loader
    ];
  };

  hardware.steam-hardware.enable = true;

  # === Caméra IPU6 (MateBook GT / Meteor Lake) ===
  hardware.ipu6.enable = true;
  hardware.ipu6.platform = "ipu6epmtl";

  # Firmware + HAL + plugin GStreamer (non-libre requis)
  nixpkgs.config.allowUnfree = true;

  # Certains firmwares doivent être embarqués dans l’initrd
  hardware.firmware = with pkgs; [
    ipu6-camera-bins-unstable  # firmwares/libraries IPU6
    ivsc-firmware-unstable     # firmware Intel VSC (souvent requis)
  ];

  # Paquets userspace nécessaires + outils de test
  environment.systemPackages = with pkgs; [
    # basics
    bluez vim zsh git curl alacritty firefox nautilus
    qt6.qtdeclarative qt6.qt5compat qt6.qtsvg
    noctalia.packages.${pkgs.system}.default

    # helpers
    brightnessctl ddcutil libnotify wl-clipboard wlsunset grim slurp
    pavucontrol pamixer inter roboto

    # IPU6 userspace
    ipu6epmtl-camera-hal-unstable
    gst_all_1.icamerasrc-ipu6epmtl
    v4l2-relayd
    v4l-utils
    ffmpeg
    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
    gst_all_1.gst-plugins-good
    gst_all_1.gst-plugins-bad
  ];

  # Exposer la caméra via un device v4l2 « propre » pour les applis
  services.v4l2-relayd.instances.cam0 = {
    cardLabel = "IPU6 Camera";
    # pipeline simple ; ajuste si besoin (résolution/fps)
    input.pipeline = "icamerasrc ! video/x-raw,format=NV12,framerate=30/1 ! videoconvert";
    extraPackages = [ pkgs.gst_all_1.icamerasrc-ipu6epmtl ];
  };

  ################
  # Bureau       #
  ################
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.wayland = true;
  services.displayManager.defaultSession = "hyprland";

  # Hyprland
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  # Portals (Wayland/Hyprland : partages d’écran, fichiers, etc.)
  xdg.portal.enable = true;
  xdg.portal.extraPortals = [
    pkgs.xdg-desktop-portal-hyprland
    pkgs.xdg-desktop-portal-gtk
  ];

  environment.etc."gdm/backgrounds/default.png".source =
    ../../users/normi/dots/wallpapers/default.png;

  services.displayManager.gdm.settings = {
    "org.gnome.desktop.background" = {
      picture-uri = "file:///home/normi/.config/wallpapers/default.png";
      picture-uri-dark = "file:///home/normi/.config/wallpapers/default.png";
      picture-options = "zoom";
      primary-color = "#1f1f1f";
    };
  };

  ################
  # Audio        #
  ################
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    jack.enable = true;
  };

  ################
  # Bluetooth    #
  ################
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  ################
  # Sécu / divers#
  ################
  services.fprintd.enable = true;

  ################
  # Virtualisation
  ################
  virtualisation.docker.enable = true;
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      swtpm.enable = true;
    };
  };

  boot.extraModprobeConfig = ''
    options kvm_intel nested=1
    options kvm_intel emulate_invalid_guest_state=0
    options kvm ignore_msrs=1
  '';

  programs.dconf.enable = true;

  ################
  # Utilisateur  #
  ################
  programs.fish.enable = true;
  users.users.normi = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Normi";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" ];
  };

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Variables d'env
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };

  system.stateVersion = "25.05";
}
