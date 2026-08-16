# Jeux — Steam et Heroic (Epic / GOG / Amazon)
#
# Module volontairement séparé de desktop.nix : il n'est importé QUE par
# nixosConfigurations.matebook, pas par l'ISO live. Steam et Heroic pèsent
# plusieurs Go à eux deux et ne testent aucun matériel, donc ils n'ont rien
# à faire dans une image dont le seul but est de valider la machine.

{ pkgs, ... }:

{
  #############################################################################
  # Steam
  #############################################################################

  programs.steam = {
    enable = true;
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
