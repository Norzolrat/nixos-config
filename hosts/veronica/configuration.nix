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

  # sudo systemctl reboot --boot-loader-menu=10s ==> take in the menu

  boot = {
    loader = {
      timeout = 2;
      efi.canTouchEfiVariables = true;

      systemd-boot = {
        enable = true;
        consoleMode = "max";
        # configurationLimit = 8;
      };
    };

    plymouth.enable = true;
    plymouth.theme = "spinner";
    initrd.verbose = false;
    # kernelParams = [ "quiet" "splash" "loglevel=3" "rd.systemd.show_status=auto" "rd.udev.log_level=3" ];
    kernelParams = [ "quiet" "splash" ];

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
    # Drivers Mesa (GL/Vulkan) en 64 et 32 bits
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

  # Caméra IPU6 (MateBook GT / Meteor Lake)
  # hardware.ipu6.enable = true;
  # hardware.ipu6.platform = "ipu6epmtl";
  boot.kernelPackages = pkgs.linuxPackages_latest;

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

  environment.etc."gdm/backgrounds/default.png".source =
    ../../users/normi/dots/wallpapers/default.png;

  services.displayManager.gdm.settings = {
    "org.gnome.desktop.background" = {
      picture-uri = "file:///home/normi/.config/wallpapers/default.png";
      # picture-uri = "file:///etc/gdm/backgrounds/default.png";
      # picture-uri-dark = "file:///etc/gdm/backgrounds/default.png";
      picture-uri-dark = "file:///home/normi/.config/wallpapers/default.png";
      picture-options = "zoom";
      primary-color = "#1f1f1f";
    };
  };


  # xdg.portal.enable = true;
  # xdg.portal.extraPortals = [
  #   pkgs.xdg-desktop-portal-hyprland
  #   pkgs.xdg-desktop-portal-gtk
  # ];

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
    # wireplumber.enable = true;
  };

  ################
  # Bluetooth    #
  ################
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
    # settings = {
    #   # tes réglages bluetooth ici
    # };
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
  programs.fish = {
    enable = true;
  };
  users.users.normi = {
    isNormalUser = true;
    shell = pkgs.fish;
    description = "Normi";
    extraGroups = [ "networkmanager" "wheel" "libvirtd" "kvm" "docker" ];
  };
  
  ################
  # Paquets base #
  ################
  nixpkgs.config.allowUnfree = true;

  environment.systemPackages = with pkgs; [
    # basics
    bluez vim zsh git curl alacritty firefox nautilus
    qt6.qtdeclarative qt6.qt5compat qt6.qtsvg
    noctalia.packages.${pkgs.system}.default
    # helpers
    brightnessctl ddcutil libnotify wl-clipboard wlsunset grim slurp
    pavucontrol pamixer inter roboto
  ];

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Variables d'env
  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
  };
  # environment.variables = {
  #   QT_STYLE_OVERRIDE = "kvantum";
  #   QT_QPA_PLATFORMTHEME = "qt6ct";
  #   XCURSOR_THEME = "Bibata-Modern-Ice";
  #   XCURSOR_SIZE = "24";
  # };

  system.stateVersion = "25.05";
}
