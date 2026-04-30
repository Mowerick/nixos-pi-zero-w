# Building a NixOS SD image for a Raspberry Pi Zero W v1.1

## Usage

### With an existing flake setup

Add the flake into the inputs:

```nix
inputs = {
  nixos-pi-zero-w = {
    url = "github:Mowerick/nixos-pi-zero-w";
    inputs.nixpkgs.follows = "nixpkgs";
  };
};
```

Use the modules and deploy helper in your outputs:

```nix
outputs = { self, nixpkgs, nixos-pi-zero-w, deploy-rs, ... }: {
  nixosConfigurations = {
    zerow = nixpkgs.lib.nixosSystem {
      # Build on x86_64, target the Pi's armv6l
      modules = [
        nixos-pi-zero-w.nixosModules.sd-image
        nixos-pi-zero-w.nixosModules.hardware
        {
          nixpkgs.buildPlatform = "x86_64-linux";
          nixpkgs.hostPlatform  = "armv6l-linux";
          # Configure your machine here. Head to zerow.nix for opinionated defaults.
        }
      ];
    };
  };

  # deploy-rs node, built using the provided helper
  deploy.nodes.zerow = nixos-pi-zero-w.lib.mkDeployNode {
    nixosConfiguration = self.nixosConfigurations.zerow;
    hostname = "zerow.local";  # or an IP address
    sshUser  = "admin";        # user with passwordless sudo
    user     = "root";         # activation always runs as root
  };
};
```

If your flake has multiple Pi Zero W hosts, a thin wrapper keeps call sites clean:

```nix
mkPiZeroSystem = { buildSystem ? "x86_64-linux", extraModules ? [] }:
  nixpkgs.lib.nixosSystem {
    modules = [
      nixos-pi-zero-w.nixosModules.sd-image
      nixos-pi-zero-w.nixosModules.hardware
      {
        nixpkgs.buildPlatform = buildSystem;
        nixpkgs.hostPlatform  = "armv6l-linux";
      }
    ] ++ extraModules;
  };
```

### On its own

1. Update `zerow.nix`

   In particular, don't forget:

   - to configure your WiFi (consider using `networking.wireless.environmentFile` via sops to
     keep the PSK out of the Nix store)
   - to add an admin user with an SSH authorized key and passwordless sudo — required for deploy-rs:

```nix
   users.users.admin = {
     isNormalUser = true;
     extraGroups = [ "wheel" ];
     openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
   };

   security.sudo.wheelNeedsPassword = false;

   services.openssh = {
     enable = true;
     settings = {
       PermitRootLogin      = "no";
       PasswordAuthentication = false;
     };
   };

   nix.settings.trusted-users = [ "@wheel" ];
```

2. Build the image

   This builds a full Linux kernel and can take multiple hours on first run.
   Subsequent builds are faster once package artifacts are cached.

   From an `x86_64-linux` host:

```sh
   nix build -L .#nixosConfigurations.zerow.config.system.build.sdImage
```

From an `aarch64-linux` host:

```sh
   nix build -L .#nixosConfigurations.zerow.config.system.build.sdImage
```

3. Copy the image to your SD card

```sh
   DEVICE=/dev/disk5  # whatever your SD card reader is
   sudo dd if=result/sd-image/zerow.img of=$DEVICE bs=1M conv=fsync status=progress
```

4. Boot your Zero W

5. Find its IP address

```sh
   ifconfig wlan0
```

If you have avahi/mDNS enabled, `zerow.local` will resolve automatically and you
can skip this step.

6. Verify SSH access before deploying

```sh
   ssh admin@zerow.local
```

If that succeeds, deploy-rs will work.

7. Deploy from another machine

   Dry-run first to catch any activation issues without touching the running system:

```sh
   nix run github:serokell/deploy-rs -- --dry-activate .#zerow
```

Then deploy for real:

```sh
   nix run github:serokell/deploy-rs -- .#zerow
```

If mDNS isn't resolving, override the hostname on the command line:

```sh
   nix run github:serokell/deploy-rs -- .#zerow --hostname 192.168.x.y
```

## Notes

- **The Pi Zero W v1.1 cannot build itself.** It has only 512 MB of RAM. Using a swap
  partition would wear out the SD card quickly (SD cards don't tolerate many write cycles),
  and a `zram` swap isn't large enough. Hence the use of `deploy-rs` — builds happen on your
  workstation and only the resulting closure is pushed to the Pi.

- **`deploy-rs` works on both NixOS and Darwin.** `nixos-rebuild --target-host` would also
  work, but it isn't available on Darwin. `deploy-rs` is the portable choice.

- **This flake is a pure library flake.** It exposes `nixosModules` and `lib.mkDeployNode`
  only. `deploy-rs` is a consumer concern — add it to your own flake's inputs and wire up
  the `deploy.nodes` block yourself (or use `lib.mkDeployNode` as shown above).

- **Cross-compilation.** Set `nixpkgs.buildPlatform` to your host architecture and
  `nixpkgs.hostPlatform = "armv6l-linux"` in your NixOS configuration. This is handled
  automatically if you use the `mkPiZeroSystem` wrapper above.

- `boot.kernelPackages = pkgs.linuxKernel.packages.linux_rpi1` is not yet working.

- `sdImage.extraFirmwareConfig` cannot update `config.txt` after the SD image is created.

- An overlay in `hardware.deviceTree` activates the I2C bus, so `i2c-tools` works out of
  the box.

## See also

- [NixOS issue #216886](https://github.com/NixOS/nixpkgs/issues/216886)
- [Reference gist](https://gist.github.com/plmercereau/0c8e6ed376dc77617a7231af319e3d29)
