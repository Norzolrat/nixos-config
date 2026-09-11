# Applications et intégration du thème Noctalia
{ config, pkgs, lib, inputs, ... }:

let
  username = config.my.username;

  ###########################################################################
  # Type MIME des conteneurs chiffrés ZED! (PRIM'X)
  ###########################################################################
  # ZEDFREE tourne dans un conteneur Distrobox Ubuntu (cf. la section
  # Conteneurs de system.nix) et son .desktop exporté porte bien une ligne
  # MimeType=application/zed. Ça ne suffit pas : le .deb installe sa
  # définition de type dans le /usr/share/mime DU CONTENEUR, que l'hôte ne lit
  # jamais. Sans le doublon ci-dessous, l'hôte ignore qu'un *.zed est autre
  # chose qu'un binaire quelconque, xdg-mime répond application/octet-stream,
  # et Nautilus ne propose jamais ZEDFREE — même avec l'appli parfaitement
  # exportée.
  #
  # xdg.mime.enable est à true par défaut sur NixOS : tout paquet de
  # environment.systemPackages qui expose share/mime/packages/*.xml est agrégé
  # dans /run/current-system/sw/share/mime à l'activation, update-mime-database
  # compris. Rien d'autre à déclencher.
  #
  # Le contenu est recopié de /usr/share/mime/packages/zed.xml livré par
  # ZEDFREE-2025.1.14.Ubuntu24.04.amd64.deb, pas déduit de l'extension. Deux
  # écarts volontaires avec l'original :
  #   - l'espace de noms est écrit en défaut plutôt qu'en préfixe ns0:, les
  #     deux sont équivalents pour update-mime-database ;
  #   - <alias type="application/zed"/> est supprimé : l'original se déclare
  #     alias de lui-même, ce qui est un artefact de génération sans effet.
  # Le type est bien « application/zed » et PAS « application/x-zed » : c'est
  # une exception à la convention x- pour un type non enregistré à l'IANA.
  zedMimeType = pkgs.writeTextDir "share/mime/packages/zed-primx.xml" ''
    <?xml version="1.0" encoding="UTF-8"?>
    <mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
      <mime-type type="application/zed">
        <comment>ZED! container</comment>
        <comment xml:lang="fr">Conteneur chiffré ZED!</comment>
        <glob pattern="*.zed"/>
        <generic-icon name="zed-file"/>
      </mime-type>
    </mime-info>
  '';
in
{
  environment.systemPackages = with pkgs; [
    # Bureautique et média — pas de template Noctalia pour ceux-là
    onlyoffice-desktopeditors
    vlc
    gimp

    # Okular : lecteur PDF/DjVu de KDE. On prend la build Qt6 (kdePackages)
    # et pas libsForQt5 : les couleurs sont pilotées par qt6ct ici, une build
    # Qt5 suivrait qt5ct et tirerait une seconde pile de dépendances.
    kdePackages.okular

    # Discord : vesktop embarque Vencord, pas besoin de patcher discord.
    vesktop

    # Cohérence GTK/Qt, nécessaire pour que le template Qt s'applique à VLC
    libsForQt5.qt5ct
    qt6Packages.qt6ct
    adwaita-icon-theme

    thunderbird
    vim
    codex
    claude-code
    bitwarden-desktop
    bitwarden-cli
    git
    fastfetch
    affine

    # Déclaration du type *.zed pour l'hôte (cf. le let ci-dessus). Ce n'est
    # pas un paquet pkgs mais une liaison du let : elle a priorité sur le
    # « with pkgs » de cette liste.
    zedMimeType

    # update-desktop-database : absent du système jusqu'ici (xdg-mime et
    # xdg-open, eux, arrivent déjà par une dépendance transitive du portail).
    # Il est nécessaire après « distrobox-export », pour régénérer le
    # mimeinfo.cache de ~/.local/share/applications. Sans ce cache, une appli
    # exportée reste absente de la liste « Ouvrir avec » de Nautilus, même
    # quand son .desktop déclare bien le MimeType.
    desktop-file-utils
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

      # adw-gtk3 et pas Adwaita : le template GTK de Noctalia n'écrit que des
      # variables libadwaita (window_bg_color, view_bg_color, …) dans
      # ~/.config/gtk-3.0/noctalia.css. Le thème Adwaita GTK3 d'origine les
      # ignore (il utilise theme_bg_color, etc.), donc TOUT ce qui est GTK3
      # restait en clair : les dialogues « Ouvrir » / « Enregistrer sous »
      # servis par xdg-desktop-portal-gtk, et le sélecteur de fichiers de
      # Zen/Firefox. Nautilus, lui, est GTK4/libadwaita, d'où son fond sombre
      # correct quand on l'ouvre directement. adw-gtk3 est le portage GTK3 de
      # libadwaita : il consomme les mêmes variables, les deux se rejoignent.
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };

      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };

      # adw-gtk3 ne fournit rien pour GTK4 : on ne lui impose pas de nom de
      # thème (c'est aussi le nouveau défaut de home-manager, ça enlève le
      # warning de dépréciation sur gtk.gtk4.theme).
      gtk4.theme = null;

      # Le hook GTK de Noctalia (assets/templates/gtk/apply.sh) ne pose
      # gtk-theme que s'il TROUVE le thème, en cherchant dans ~/.themes,
      # $XDG_DATA_HOME/themes, /usr/share/themes et $XDG_DATA_DIRS/*/themes.
      # Sur NixOS le thème n'est que dans le profil, donc visible uniquement
      # via XDG_DATA_DIRS — or noctalia.service démarre avec
      # graphical-session.target, avant que la session n'ait forcément importé
      # cet environnement. Quand la course est perdue, le hook journalise
      # « Theme not found, skipping GTK theme set », ne pose que color-scheme,
      # et l'apparence part de travers au démarrage.
      #
      # Le lien ci-dessous place le thème dans ~/.themes, le tout premier
      # chemin testé par le script et le seul qui ne dépende d'aucune variable
      # d'environnement. Voir [[gtk-theme-depends-on-xdg-data-dirs]].

      # Interrupteur natif GTK3, pour les applis qui choisissent leur variante
      # elles-mêmes plutôt que de suivre le nom du thème.
      gtk3.extraConfig.gtk-application-prefer-dark-theme = 1;
      gtk4.extraConfig.gtk-application-prefer-dark-theme = 1;
    };

    qt = {
      enable = true;
      platformTheme.name = "qtct";   # laisse Noctalia piloter les couleurs
    };

    # Les deux variantes, pour que le hook trouve aussi bien adw-gtk3 (clair)
    # que adw-gtk3-dark quand tu bascules avec Mod+Alt+D.
    home.file.".themes/adw-gtk3".source = "${pkgs.adw-gtk3}/share/themes/adw-gtk3";
    home.file.".themes/adw-gtk3-dark".source = "${pkgs.adw-gtk3}/share/themes/adw-gtk3-dark";

    # VLC : application Qt, il suivra le thème qt6ct.
    # Sur niri, forcer Wayland natif évite le tearing sur l'écran 120Hz :
    home.file.".config/vlc/vlcrc".text = lib.mkDefault ''
      [qt]
      qt-fs-screen=-1
    '';
  };
}
