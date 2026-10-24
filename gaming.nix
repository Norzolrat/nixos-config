# Jeux — Steam et Heroic (Epic / GOG / Amazon)
#
# Module volontairement séparé de desktop.nix : il n'est importé QUE par
# nixosConfigurations.matebook, pas par l'ISO live. Steam et Heroic pèsent
# plusieurs Go à eux deux et ne testent aucun matériel, donc ils n'ont rien
# à faire dans une image dont le seul but est de valider la machine.

{ config, pkgs, ... }:

let
  # Bascule sur la RTX 4070 si l'eGPU est branché et piloté ; ne fait rien
  # sinon, et l'application reste sur l'Arc. Évalué à CHAQUE lancement de
  # Steam ou d'Heroic, dans leur conteneur, et hérité par les jeux.
  #
  # Mêmes variables que prime-run (matebook-gt.nix), pour les mêmes raisons ;
  # voir les commentaires là-bas, notamment pour VK_LOADER_DRIVERS_SELECT.
  #
  # Limites, valables pour Steam comme pour Heroic :
  # - Le choix est figé tant que l'application tourne, et toutes deux restent
  #   en arrière-plan quand on ferme leur fenêtre. Brancher le dock APRÈS les
  #   avoir lancées ne suffit pas : les quitter complètement puis les relancer.
  # - Les quitter AVANT de débrancher le dock : lancées sur la 4070, elles
  #   perdent leur GPU, et le jeu en cours avec.
  offloadIfEgpu = ''
    if [ -n "$(ls -A /proc/driver/nvidia/gpus 2>/dev/null)" ]; then
      export __NV_PRIME_RENDER_OFFLOAD=1
      export __GLX_VENDOR_LIBRARY_NAME=nvidia
      export __VK_LAYER_NV_optimus=NVIDIA_only
      export VK_LOADER_DRIVERS_SELECT='*nvidia*'
    fi
  '';

  # Lanceur du Flatpak Hytale, voir la section Hytale plus bas.
  hytale = pkgs.writeShellScriptBin "hytale" ''
    env_args=()
    if [ -n "$(ls -A /proc/driver/nvidia/gpus 2>/dev/null)" ]; then
      env_args=(
        --env=__NV_PRIME_RENDER_OFFLOAD=1
        --env=__GLX_VENDOR_LIBRARY_NAME=nvidia
        --env=__VK_LAYER_NV_optimus=NVIDIA_only
        '--env=VK_LOADER_DRIVERS_SELECT=*nvidia*'
      )
    fi
    exec flatpak run "''${env_args[@]}" \
      --branch=master --arch=x86_64 \
      --command=hytale-launcher-wrapper \
      com.hypixel.HytaleLauncher "$@"
  '';
