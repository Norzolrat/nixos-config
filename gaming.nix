# Jeux — Steam et Heroic (Epic / GOG / Amazon)
#
# Module volontairement séparé de desktop.nix : il n'est importé QUE par
# nixosConfigurations.matebook, pas par l'ISO live. Steam et Heroic pèsent
# plusieurs Go à eux deux et ne testent aucun matériel, donc ils n'ont rien
# à faire dans une image dont le seul but est de valider la machine.

{ pkgs, ... }:

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
  ];
}
