{
  description = "Configuration NixOS de Normi (flake)";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    quickshell = {
      url = "git+https://git.outfoxxed.me/outfoxxed/quickshell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.quickshell.follows = "quickshell";
    };
  };

  outputs = { self, nixpkgs, home-manager, quickshell, noctalia, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations = {
      veronica = nixpkgs.lib.nixosSystem {
        inherit system;

        specialArgs = { inherit noctalia; };

        modules = [
          ./hosts/veronica/configuration.nix
          ./common/hardware-configuration.nix
          ./common/android.nix

          home-manager.nixosModules.home-manager

          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            
            home-manager.extraSpecialArgs = {
              inherit quickshell noctalia;
            };
            
            home-manager.users.normi.imports = [
              ./users/normi/home.nix
            ];
          }
        ];
      };
    };
  };
}

