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
          # Reuse the already-evaluated package set from the nixosConfiguration,
          # extended with the deploy-rs overlay. This guarantees we use the same
          # nixpkgs revision (and overlays/config) as the system closure, so all
          # store paths align and nothing rebuilds.
          deployPkgs = nixosConfiguration.pkgs.extend deploy-rs.overlays.default;
        in
        {
          inherit hostname user sshUser;
          profiles.system.path = deployPkgs.deploy-rs.lib.activate.nixos nixosConfiguration;
        };
    };
}
