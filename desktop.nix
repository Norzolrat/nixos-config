# Environnement de bureau : niri + noctalia (Quickshell) + apps
{ config, pkgs, lib, inputs, ... }:

let
  username = config.my.username;
in
{
  #############################################################################
  # niri
  #############################################################################

  programs.niri = {
    enable = true;
    # niri-stable suit les releases, niri-unstable le master.
    # On passe par l'input plutôt que par pkgs.niri-stable : l'overlay du
    # flake n'est pas garanti d'être appliqué selon l'ordre de chargement.
    package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-stable;
  };

  # niri ne fournit pas de portal : il faut gnome (screencast) + gtk (fichiers)
  xdg.portal = {
    enable = true;
    extraPortals = with pkgs; [
      xdg-desktop-portal-gnome
      xdg-desktop-portal-gtk
    ];
    config.niri = {
      default = [ "gnome" "gtk" ];
      "org.freedesktop.impl.portal.FileChooser" = [ "gtk" ];
    };
  };

  # Greeter assorti au thème Noctalia. Le « Sync Now » (Settings → Security →
  # Noctalia Greeter) documenté par Noctalia ne fonctionne qu'avec Noctalia
  # v5 — on est sur legacy-v4, donc ce bouton ne fait rien chez nous. À la
  # place : scheme "Synced" + palette manuelle (toujours prioritaire sur la
  # sync de toute façon), recopiée depuis ~/.config/noctalia/colors.json —
  # donc un instantané, PAS un lien live : si tu changes de fond d'écran ou
  # de palette dans Noctalia, il faudra remettre ces valeurs à jour ici.
  #
  # Le module active services.greetd et accounts-daemon via mkDefault, donc
  # ne PAS définir services.greetd ici en dur, ça écraserait ces défauts.
  programs.noctalia-greeter = {
    enable = true;
    settings = {
      cursor = {
        theme = "Bibata-Modern-Classic";
        size = 24;
        path = "${pkgs.bibata-cursors}/share/icons";
      };
      appearance = {
        scheme = "Synced";
        theme_mode = "dark";
        font_family = "DejaVu Sans Mono";
        palette = {
          primary = "#e0c0ac";
          on_primary = "#402c1e";
          secondary = "#d4c3b9";
          on_secondary = "#392e27";
          tertiary = "#cac8aa";
          on_tertiary = "#32311c";
          error = "#ffb4ab";
          on_error = "#690005";
          surface = "#151311";
          on_surface = "#e8e1de";
          surface_variant = "#221f1d";
          on_surface_variant = "#d2c4bb";
          outline = "#4f453e";
          shadow = "#000000";
          hover = "#cac8aa";
          on_hover = "#32311c";
        };
        wallpaper = {
          # Fond réellement affiché sur l'écran interne (eDP-1), vérifié dans
          # ~/.cache/noctalia/wallpapers.json — pas une supposition.
          path = "${config.users.users.${username}.home}/Pictures/Wallpapers/default.jpg";
          fill_mode = "crop";
        };
      };
    };
  };

  #############################################################################
  # IA locale — Ollama, pour le plugin Noctalia « Assistant Panel »
  #############################################################################
  # ollama-vulkan accélère via l'iGPU Intel Arc (Meteor Lake) plutôt que le
  # CPU seul. Écoute uniquement en local (127.0.0.1:11434, valeur par défaut
  # du module) — pas besoin d'ouvrir le pare-feu.
  #
  # Le plugin « Assistant Panel » vient du store de plugins Noctalia, pas de
  # Nix : installe-le toi-même (bouton ⬇ dans les réglages Noctalia), puis
  # configure-le avec :
  #   AI Provider : OpenAI Compatible
  #   Local Mode  : ON
  #   Base URL    : http://localhost:11434/v1/chat/completions
  #   Model       : qwen2.5:7b (déjà téléchargé automatiquement ci-dessous)
  #   API Key     : laisser vide
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan;
    loadModels = [ "qwen2.5:7b" ];
  };

  #############################################################################
  # Shell
  #############################################################################
  # L'activation système est obligatoire : c'est elle qui inscrit fish dans
  # /etc/shells et installe les complétions générées depuis les paquets Nix.
  # Sans elle, greetd refusera fish comme shell de login.

  programs.fish.enable = true;
  users.users.${username} = {
    isNormalUser = true;
    shell = pkgs.fish;
    extraGroups = [ "wheel" "networkmanager" "video" "input" "docker" "libvirtd" ];
  };

  security.polkit.enable = true;
  services.gnome.gnome-keyring.enable = true;
  security.pam.services.greetd.enableGnomeKeyring = true;

  #############################################################################
  # Noctalia — dépendances système obligatoires
  #############################################################################
  # Sans ces quatre services, les widgets wifi / bluetooth / batterie /
  # profil de puissance de Noctalia restent vides.

  networking.networkmanager.enable = true;
  # Plugin OpenVPN pour NetworkManager : importe/gère des profils .ovpn
  # directement depuis le panneau réseau de Noctalia, pas besoin de config
  # déclarative séparée (services.openvpn.servers) tant qu'aucun profil
  # précis n'est fourni.
  networking.networkmanager.plugins = [ pkgs.networkmanager-openvpn ];
  hardware.bluetooth.enable = true;
  services.upower.enable = true;
  # services.power-profiles-daemon est déjà activé dans matebook-gt.nix

  environment.systemPackages = [
    inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default
    inputs.zen-browser.packages.${pkgs.stdenv.hostPlatform.system}.default

    # XWayland pour niri. SANS LUI, aucune application X11 ne démarre :
    # Steam, une partie des jeux, certains Electron et Java. niri le lance
    # automatiquement dès qu'il le trouve dans le PATH.
    inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.xwayland-satellite-stable
  ] ++ (with pkgs; [
    # utilitaires attendus par Noctalia
    wl-clipboard
    cliphist
    grim
    slurp
    wlsunset
    brightnessctl

    # VSCode. La variante FHS évite de casser les extensions qui embarquent
    # leurs propres binaires (serveurs LSP, debuggers, formatters).
    vscode-fhs

    alacritty  # terminalCommand par défaut de Noctalia

    # Outils repris de ta config Hyprland
    fuzzel            # repli du lanceur Noctalia
    tesseract         # OCR (Mod+Shift+T)
    hyprpicker        # pipette (Mod+Shift+C) — fonctionne hors Hyprland
    wf-recorder       # enregistrement d'écran
    easyeffects       # lancé au démarrage
    pavucontrol
    nautilus
    btop
    jq                # utilisé par tes scripts
    libnotify         # notify-send
    bibata-cursors    # HYPR: Bibata-Modern-Classic
    openvpn           # client CLI, pour lancer un .ovpn hors NetworkManager
  ]);

  # HYPR: exec-once = fcitx5
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5.addons = with pkgs; [ fcitx5-gtk ];
  };

  # HYPR: exec-once = hypridle — hypridle est spécifique à Hyprland.
  # L'équivalent générique compatible niri est swayidle, qui se configure
  # côté home-manager (programs.noctalia-shell gère déjà lockOnSuspend).
  # À ajouter plus tard, une fois tes délais de veille choisis.

  # Le verrouillage Noctalia détecte seul /etc/pam.d/login, généré par NixOS.
  # Décommente uniquement si tu veux une pile PAM dédiée :
  #   security.pam.services.noctalia = {};
  #   environment.sessionVariables.NOCTALIA_PAM_SERVICE = "noctalia";
  #
  # N'active PAS services.fprintd : le capteur Goodix GXFP5130 de cette
  # machine n'a aucun pilote Linux, et Noctalia attendrait un capteur absent.

  #############################################################################
  # Steam
  #############################################################################

  programs.steam = {
    enable = true;
    gamescopeSession.enable = true;   # utile pour cadrer sur l'écran 3:2
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;
  };
  programs.gamemode.enable = true;

  # hardware.graphics.enable32Bit est déjà activé dans matebook-gt.nix,
  # c'est indispensable pour Proton.

  #############################################################################
  # Wayland — variables d'environnement
  #############################################################################

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";           # VSCode et tout Electron en Wayland natif
    MOZ_ENABLE_WAYLAND = "1";       # Zen (base Firefox)
    QT_QPA_PLATFORM = "wayland";
    XDG_CURRENT_DESKTOP = "niri";
  };

  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    inter
    noto-fonts
    noto-fonts-color-emoji
  ];

  #############################################################################
  # Config utilisateur (home-manager)
  #############################################################################

  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.extraSpecialArgs = { inherit inputs; };

  home-manager.users.${username} = { config, lib, pkgs, ... }:
    let
      # Seed initial de ~/.config/noctalia/settings.json : Noctalia gère ce
      # fichier lui-même à l'exécution (couleurs, layout, etc.). Si on le
      # laissait sous home-manager (xdg.configFile), il serait re-symlinké
      # vers le store — donc écrasé — à CHAQUE boot, puisque
      # home-manager-<user>.service se relance à chaque démarrage, pas
      # seulement à `nixos-rebuild switch`. On ne fournit donc ces valeurs
      # que comme point de départ, copiées une seule fois (cf. activation
      # script plus bas) si le fichier n'existe pas encore.
      noctaliaSettingsSeed = pkgs.writeText "noctalia-settings-seed.json" (builtins.toJSON {
        general = {
          # Pas de capteur d'empreintes exploitable sur cette machine.
          allowPasswordWithFprintd = false;
          lockOnSuspend = true;
        };
        appLauncher.terminalCommand = "alacritty -e";
        templates = {
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
        wallpaper = {
          enabled = true;
          directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
          fillMode = "crop";
          setWallpaperOnAllMonitors = true;
        };
      });
    in
    {
    home.stateVersion = "25.11";

    imports = [
      inputs.noctalia.homeModules.default
    ];

    programs.noctalia-shell.enable = true;

    home.activation.noctaliaSettingsSeed = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      target="${config.home.homeDirectory}/.config/noctalia/settings.json"
      if [ ! -e "$target" ]; then
        install -Dm644 ${noctaliaSettingsSeed} "$target"
      fi
    '';

    ###########################################################################
    # fish
    ###########################################################################

    programs.fish = {
      enable = true;
      shellAliases = {
        rebuild = "sudo nixos-rebuild switch --flake ~/nixos#matebook";
        rebuild-test = "sudo nixos-rebuild test --flake ~/nixos#matebook";
      };
      # fish n'est pas POSIX : nix-shell / nix develop repassent par bash et
      # tu perds ton shell dans les sous-environnements. any-nix-shell corrige.
      interactiveShellInit = ''
        set -g fish_greeting
        any-nix-shell fish --info-right | source
      '';
    };

    home.packages = [ pkgs.any-nix-shell ];

    ###########################################################################
    # Alacritty
    ###########################################################################
    # Même motif que kitty : Nix gère le fichier principal, Noctalia écrit
    # noctalia.toml à côté et on l'importe. Ne jamais laisser home-manager
    # gérer noctalia.toml lui-même.

    programs.alacritty = {
      enable = true;
      settings = {
        general.import = [ "~/.config/alacritty/noctalia.toml" ];
        window = {
          padding = { x = 10; y = 10; };
          opacity = 0.95;
          decorations = "none";   # niri dessine ses propres bordures
        };
        font = {
          normal.family = "JetBrainsMono Nerd Font";
          size = 11;
        };
        terminal.shell.program = "${pkgs.fish}/bin/fish";
      };
    };

    ###########################################################################
    # Fonds d'écran
    ###########################################################################
    # Chaque image est un symlink individuel vers le store : le RÉPERTOIRE
    # reste un vrai dossier inscriptible, donc tu peux continuer à y déposer
    # de nouvelles images à la main. Si on gérait le dossier entier avec
    # home.file, il deviendrait un symlink en lecture seule et le panneau
    # Noctalia ne pourrait plus rien y ajouter.

    home.file."Pictures/Wallpapers/default.png".source = ./wallpapers/default.png;
    home.file."Pictures/Wallpapers/default.jpg".source = ./wallpapers/default.jpg;

    # Fond par défaut du shell, à l'emplacement où Noctalia le cherche.
    home.file.".config/wallpapers/default.png".source = ./wallpapers/default.png;

    # Config niri en KDL brut plutôt qu'en attrsets Nix : ta config est
    # trop volumineuse pour être traduite sans erreurs, et le KDL se
    # débogue directement avec la documentation niri.
    programs.niri.config = builtins.readFile ./niri-config.kdl;
  };
}
