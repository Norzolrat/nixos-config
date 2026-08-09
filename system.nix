# Réglages système de la machine installée — ce que l'ISO live fournit déjà
# de son côté (profil d'installation) et qui manque donc à la config finale :
# identité de la machine, locale, et surtout l'activation des flakes.
#
# Volontairement séparé de matebook-gt.nix, qui reste purement matériel.

{ config, lib, pkgs, ... }:

{
  networking.hostName = "matebook";

  #############################################################################
  # Nix
  #############################################################################

  nix.settings = {
    # SANS CETTE LIGNE, « nixos-rebuild switch --flake ~/nixos#matebook »
    # échoue sur le système installé : l'ISO active les flakes de son côté
    # (iso.nix), mais ce réglage ne se propage pas au système qu'elle installe.
    experimental-features = [ "nix-command" "flakes" ];

    # Les mêmes caches que le nixConfig du flake. Ici c'est le démon qui les
    # connaît, donc plus de question de confiance à chaque rebuild.
    substituters = [
      "https://cache.nixos.org"
      "https://noctalia.cachix.org"
      "https://niri.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
    trusted-users = [ "root" "@wheel" ];
  };

  # nixpkgs-unstable bouge vite : sans ménage, /nix/store enfle de plusieurs
  # Go par semaine.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.optimise.automatic = true;

  #############################################################################
  # Localisation
  #############################################################################

  time.timeZone = "Europe/Paris";

  # Interface en anglais (messages d'erreur cherchables), formats français.
  # Pour tout passer en français : i18n.defaultLocale = "fr_FR.UTF-8";
  i18n.defaultLocale = "en_US.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "fr_FR.UTF-8";
    LC_MEASUREMENT = "fr_FR.UTF-8";
    LC_MONETARY = "fr_FR.UTF-8";
    LC_NAME = "fr_FR.UTF-8";
    LC_NUMERIC = "fr_FR.UTF-8";
    LC_PAPER = "fr_FR.UTF-8";
    LC_TELEPHONE = "fr_FR.UTF-8";
    LC_TIME = "fr_FR.UTF-8";
  };

  # Console TTY alignée sur niri-config.kdl, qui déclare xkb layout "us".
  console.keyMap = "us";

  #############################################################################
  # Mémoire
  #############################################################################

  # Pas de partition de swap par défaut : zram suffit largement au quotidien
  # et évite d'écrire sur le SSD. Pour l'hibernation il faut en revanche un
  # vrai swap ≥ RAM — dans ce cas, installer avec « install-matebook --swap 32G ».
  zramSwap.enable = true;

  #############################################################################
  # Conteneurs
  #############################################################################
  # pkgs.docker embarque déjà le plugin `docker compose` (composeSupport =
  # true par défaut) : rien d'autre à installer pour la commande compose.

  virtualisation.docker.enable = true;

  #############################################################################
  # Machines virtuelles (KVM/QEMU)
  #############################################################################
  # Le CPU expose vmx et /dev/kvm existe déjà (kvm_intel chargé) : rien à
  # activer au niveau noyau, juste la couche libvirt/QEMU par-dessus.

  virtualisation.libvirtd.enable = true;
  programs.virt-manager.enable = true;
  # programs.dconf.enable est déjà à true ailleurs dans la config (dépendance
  # transitive) : virt-manager en a besoin pour retenir ses réglages GTK.

  #############################################################################
  # Comptes
  #############################################################################

  # Aucun mot de passe déclaré ici : un hash dans le dépôt, même bcrypt, finit
  # lisible par tout le monde dans /nix/store. install.sh les demande à la fin
  # de l'installation, et mutableUsers (true par défaut) rend « passwd »
  # utilisable ensuite.

  # L'utilisateur est créé par desktop.nix ; on n'ajoute ici que sudo.
  security.sudo.wheelNeedsPassword = true;

  system.stateVersion = "25.11";
}
