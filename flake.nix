{
  description = "NixOS — Huawei MateBook GT (niri + noctalia)";

  inputs = {
    # unstable est imposé par Noctalia (dépendance Quickshell récente),
    # et bénéficie aussi à Meteor Lake côté noyau.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secure Boot
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # niri : le flake de sodiboo, pas le module nixpkgs.
    # Il apporte les options déclaratives (config.lib.niri.actions) que la
    # doc Noctalia utilise pour les keybinds.
    niri = {
      url = "github:sodiboo/niri-flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Noctalia v4 (branche héritée Quickshell).
    # Pour la v5 native : url = "github:noctalia-dev/noctalia";
    noctalia = {
      url = "github:noctalia-dev/noctalia/legacy-v4";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Spicetify : indispensable sur NixOS, Spotify ne peut pas être patché
    # en place dans le store.
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    zen-browser = {
      url = "github:0xc000022070/zen-browser-flake";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        home-manager.follows = "home-manager";
      };
    };
  };

  # Caches binaires : sans ça tu recompiles Quickshell (gros build Qt)
  # et niri à chaque bump.
  nixConfig = {
    extra-substituters = [
      "https://noctalia.cachix.org"
      "https://niri.cachix.org"
    ];
    extra-trusted-public-keys = [
      "noctalia.cachix.org-1:pCOR47nnMEo5thcxNDtzWpOxNFQsBRglJzxWPp3dkU4="
      "niri.cachix.org-1:Wv0OmO7PsuocRKzfDoJ3mulSl7Z6oezYhGhR+3W2964="
    ];
  };

  outputs = inputs@{ self, nixpkgs, home-manager, lanzaboote, niri, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # Ce fichier décrit les UUID des partitions : il ne peut pas être versionné
      # à l'avance et n'existe donc pas sur un clone frais. Sans ce garde-fou,
      # Nix se contente d'un « Path does not exist in Git repository » qui
      # n'indique pas quoi faire.
      hardwareConfig =
        if builtins.pathExists ./hardware-configuration.nix
        then ./hardware-configuration.nix
        else throw ''
          hardware-configuration.nix est absent.

          Depuis l'ISO live, l'installation le génère toute seule :
              sudo install-matebook

          Sur une machine déjà installée :
              sudo nixos-generate-config --show-hardware-config \
                > hardware-configuration.nix
              git add hardware-configuration.nix

          (La construction de l'ISO, elle, n'en a pas besoin :
              nix build .#nixosConfigurations.iso.config.system.build.isoImage)
        '';
    in
    {
    #########################################################################
    # Shell de développement — `nix develop`
    #########################################################################
    devShells.${system}.default = pkgs.mkShell {
      name = "nixos-matebook";

      packages = with pkgs; [
        # Langage Nix
        nil                  # serveur LSP, à brancher dans VSCode
        nixpkgs-fmt          # formatage
        statix               # lint des anti-patterns
        deadnix              # code mort

        # Build et inspection
        nix-output-monitor   # `nom build` : sortie lisible
        nvd                  # diff entre deux générations
        nix-tree             # explorer une closure
        nix-diff
        cachix               # pousser tes propres builds

        # Manipulation d'ISO et de clés
        # (utiles côté WSL avant de passer sur la machine)
        jq
        git
        sbctl                # clés Secure Boot — pour l'étape lanzaboote

        # home-manager en ligne de commande, pour tester un profil isolé
        home-manager.packages.${system}.default
      ];

      shellHook = ''
        echo "── nixos-matebook ─────────────────────────────"
        echo "  build-iso    construire l'ISO live + installeur"
        echo "  check        évaluer l'ISO sans la construire"
        echo "  lint         statix + deadnix"
        echo "  fmt          formater tous les .nix"
        echo "───────────────────────────────────────────────"

        build-iso() {
          nom build .#nixosConfigurations.iso.config.system.build.isoImage "$@"
        }
        # Ciblé sur l'ISO : « nix flake check » évaluerait aussi #matebook,
        # qui exige un hardware-configuration.nix propre à la machine.
        check()  {
          nix eval --raw \
            .#nixosConfigurations.iso.config.system.build.toplevel.drvPath \
            && echo " — ISO évaluée sans erreur"
        }
        lint()   { statix check . ; deadnix .; }
        fmt()    { nixpkgs-fmt .; }
        export -f build-iso check lint fmt 2>/dev/null || true
      '';
    };

    # ISO live : ton environnement niri + noctalia, testable sans rien installer.
    #   nix build .#nixosConfigurations.iso.config.system.build.isoImage
    nixosConfigurations.iso = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        ./iso.nix
        niri.nixosModules.niri
        home-manager.nixosModules.home-manager
      ];
    };

    nixosConfigurations.matebook = nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = { inherit inputs; };
      modules = [
        hardwareConfig                 # généré par install.sh, propre au disque
        ./options.nix
        ./system.nix                   # hostname, locale, flakes, gc
        ./boot.nix                     # systemd-boot, splash, démarrage rapide
        ./matebook-gt.nix              # le module matériel
        ./desktop.nix                  # niri + noctalia
        ./apps.nix                     # spotify, discord, bureautique
        ./secureboot.nix               # lanzaboote (à activer en 2e temps)

        lanzaboote.nixosModules.lanzaboote
        niri.nixosModules.niri
        home-manager.nixosModules.home-manager
      ];
    };
  };
}
