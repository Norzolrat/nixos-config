# Options partagées entre la config du portable et l'ISO live.
{ lib, ... }:

{
  options.my.username = lib.mkOption {
    type = lib.types.str;
    default = "normi";
    description = ''
      Utilisateur principal. Vaut "nixos" dans l'ISO live, puisque c'est le
      compte imposé par le profil d'installation, et ton vrai nom sur le
      système installé.
    '';
  };
}
