{ pkgs, ... }:

let
  dots = ./dots;
in
{
  home.username = "normi";
  home.homeDirectory = "/home/normi";
  home.stateVersion = "25.05";

  fonts.fontconfig.enable = true;

  # ——— User packages ———
  home.packages = with pkgs; [
    # applets / outils tray
    networkmanagerapplet networkmanager bluez blueman brightnessctl
    libnotify pavucontrol pamixer

    # polices pour icônes/logos
    font-awesome
    noto-fonts
    noto-fonts-emoji
    nerd-fonts.jetbrains-mono
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
    material-design-icons

    # thèmes d’icônes/cursor (au choix)
    papirus-icon-theme
    bibata-cursors
    gtklock

    # outils utiles :
    bitwarden-cli
    bitwarden-desktop
    vscode
    discord
    dmidecode
    steam
    obs-studio
    thunderbird
    onlyoffice-desktopeditors
    virt-manager
    # zen-browser
  ];

  # ——— GTK / Qt theme ———
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";       # thème sombre par défaut
      package = pkgs.gnome-themes-extra;
    };
    iconTheme = {
      name = "Papirus-Dark";       # variante sombre de Papirus
      package = pkgs.papirus-icon-theme;
    };
  };

  qt = {
    enable = true;
    platformTheme.name = "qtct";
    style = {
      name = "Adwaita-dark";
      package = pkgs.adwaita-qt;
    };
  };
  
  home.sessionVariables = {
    GTK_THEME = "Adwaita-dark";
    QT_STYLE_OVERRIDE = "Adwaita-dark";
    XCURSOR_THEME = "Bibata-Modern-Ice";
    XCURSOR_SIZE = "24";
  };

  programs.zsh.enable = true;
  programs.git = {
    enable = true;
    userName  = "Normi";
    userEmail = "normann@magnaloca.fr";
  };

  # ——— Dotfiles ———
  home.file.".config/hypr" = {
    source = dots + "/hypr";
    recursive = true;
    force = true;
  };
  
  home.file.".config/alacritty" = {
    source = dots + "/alacritty";
    recursive = true;
    force = true;
  };
  
  home.file.".config/gtklock" = {
    source = dots + "/gtklock";
    recursive = true;
    force = true;
  };
  
  home.file.".config/wallpapers" = {
    source = dots + "/wallpapers";
    recursive = true;
    force = true;
  };

  programs.kitty.enable = true;
  programs.alacritty.enable = true;
}

