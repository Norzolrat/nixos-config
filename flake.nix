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
        echo "  build-iso    construire l'ISO d'installation"
        echo "  check        évaluer la config sans construire"
        echo "  lint         statix + deadnix"
        echo "  fmt          formater tous les .nix"
        echo "───────────────────────────────────────────────"

        build-iso() {
          nom build .#nixosConfigurations.iso.config.system.build.isoImage "$@"
        }
        check()  { nix flake check --no-build; }
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
        ./hardware-configuration.nix   # généré par nixos-generate-config
        ./options.nix
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
