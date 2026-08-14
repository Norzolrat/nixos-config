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
    #
    # niri-unstable et pas -stable : le pin `niri-stable` de niri-flake est
    # resté sur 25.08 (août 2025), donc tout ce que la doc marque
    # « Since: 25.11 » ou « Since: 26.04 » est inaccessible avec. Contrepartie :
    # chaque `nix flake update` déplace le compositeur d'un cran de master.
    # Le cache niri.cachix.org (cf. flake.nix) évite de recompiler.
    package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
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

  # Greeter assorti au thème Noctalia.
  #
  # Ce bloc ne déclare QUE ce qui doit rester figé. Tout ce qui touche à
  # l'apparence — palette et fond d'écran — est volontairement absent, parce
  # que le greeter fusionne deux fichiers et que le déclaratif l'emporte :
  #   /var/lib/noctalia-greeter/greeter.toml  ← ce bloc, prioritaire
  #   /var/lib/noctalia-greeter/sync.toml     ← écrit par la synchronisation
  # Déclarer une palette ici la figerait donc pour toujours, et c'est
  # exactement ce qui faisait dériver le greeter en v4 (couleurs d'un autre
  # jour, fond d'écran pointant dans /home/normi que l'utilisateur `greeter`
  # ne peut de toute façon pas lire, ce home étant en 0700).
  #
  # La synchronisation se déclenche avec :  noctalia msg greeter-sync
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
        theme_mode = "dark";
        font_family = "DejaVu Sans Mono";
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
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;

    # Sans bloc `settings`, aucun /etc/bluetooth/main.conf n'est généré et
    # bluez tourne sur ses défauts, qui sont volontairement conservateurs.
    settings = {
      General = {
        # Expose le niveau de batterie des périphériques (casques, souris)
        # sur DBus via l'interface Battery Provider. C'est expérimental côté
        # bluez, donc désactivé par défaut : sans ça le widget Bluetooth de
        # Noctalia n'affiche jamais de pourcentage de batterie.
        Experimental = true;

        # Autorise un casque à exposer A2DP (musique) et HFP (micro) en même
        # temps. Par défaut bluez n'en garde qu'un, ce qui force un
        # aller-retour de profil — et une coupure d'audio — dès qu'une visio
        # réclame le micro.
        MultiProfile = "multiple";

        # Le contrôleur reste en page scan : un périphérique déjà appairé se
        # reconnecte en une poignée de secondes au lieu d'attendre le
        # prochain cycle. Coût : quelques mW en veille.
        FastConnectable = true;
      };

      Policy = {
        # Réappairage automatique après une coupure ou une sortie de veille.
        # Les intervalles sont en secondes, un par tentative.
        AutoEnable = true;
        ReconnectAttempts = 7;
        ReconnectIntervals = "1,2,4,8,16,32,64";
      };
    };
  };
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

    # Sans ça le module pose GTK_IM_MODULE=fcitx et QT_IM_MODULE=fcitx, qui
    # forcent les applis à passer par le pont X11 de fcitx alors que niri
    # expose déjà le protocole Wayland text-input-v3. Les deux chemins se
    # marchent dessus : c'est ce que fcitx signale au démarrage. En mode
    # waylandFrontend, les variables ne sont plus posées et les applis
    # Wayland parlent directement au frontend natif.
    fcitx5.waylandFrontend = true;
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
    {
    home.stateVersion = "25.11";

    imports = [
      inputs.noctalia.homeModules.default
    ];

    ###########################################################################
    # Noctalia v5
    ###########################################################################
    # La v5 lit ~/.config/noctalia/config.toml (TOML, rechargé à chaud via
    # inotify), là où la v4 gérait un settings.json qu'elle réécrivait
    # elle-même — d'où le seed recopié une seule fois qui existait ici avant.
    # Ce n'est plus nécessaire : `settings` est rendu en TOML par le module,
    # et validé au build (validateConfig, activé par défaut). Les réglages
    # posés ici restent modifiables à l'exécution depuis le menu Settings.
    programs.noctalia = {
      enable = true;

      # Service utilisateur systemd plutôt qu'un spawn-at-startup dans niri :
      # le shell est ainsi relancé proprement et journalisé (journalctl
      # --user -u noctalia).
      systemd.enable = true;

      settings = {
        theme = {
          mode = "dark";
          # La palette est dérivée du fond d'écran : c'est l'équivalent v5 du
          # scheme « Synced » de la v4, et c'est ce que `greeter-sync` recopie
          # ensuite vers l'écran de connexion.
          source = "wallpaper";

          templates = {
            enable_builtin_templates = true;
            # Identifiants réels, relevés avec `noctalia theme --list-templates`.
            # La v4 parlait d'un template « gtk » unique, la v5 sépare gtk3 et
            # gtk4. Les templates spotify, discord, vscode, zen et steam ne
            # sont pas fournis d'origine : ils viennent du dépôt communautaire,
            # à ajouter dans community_ids une fois leurs identifiants relevés
            # avec `noctalia theme --list-templates` après un premier lancement.
            builtin_ids = [ "gtk3" "gtk4" "qt" "alacritty" "btop" ];
            enable_community_templates = true;
          };
        };

        wallpaper = {
          enabled = true;
          directory = "${config.home.homeDirectory}/Pictures/Wallpapers";
          fill_mode = "crop";
        };

        # Barre reprise de l'ancien settings.json de la v4. La v5 nomme les
        # sections start/center/end au lieu de left/center/right, et les
        # widgets en minuscules : Workspace → workspaces, SystemMonitor →
        # sysmon, NotificationHistory → notifications, ActiveWindow →
        # active_window (le seul avec un tiret bas, les autres sont en tirets).
        # Les identifiants sont ceux de la fabrique de widgets du binaire v5,
        # pas une transposition à vue.
        #
        # privacy était un plugin en v4 (plugin:privacy-indicator) ; c'est un
        # widget intégré en v5, donc plus rien à installer pour l'avoir.
        # Les trois autres widgets de plugins (calculator, mini-docker,
        # keybind-cheatsheet) sont à réinsérer ici une fois les plugins
        # réinstallés, sous l'identifiant que donne `noctalia msg plugins list`.
        bar.main = {
          position = "top";
          start = [ "sysmon" "active_window" ];
          center = [ "workspaces" "privacy" ];
          end = [
            "tray"
            "bluetooth"
            "network"
            "notifications"
            "battery"
            "volume"
            "brightness"
            "clock"
          ];
        };

        nightlight.enabled = true;

        # Délais repris tels quels de la v4 : écran éteint à 10 min,
        # verrouillage à 11 min, veille à 30 min. C'est Noctalia qui s'en
        # charge, il n'y a donc toujours pas de swayidle à installer.
        idle.behavior = {
          "screen-off" = {
            enabled = true;
            timeout = 600;
            action = "screen_off";
          };
          lock = {
            enabled = true;
            timeout = 660;
            action = "lock";
          };
        };
      };
    };

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
