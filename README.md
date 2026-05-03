# NixOS SD image for Raspberry Pi Zero W v1.1

A NixOS library flake providing modules to build a bootable SD image for the Raspberry Pi Zero W (BCM2835, ARMv6).

Wire it into your own flake's `nixosConfigurations` to get sensible hardware defaults, cross-compilation support, and zero-rebuild deployments.

## What's Included

| Output                  | Description                                                                                                                                        |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `nixosModules.sd-image` | SD image builder with `sdImage.extraFirmwareConfig` support and sane defaults (reduced GPU mem, disabled camera, 800x600 HDMI).                    |
| `nixosModules.hardware` | Hardware config: `armv6l-linux` platform, `rpi1` kernel (patched for ARMv6), WiFi firmware, zram swap, and device tree overlays (I2C1, PWM, SPI1). |
| `lib.mkDeployNode`      | Helper to generate a `deploy-rs` node that correctly reuses your cross-compiled packages.                                                          |

## Usage

> [!NOTE]
> The Pi Zero W (512MB RAM) cannot build itself. Builds happen on your workstation via **cross-compilation**. The hardware module sets `nixpkgs.hostPlatform = "armv6l-linux"`; you only need to set `nixpkgs.buildPlatform` to match your workstation.

### 1. Add to your `flake.nix`

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixos-pi-zero-w = {
      url = "github:Mowerick/nixos-pi-zero-w";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-pi-zero-w, ... }: {

    nixosConfigurations.zerow = nixpkgs.lib.nixosSystem {
      modules = [
        nixos-pi-zero-w.nixosModules.sd-image
        nixos-pi-zero-w.nixosModules.hardware
        {
          # Cross-compile from your workstation (change to aarch64-linux if on Apple Silicon)
          nixpkgs.buildPlatform = "x86_64-linux";

          networking.hostName = "zerow"; # Output image will be 'zerow.img'

          networking.wireless = {
            enable = true;
            networks."MySSID".psk = "secret";
          };

          services.openssh = {
            enable = true;
            settings.PasswordAuthentication = false;
          };

          users.users.admin = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
          };

          security.sudo.wheelNeedsPassword = false;
          system.stateVersion = "25.11";
        }
      ];
    };

    # Set up deploy-rs
    deploy.nodes.zerow = nixos-pi-zero-w.lib.mkDeployNode {
      nixosConfiguration = self.nixosConfigurations.zerow;
      hostname = "zerow.local";
      sshUser = "admin";
    };
  };
}
```

### 2. Build & Flash the SD Image

Expect the first build to take **1–2 hours**, as it compiles the ARMv6 toolchain and packages from source (no public binary cache exists).

```sh
# Build the image
nix build -L .#nixosConfigurations.zerow.config.system.build.sdImage

# Flash to SD card (replace /dev/sdX with your actual drive)
sudo dd if=result/sd-image/zerow.img of=/dev/sdX bs=1M conv=fsync status=progress
```

### 3. Boot & Deploy

Insert the SD card, boot the Pi, and deploy future updates instantly from your workstation over SSH:

```sh
nix run github:serokell/deploy-rs .#zerow
```

---

## Why deploy-rs is fast (The `extend` trick)

Normally, `deploy-rs` evaluates its own `nixpkgs` instance to build the deployment activation script. When cross-compiling to `armv6l-linux`, this causes a derivation hash mismatch, forcing Nix to rebuild the entire toolchain a second time just for the deploy script.

`lib.mkDeployNode` solves this under the hood using this line:

```nix
deployPkgs = nixosConfiguration.pkgs.extend deploy-rs.overlays.default;
```

By explicitly injecting the `deploy-rs` overlay into the _already-evaluated_ package set from your `nixosConfiguration`, the deployment closure shares the exact same dependency tree as your OS. Result: perfect cache hits and zero redundant rebuilds.

---

## Preventing Garbage Collection of Build Artifacts

Because the first ARMv6 build takes hours, you do not want `nix-collect-garbage` to delete your cached cross-compiled packages.

To protect them, register your builds as **permanent GC roots**.

First, prepare your user's GC roots directory:

```sh
sudo mkdir -p /nix/var/nix/gcroots/per-user/$USER
sudo chown $USER /nix/var/nix/gcroots/per-user/$USER
```

Then, use the `--out-link` flag when building to pin the artifacts:

**1. Pin the full deploy-rs closure (Recommended):**
This protects the system closure _plus_ the ARMv6 `deploy-rs` dependencies.

```sh
nix build .#deploy.nodes.zerow.profiles.system.path \
  --out-link /nix/var/nix/gcroots/per-user/$USER/zerow-activatable
```

**2. Pin the SD Image:**
Useful if you need to flash fresh SD cards later without rebuilding.

```sh
nix build .#nixosConfigurations.zerow.config.system.build.sdImage \
  --out-link /nix/var/nix/gcroots/per-user/$USER/zerow-sdimage
```

**3. Pin the System toplevel:**

```sh
nix build .#nixosConfigurations.zerow.config.system.build.toplevel \
  --out-link /nix/var/nix/gcroots/per-user/$USER/zerow-system
```

**To update a pin:** Just re-run the build command. The symlink updates atomically.  
**To un-pin:** Delete the symlink (`rm /nix/var/nix/gcroots/per-user/$USER/zerow-activatable`).
