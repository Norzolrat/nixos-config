# Applications et intégration du thème Noctalia
{ config, pkgs, lib, inputs, ... }:

let
  username = config.my.username;
in
{
  environment.systemPackages = with pkgs; [
    # Bureautique et média — pas de template Noctalia pour ceux-là
    onlyoffice-desktopeditors
    vlc

    # Discord : vesktop embarque Vencord, pas besoin de patcher discord.
    vesktop

    # Cohérence GTK/Qt, nécessaire pour que le template Qt s'applique à VLC
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    adwaita-icon-theme

    vim
    codex
    claude-code
    bitwarden-desktop
    bitwarden-cli
    git
  ];

  # Spotify est unfree ; allowUnfree est déjà posé dans matebook-gt.nix.

  home-manager.users.${username} = { config, ... }: {

    ###########################################################################
    # Spotify + Spicetify
    ###########################################################################
    # Spicetify patche Spotify en place, ce qui est impossible dans le store
    # Nix en lecture seule. spicetify-nix reconstruit un paquet pré-patché,
    # c'est la seule voie viable ici. N'installe PAS pkgs.spotify en plus :
    # tu aurais deux Spotify concurrents.

    imports = [ inputs.spicetify-nix.homeManagerModules.default ];

    programs.spicetify =
      let
        spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
      in
      {
        enable = true;
        # Comfy est le thème attendu par le template Noctalia.
        # Vérifie le nom exact de l'attribut : `nix repl` puis
        #   :lf github:Gerg-L/spicetify-nix
        theme = spicePkgs.themes.comfy;
        enabledExtensions = with spicePkgs.extensions; [
          shuffle
          keyboardShortcut
        ];
      };

    # Réglages Noctalia (templates, wallpaper, etc.) : plus déclarés ici, cf.
    # le seed dans desktop.nix (Noctalia gère son settings.json lui-même après
    # le premier démarrage, cf. le commentaire à côté de home.activation).

    ###########################################################################
    # Thème GTK / Qt
    ###########################################################################
    # On pose une base cohérente ; Noctalia écrase les couleurs par-dessus.

    gtk = {
      enable = true;
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
    };

    qt = {
      enable = true;
      platformTheme.name = "qtct";   # laisse Noctalia piloter les couleurs
    };

    # VLC : application Qt, il suivra le thème qt6ct.
    # Sur niri, forcer Wayland natif évite le tearing sur l'écran 120Hz :
    home.file.".config/vlc/vlcrc".text = lib.mkDefault ''
      [qt]
      qt-fs-screen=-1
    '';
  };
}