in
{
  #############################################################################
  # Steam
  #############################################################################

  programs.steam = {
    enable = true;

    # GPU choisi automatiquement au lancement (voir offloadIfEgpu plus haut).
    # extraProfile s'exécute dans le conteneur de Steam avant son démarrage,
    # quel que soit le point d'entrée : menu, terminal ou lien steam://.
    package = pkgs.steam.override { extraProfile = offloadIfEgpu; };

    gamescopeSession.enable = true;   # utile pour cadrer sur l'écran 3:2
    remotePlay.openFirewall = true;
    localNetworkGameTransfers.openFirewall = true;

    # Le même overlay des deux côtés, pour ne pas avoir à régler MangoHud
    # deux fois selon le lanceur.
    extraPackages = with pkgs; [ mangohud ];
  };

  programs.gamemode.enable = true;

  # gamescopeSession.enable pose déjà programs.gamescope.enable en mkDefault,
  # donc le binaire gamescope arrive dans systemPackages — pas besoin de le
  # redemander ici.

  # hardware.graphics.enable32Bit est activé dans matebook-gt.nix, c'est
  # indispensable pour Proton. Ce module suppose donc matebook-gt.nix (ou un
  # autre module posant enable32Bit) à côté de lui.

  #############################################################################
  # Heroic — Epic / GOG / Amazon
  #############################################################################
  #
  # C'est un Electron enfermé dans le MÊME environnement FHS que Steam
  # (pkgs.heroic = steam.buildRuntimeEnv autour de heroic-unwrapped). Il n'a
  # pas de module NixOS, on override le paquet directement.
  #
  # Conséquence importante : un paquet posé dans environment.systemPackages
  # n'est pas forcément visible DANS le conteneur. Tout ce que Heroic doit
  # pouvoir exécuter passe par extraPkgs / extraLibraries ci-dessous.
  #
  # Ce que heroic-unwrapped embarque DÉJÀ, à ne surtout pas ajouter en double :
  # legendary (Epic), gogdl + comet (GOG), nile (Amazon), vulkan-helper, et
  # umu-launcher — le lanceur qui fait tourner Proton hors de Steam, couche
  # anti-triche EAC/BattlEye comprise.
  #
  # Les runners (Wine-GE, Proton-GE) sont téléchargés par Heroic lui-même dans
  # ~/.config/heroic/tools : ce sont des binaires FHS, donc ils fonctionnent
  # tels quels ici. C'est précisément ce qui casse hors conteneur sur NixOS,
  # et la raison pour laquelle on ne cherche pas à installer Wine côté système.

  environment.systemPackages = [
    (pkgs.heroic.override {
      # GPU choisi automatiquement au lancement (voir offloadIfEgpu plus haut).
      # Le paquet heroic, contrairement à steam, ne transmet pas extraProfile à
      # son conteneur. On remplace donc l'exécutable « heroic » de
      # heroic-unwrapped par un lanceur qui fait la détection puis exécute le
      # vrai Heroic. Le conteneur lance « heroic » par son nom (runScript), et
      # l'entrée de menu aussi (Exec=heroic %u) : tous les chemins y passent.
      heroic-unwrapped = pkgs.symlinkJoin {
        name = "heroic-unwrapped-egpu-${pkgs.heroic-unwrapped.version}";
        inherit (pkgs.heroic-unwrapped) version meta;
        paths = [ pkgs.heroic-unwrapped ];
        postBuild = ''
          rm $out/bin/heroic
          ln -s ${pkgs.writeShellScript "heroic" ''
            ${offloadIfEgpu}
            exec ${pkgs.heroic-unwrapped}/bin/heroic "$@"
          ''} $out/bin/heroic
        '';
      };

      # extraPkgs → targetPkgs : les binaires que Heroic appelle depuis les
      # réglages par jeu. Sans eux, les cases correspondantes ne font rien.
      extraPkgs = p: with p; [
        gamemode      # « Use GameMode » → appelle gamemoderun
        gamescope     # « Use Gamescope »
        mangohud      # « Show FPS » — la variante x86_64 installe aussi la
                      # couche Vulkan 32 bits, rien à ajouter pour les vieux jeux
        winetricks    # bouton « Winetricks » des réglages de préfixe
        # Dépendances d'exécution de winetricks : il les cherche dans le PATH
        # et échoue sans rien dire de clair s'il ne les trouve pas.
        cabextract
        p7zip
        unzip
        curl
      ];

      # extraLibraries → multiPkgs : construit en 64 ET 32 bits.
      # gamemoderun fait un LD_PRELOAD sur le soname nu libgamemodeauto.so.0,
      # donc il faut les deux copies visibles du loader, sinon GameMode
      # décroche sur tout jeu 32 bits.
      extraLibraries = p: with p; [ gamemode ];
    })
    hytale

    # Minecraft : Prism gère les comptes Microsoft, Java (21/17/8 fournis par
    # le paquet) et les modpacks, dont l'import des .zip de CurseForge.
    # Même lanceur que Heroic : GPU choisi au démarrage (offloadIfEgpu), à
    # quitter avant de débrancher le dock. Les instances héritent de
    # l'environnement, donc le jeu tourne aussi sur la 4070.
    (pkgs.symlinkJoin {
      name = "prismlauncher-egpu";
      paths = [ pkgs.prismlauncher ];
      postBuild = ''
        rm $out/bin/prismlauncher
        ln -s ${pkgs.writeShellScript "prismlauncher" ''
          ${offloadIfEgpu}
          exec ${pkgs.prismlauncher}/bin/prismlauncher "$@"
        ''} $out/bin/prismlauncher
      '';
    })
  ];

  #############################################################################
  # Roblox — via Sober (Flatpak), pas de paquet nixpkgs
  #############################################################################
  #
  # Roblox ne publie aucun client Linux. Sober (projet VinegarHQ) fait tourner
  # le vrai client Windows de Roblox sous Linux via une intégration Wine sur
  # mesure — pas Proton générique. Son équipe distribue UNIQUEMENT sur
  # Flathub, volontairement : Roblox pousse des mises à jour client fréquentes
  # et cassantes (l'anticheat Hyperion vérifie la version), et une build
  # nixpkgs classique prendrait toujours du retard sur le rythme de Flathub.
  # D'où nix-flatpak (cf. flake.nix) plutôt qu'un paquet dans
  # environment.systemPackages.
  #
  # Conséquence à garder en tête : Sober échappe à la reproductibilité Nix
  # habituelle. `nixos-rebuild` ne le fige pas dans flake.lock, Flathub peut
  # le mettre à jour de façon autonome entre deux rebuilds.
  services.flatpak = {
    enable = true;

    remotes = [{
      name = "flathub";
      location = "https://dl.flathub.org/repo/flathub.flatpakrepo";
    }];

    # CurseForge : pas de paquet nixpkgs, seulement le Flatpak Overwolf. Il
    # n'est pas forcé sur la 4070 (un override Flatpak est statique, donc il
    # casserait GL sans eGPU) : pour jouer sur l'eGPU, lance l'instance
    # depuis Prism, qui sait importer les modpacks CurseForge.
    packages = [ "org.vinegarhq.Sober" "com.overwolf.curseforge" ];

    # Mise à jour manuelle (flatpak update) plutôt qu'automatique : Sober sort
    # ses propres versions au rythme de Roblox, autant garder la main sur le
    # moment où ça bouge plutôt que de laisser un timer systemd le faire la
    # nuit.
    update.auto.enable = false;
  };

  # Sober est un Flatpak classique (portals xdg-desktop-portal-gnome/gtk déjà
  # posés dans desktop.nix) : pas besoin du bricolage extraProfile/FHS de
  # Steam et Heroic ci-dessus. Pour le faire basculer sur la RTX 4070 quand
  # l'eGPU est branché, il faudrait un override Flatpak déclaratif
  # (services.flatpak.overrides."org.vinegarhq.Sober".Environment.*) — pas
  # fait ici faute de retour d'expérience sur le rendu Sober côté PRIME
  # offload ; à ajouter si besoin, sur le même principe que offloadIfEgpu.

  #############################################################################
  # Hytale — launcher officiel (Flatpak), installé à la main
  #############################################################################
  #
  # Hytale n'est ni dans nixpkgs ni sur Flathub : le .flatpak se télécharge sur
  # le site officiel et s'installe en --user (`flatpak install --user`). Il
  # échappe donc à nix-flatpak, comme Sober, et se met à jour tout seul.
  #
  # Un Flatpak n'hérite pas de l'environnement de l'hôte : les variables PRIME
  # d'offloadIfEgpu doivent passer par --env. Même condition que pour Steam et
  # Heroic : sans eGPU, rien n'est forcé et le jeu reste sur l'Arc (forcer
  # nvidia sans carte casserait GL et Vulkan). Le choix est figé au lancement
  # du launcher, donc à relancer après avoir branché le dock, et à quitter
  # avant de le débrancher.
  #
  # Le Flatpak a besoin de l'extension GL NVIDIA de la MÊME version que le
  # pilote hôte (org.freedesktop.Platform.GL.nvidia-<version>). Après une mise
  # à jour du pilote : `flatpak update`, sinon le jeu retombe sur Mesa.
  # Le wrapper « hytale » est défini dans le let en haut du fichier et ajouté
  # à environment.systemPackages avec Heroic.

  # Même identifiant que l'entrée exportée par Flatpak. Elle doit aller dans
  # ~/.local/share/applications (XDG_DATA_HOME, prioritaire) et non dans le
  # profil home-manager : flatpak/exports figure avant /etc/profiles dans
  # XDG_DATA_DIRS et masquerait cette entrée. Le menu n'affiche ainsi qu'une
  # seule entrée « Hytale Launcher », celle qui passe par le wrapper.
  home-manager.users.${config.my.username}.xdg.dataFile."applications/com.hypixel.HytaleLauncher.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Hytale Launcher
    Comment=Official launcher for Hytale
    Exec=hytale
    Icon=com.hypixel.HytaleLauncher
    Terminal=false
    Categories=Game;
    Keywords=hytale;game;launcher;hypixel;
    StartupWMClass=com.hypixel.HytaleLauncher
  '';
}
