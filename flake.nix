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
    { self, nixpkgs, ... }:
    {
      nixosModules.sd-image = {
        imports = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-raspberrypi.nix"
          ./sd-image.nix
          ./sd-defaults.nix
        ];
      };

      nixosModules.hardware = ./hardware.nix;

      lib.mkDeployNode =
        {
          nixosConfiguration,
          hostname,
          user ? "root",
          sshUser ? user,
        }:
        {
          inherit hostname user sshUser;
          profiles.system.path = deploy-rs.lib.armv6l-linux.activate.nixos nixosConfiguration;
        };
    };
}
