# Secure Boot via lanzaboote.
#
# ORDRE IMPÉRATIF — ne pas activer ce module dès la première installation.
#
#  1. Installer avec systemd-boot, Secure Boot DÉSACTIVÉ dans le BIOS.
#     Faire fonctionner niri, noctalia, l'eGPU. Tout valider.
#  2. Générer les clés :
#        sudo nix run nixpkgs#sbctl -- create-keys
#  3. Activer ce module (enable = true ci-dessous) et rebuild.
#        sudo nixos-rebuild switch --flake .
#     Vérifier que tout est signé :
#        sudo nix run nixpkgs#sbctl -- verify
#  4. BIOS (F2) : passer en Setup Mode / effacer la Platform Key.
#     Si le BIOS Huawei n'offre aucune de ces options, ARRÊTER ICI —
#     lanzaboote est impossible sur cette machine.
#  5. Enrôler les clés. Le flag --microsoft est OBLIGATOIRE ici : la RTX 4070
#     expose une option ROM signée Microsoft, et le firmware la refuserait
#     sans les certificats OEM. sbctl avertit d'ailleurs quand il détecte une
#     option ROM dans la chaîne de boot.
#        sudo nix run nixpkgs#sbctl -- enroll-keys --microsoft
#     Ne JAMAIS utiliser --yes-this-might-brick-my-machine.
#  6. Réactiver Secure Boot dans le BIOS, redémarrer, puis vérifier :
#        bootctl status     # attendu : Secure Boot: enabled (user)
#
# AVANT L'ÉTAPE 5 : suspendre BitLocker côté Windows. L'enrôlement modifie
# PCR7, Windows réclamera sa clé de récupération au démarrage suivant.

{ config, lib, pkgs, ... }:

{
  # lanzaboote remplace systemd-boot : il faut le désactiver explicitement.
  boot.loader.systemd-boot.enable = lib.mkForce false;

  boot.lanzaboote = {
    enable = false;   # passer à true à l'étape 3
    pkiBundle = "/var/lib/sbctl";
  };

  environment.systemPackages = [ pkgs.sbctl ];

  # NixOS n'active pas le lockdown noyau : le module NVIDIA out-of-tree
  # continuera de se charger malgré Secure Boot.
}
