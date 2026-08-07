# Démarrage : rapide et silencieux, avec splash Plymouth.
#
# La machine n'a que NixOS — pas de dual boot, donc pas de menu à attendre.
# L'objectif est un écran de démarrage propre du firmware jusqu'à greetd,
# sans le mur de logs habituel.

{ config, lib, pkgs, ... }:

{
  #############################################################################
  # systemd-boot
  #############################################################################
  # systemd-boot, pas GRUB : il est lu directement par le firmware UEFI, sans
  # la couche de chargement de GRUB, ce qui vaut environ une seconde. C'est
  # aussi le seul des deux que lanzaboote sait signer (voir secureboot.nix),
  # donc changer pour GRUB fermerait la porte au Secure Boot.
  #
  # boot.loader.systemd-boot.enable est défini dans matebook-gt.nix.

  # 1 seconde, pas 0 : la spécialisation « egpu » est une entrée du menu, et
  # avec un délai nul il faut deviner le bon moment pour taper sur une touche.
  # Passe à 0 si tu ne démarres jamais sur l'eGPU — le menu reste alors
  # accessible en maintenant Espace pendant le POST.
  boot.loader.timeout = lib.mkDefault 1;

  # L'éditeur de ligne de commande du menu permet d'ajouter init=/bin/sh :
  # c'est un contournement complet du mot de passe pour qui a la machine.
  boot.loader.systemd-boot.editor = false;

  #############################################################################
  # Splash Plymouth
  #############################################################################

  boot.plymouth = {
    enable = true;
    # Autres thèmes du même paquet : lone, hexagon, cuts, spin, deus_ex,
    # pixels, sphere, connect. Change les deux occurrences du nom.
    theme = "rings";
    themePackages = [
      (pkgs.adi1090x-plymouth-themes.override { selected_themes = [ "rings" ]; })
    ];
  };

  # initrd systemd : Plymouth démarre alors dans l'initrd et la poignée de
  # main vers le système est continue. Sans ça, l'écran clignote au passage.
  boot.initrd.systemd.enable = true;

  #############################################################################
  # Silence
  #############################################################################
  # Plymouth ne sert à rien si les logs du noyau s'affichent par-dessus.

  boot.kernelParams = [
    # « splash » et « loglevel=0 » sont ajoutés par le module Plymouth lui-même,
    # inutile de les répéter ici.
    "quiet"
    "udev.log_level=3"
    "rd.udev.log_level=3"
    "vt.global_cursor_default=0"   # pas de curseur clignotant sous le splash
  ];

  boot.consoleLogLevel = 0;
  boot.initrd.verbose = false;

  # En cas de problème, tout reste consultable :
  #   Échap pendant le démarrage        → bascule sur les logs en direct
  #   journalctl -b                     → le journal complet après coup
  #   systemd-analyze / systemd-analyze blame / critical-chain

  #############################################################################
  # Ce qui coûte réellement des secondes
  #############################################################################

  # LE gain principal. Cette unité bloque multi-user.target jusqu'à ce que
  # NetworkManager déclare une connexion établie, soit plusieurs secondes en
  # Wi-Fi, et jusqu'au timeout complet quand aucun réseau n'est joignable.
  # Rien ici n'en dépend : greetd, niri et Noctalia gèrent l'arrivée du réseau
  # après coup. À réactiver seulement si tu ajoutes un montage réseau.
  systemd.services.NetworkManager-wait-online.enable = false;

  # Même logique côté systemd-networkd, au cas où il serait tiré par un module.
  systemd.network.wait-online.enable = false;

  # Par défaut systemd attend 90 s avant d'abandonner une unité bloquée, et
  # autant à l'extinction. Sur un portable à un seul SSD NVMe, un service qui
  # n'est pas parti au bout de 20 s ne partira pas : autant voir l'échec tout
  # de suite plutôt que de fixer un écran figé.
  systemd.settings.Manager.DefaultTimeoutStartSec = "20s";
  systemd.settings.Manager.DefaultTimeoutStopSec = "10s";

  #############################################################################
  # Non fait volontairement
  #############################################################################
  # - Pas de « nomodeset » ni de désactivation de KMS : le splash a besoin du
  #   pilote i915/xe chargé tôt, c'est justement ce qui rend la transition
  #   fluide sur l'iGPU Arc.
  # - Pas de systemd-boot en timeout 0 par défaut : voir plus haut, l'entrée
  #   egpu deviendrait pénible à atteindre.
}
