{
  description = "Flake for building a Raspberry Pi Zero W v1.1 SD image";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      deploy-rs,
      ...
    }:
    {
      nixosModules.sd-image = {
        imports = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi.nix"
          ./sd-image.nix
          ./sd-defaults.nix
        ];
      };

      nixosModules.hardware = ./hardware.nix;

      # Updated to properly handle armv6l-linux via the overlay
      lib.mkDeployNode =
        {
          nixosConfiguration,
          hostname,
          user ? "root",
          sshUser ? user,
        }:
        let
          # 1. Create a specialized package set with deploy-rs injected
          deployPkgs = import nixpkgs {
            system = nixosConfiguration.pkgs.system;
            overlays = [ deploy-rs.overlay ];
          };
        in
        {
          inherit hostname user sshUser;

          # 2. Use the dynamically generated library instead of the hardcoded armv6l-linux one
          profiles.system.path = deployPkgs.deploy-rs.lib.activate.nixos nixosConfiguration;
        };
    };
}
