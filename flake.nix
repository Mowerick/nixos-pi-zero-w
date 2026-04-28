{
  description = "Flake for building a Raspberry Pi Zero W v1.1 SD image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    flake-utils.url = "github:numtide/flake-utils";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs =
    inputs:
    with inputs;
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = nixpkgs.legacyPackages."${system}";
        crossPkgs = import "${nixpkgs}" {
          localSystem = system;
          crossSystem = "armv6l-linux";
        };
      in
      rec {
        nixosConfigurations = {
          zerow = nixpkgs.lib.nixosSystem {
            modules = [
              "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi.nix"
              ./zerow.nix
              {
                nixpkgs.pkgs = crossPkgs; # configure cross compilation. If the build system `system` is aarch64, this will provide the aarch64 nixpkgs
              }
            ];
          };
        };

        deploy = {
          user = "root";
          nodes = {
            zerow = {
              hostname = "zerow";
              profiles.system.path = deploy-rs.lib.armv6l-linux.activate.nixos self.nixosConfigurations.zerow;
            };
          };
        };
      }
    )
    // {
      nixosModules.sd-image =
        { inputs, ... }:
        {
          imports = [
            "${inputs.nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi.nix"
            ./sd-image.nix
            ./sd-defaults.nix
          ];
        };

      nixosModules.hardware = ./hardware.nix;
    };
}
