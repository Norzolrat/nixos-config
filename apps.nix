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

    ###########################################################################
    # Templates Noctalia
    ###########################################################################
    # Noctalia écrit ces fichiers de thème À CHAQUE changement de couleur.
    # Ne laisse JAMAIS home-manager gérer les chemins de sortie ci-dessous :
    # un symlink read-only vers le store fait échouer l'écriture en silence.

    programs.noctalia-shell.settings.templates = {
      enableUserTemplates = false;   # true seulement si tu ajoutes les tiens
      activeTemplates = [
        { id = "alacritty"; active = true; }
        { id = "spotify"; active = true; }
        { id = "discord"; active = true; }
        { id = "vscode";  active = true; }
        { id = "zen";     active = true; }
        { id = "steam";   active = true; }
        { id = "gtk";     active = true; }
        { id = "qt";      active = true; }
      ];
    };

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
