# Environnement de bureau : niri + noctalia + apps
{ config, pkgs, lib, inputs, ... }:

let
  username = config.my.username;
in
{
  imports = [ inputs.piri.nixosModules.piri ];

  #############################################################################
  # niri
  #############################################################################

  programs.niri = {
    enable = true;
    # niri-stable suit les releases, niri-unstable le master.
    # On passe par l'input plutôt que par pkgs.niri-stable : l'overlay du
    # flake n'est pas garanti d'être appliqué selon l'ordre de chargement.
    #
    # Retour sur niri-stable (25.08). Le passage à niri-unstable avait été
    # motivé par une question sur des « plugins » qui s'est finalement révélée
    # porter sur Noctalia, pas sur niri : aucune fonctionnalité postérieure à
    # 25.08 n'est utilisée ici. Stable évite qu'un `nix flake update` ne
    # déplace le compositeur d'un cran de master à chaque fois.
    #
    # À noter : ce choix n'a RIEN à voir avec la panne de l'écran tactile.
    # libinput ne reçoit aucun événement du contrôleur FTSC1000, donc le
    # problème est sous le compositeur — voir les erreurs I2C
    # « failed to get a report from device: -5 » au démarrage.
    package = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-stable;
  };

  # piri tourne en service utilisateur (démarré avec graphical-session.target)
  # et parle à niri par son IPC. Sa configuration est posée côté home-manager
  # dans ~/.config/niri/piri.toml, le chemin qu'il lit par défaut.
  services.piri.enable = true;

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

  #############################################################################
  # Montage automatique des périphériques amovibles
  #############################################################################
  # Trois briques distinctes, qu'on confond souvent parce que GNOME et KDE les
  # embarquent toutes les trois sans le dire. niri ne fournit rien : il faut
  # les poser à la main.
  #
  #   udisks2 — le démon D-Bus qui SAIT monter un périphérique bloc (clé USB,
  #             disque externe, carte SD) sous /run/media/$USER, sans sudo.
  #             Mais il ne monte rien de lui-même : il attend qu'on lui demande.
  #   udiskie — le client qui écoute udisks2 et déclenche le montage dès qu'un
  #             périphérique apparaît. C'est lui, l'automontage proprement dit.
  #             Il tourne en service utilisateur (voir home-manager plus bas).
  #   gvfs    — la couche FUSE de GTK, et la SEULE qui réponde au cas du
  #             téléphone : un Android en mode « transfert de fichiers »
  #             n'expose pas un périphérique bloc, mais du MTP — un protocole
  #             qui parle par-dessus USB. Aucun mount classique ne peut le
  #             monter et udisks2 ne le verra jamais ; seul le backend
  #             gvfs-mtp le présente à Nautilus.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # Règles udev de libmtp. Sans elles le noyau détecte bien le téléphone, mais
  # le nœud USB reste root:root : gvfs-mtp échoue silencieusement en
  # « permission denied » et rien n'apparaît dans Nautilus.
  services.udev.packages = [ pkgs.libmtp.out ];

  # Le pilote noyau ntfs3 lit le NTFS, mais udisks2 monte en écriture via le
  # helper mount.ntfs. Sans ce flag, un disque externe formaté sous Windows
  # se monte en lecture seule — ou refuse de se monter.
  boot.supportedFilesystems.ntfs = true;

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

        # Retire le logo Noctalia de l'écran de connexion.
        hide_logo = true;

        # Le sélecteur de thème, lui, n'est PAS masquable : aucune clé du
        # greeter ne le contrôle (vérifié sur la liste complète des clés de
        # greeter_config_io.cpp), il est disposé sans condition.
        # « Synced » neutralise au moins son effet : la valeur déclarée ici
        # l'emporte sur le dernier choix fait dans l'interface, donc un clic
        # accidentel ne survit pas au redémarrage. La palette continue de
        # venir de `noctalia msg greeter-sync`, rien n'est figé en dur.
        scheme = "Synced";
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

  # Micro des casques Bluetooth : rien à régler ici, c'est côté application.
  #
  # WirePlumber n'expose jamais le micro HFP directement : il publie un node
  # loopback (bluez_input.<adresse>) et ne bascule la carte de `a2dp-sink` vers
  # `headset-head-unit` que quand une application se branche dessus. Cette
  # détection ne traverse pas EasyEffects : elle suit les liens du graphe et
  # exige que chaque filtre porte `node.link-group`, ce que les nodes
  # EasyEffects (easyeffects_source, ee_sie_*) n'ont pas. Une appli qui capte
  # via « Easy Effects Source » n'atteint donc jamais le casque.
  #
  # Le remède est de sélectionner le casque comme micro DANS l'application
  # (pas « Easy Effects Source ») : la bascule se fait alors seule et le retour
  # en A2DP aussi. Corollaire : pas d'effets EasyEffects sur le micro BT, les
  # deux sont incompatibles.
  #
  # NE PAS poser bluetooth.autoswitch-to-headset-profile = false pour
  # contourner : essayé, ça supprime purement et simplement le micro du casque
  # de la liste des sources tant que la carte est en A2DP, sans rien résoudre.

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

  # Steam, Heroic et GameMode vivent dans ./gaming.nix, importé uniquement par
  # nixosConfigurations.matebook : ils pèsent plusieurs Go et ne testent aucun
  # matériel, donc ils restent hors de l'ISO live.

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
      #
      # Le garde command -q est là pour Distrobox : le conteneur monte ce
      # config.fish depuis le home partagé, mais any-nix-shell vit dans le
      # profil home-manager, absent du PATH côté conteneur. Sans le garde,
      # chaque shell ouvert dans le conteneur s'ouvre sur une erreur fish.
      interactiveShellInit = ''
        set -g fish_greeting
        if command -q any-nix-shell
          any-nix-shell fish --info-right | source
        end
      '';
    };

    home.packages = [ pkgs.any-nix-shell ];

    ###########################################################################
    # udiskie — automontage des clés et disques USB
    ###########################################################################
    # Le pendant utilisateur de services.udisks2 : c'est ce service qui écoute
    # les événements et demande le montage. Il doit tourner dans la session
    # graphique (le module le rattache à graphical-session.target), et non en
    # service système, parce que le montage est fait AU NOM de l'utilisateur —
    # c'est ce qui autorise polkit sans mot de passe et place le point de
    # montage dans /run/media/$USER.
    #
    # Il ne gère QUE les périphériques bloc. Le téléphone en MTP passe par
    # gvfs et apparaît directement dans la barre latérale de Nautilus, sans
    # intervention d'udiskie.
    services.udiskie = {
      enable = true;
      automount = true;
      notify = true;

      # "auto" n'affiche l'icône que lorsqu'un périphérique est présent ;
      # elle sert à démonter proprement avant de débrancher.
      tray = "auto";
    };

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

    ###########################################################################
    # piri — scratchpads
    ###########################################################################
    # Le plugin scratchpads rend une fenêtre flottante escamotable : piri la
    # déplace hors de l'écran plutôt que sur un autre workspace (aucun
    # move_to_workspace déclaré), ce qui donne le comportement « fenêtre
    # cachée » que niri seul ne sait pas faire.
    #
    # Ce fichier est un lien vers le store, donc en lecture seule : la
    # commande `piri scratchpads <nom> add`, qui enregistre la fenêtre
    # courante en écrivant dans la config, ne fonctionnera pas. Les
    # scratchpads se déclarent donc ici, ce qui est de toute façon ce qu'on
    # veut pour une config versionnée.
    xdg.configFile."niri/piri.toml".text = ''
      [piri.plugins]
      scratchpads = true

      [piri.scratchpad]
      default_size = "40% 60%"
      default_margin = 50

      # size et margin sont OBLIGATOIRES par scratchpad : les valeurs de
      # [piri.scratchpad] ne servent que de gabarit, elles ne comblent pas les
      # champs manquants. Sans elles, le démon refuse de démarrer avec
      # « missing field `size` ».
      [scratchpads.spotify]
      command = "spotify"
      app_id = "spotify"
      direction = "fromRight"
      size = "40% 60%"
      margin = 50
    '';

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
