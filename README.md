# NixOS SD image for Raspberry Pi Zero W v1.1

A NixOS flake that provides modules for building a bootable SD image for the Raspberry Pi Zero W (BCM2835, ARMv6).

This is a **library flake** — it exposes `nixosModules` and `lib.mkDeployNode` only. You wire it into your own flake's `nixosConfigurations`.

## What this flake provides

| Output                  | Description                                                                                                                      |
| ----------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| `nixosModules.sd-image` | SD image builder — imports upstream `sd-image-raspberrypi.nix` plus the `sdImage.extraFirmwareConfig` option and sane defaults   |
| `nixosModules.hardware` | Hardware config — kernel, device tree overlays, WiFi firmware, boot loader                                                       |
| `lib.mkDeployNode`      | Helper to build a `deploy-rs` node for the Pi                                                                                    |

### Hardware module details (`hardware.nix`)

- Kernel: `linuxPackages_rpi1` with patches to disable RPi5-specific drivers that break ARMv6 builds
- Host platform: `armv6l-linux` (already set — you only need to set `nixpkgs.buildPlatform`)
- WiFi: `raspberrypiWirelessFirmware` included
- zram swap enabled (zstd) — avoids wearing out the SD card
- EFI tools stubbed out (not needed, broken on 32-bit)
- Device tree overlays:
  - **I2C1** enabled (`dts/i2c.dts`)
  - **PWM** 2-channel on GPIO 12/13 (`dts/pwm.dts`)
  - **SPI1** with 2 chip selects on GPIO 17/18 (`dts/spi.dts`)

### SD image module details (`sd-image.nix` + `sd-defaults.nix`)

- Adds `sdImage.extraFirmwareConfig` option — any attrs you set get appended to `config.txt` at image build time
- Defaults: `compressImage = false`, output filename `zerow.img`, GPU memory reduced to 16 MB, camera disabled, HDMI 800×600

## Usage

### Cross-compilation

The Pi Zero W cannot build itself (512 MB RAM). You must cross-compile from your workstation by setting `nixpkgs.buildPlatform` to your host architecture. The `hardware` module already sets `nixpkgs.hostPlatform = "armv6l-linux"`.

### Adding to your flake

**`flake.nix`:**

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
          # Cross-compile from your workstation to ARMv6
          # nixpkgs.hostPlatform is already set to "armv6l-linux" by the hardware module
          nixpkgs.buildPlatform = "x86_64-linux"; # change to "aarch64-linux" if on Apple Silicon / ARM host

          networking.hostName = "zerow";

          # WiFi — consider networking.wireless.environmentFile + sops to keep PSK out of store
          networking.wireless = {
            enable = true;
            networks."MySSID".psk = "secret";
          };

          # SSH + user with passwordless sudo (required for deploy-rs)
          services.openssh = {
            enable = true;
            settings = {
              PermitRootLogin = "no";
              PasswordAuthentication = false;
            };
          };

          users.users.admin = {
            isNormalUser = true;
            extraGroups = [ "wheel" ];
            openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAA..." ];
          };

          security.sudo.wheelNeedsPassword = false;
          nix.settings.trusted-users = [ "@wheel" ];

          system.stateVersion = "25.11";
        }
      ];
    };

    # deploy-rs node
    deploy.nodes.zerow = nixos-pi-zero-w.lib.mkDeployNode {
      nixosConfiguration = self.nixosConfigurations.zerow;
      hostname = "zerow.local"; # or an IP address
      sshUser = "admin";        # user with passwordless sudo
    };
  };
}
```

### Build the SD image

This builds a full Linux kernel and takes a while on first run. Subsequent builds are faster once packages are cached.

```sh
nix build -L .#nixosConfigurations.zerow.config.system.build.sdImage
```

### Flash to SD card

```sh
DEVICE=/dev/sdX  # your SD card device
sudo dd if=result/sd-image/zerow.img of=$DEVICE bs=1M conv=fsync status=progress
```

### Boot and deploy

1. Insert SD card, power on the Pi Zero W
2. Find its IP (or use mDNS `zerow.local` if avahi is enabled):

```sh
# on the pi via serial/console:
ip addr show wlan0
```

1. Verify SSH access:

```sh
ssh admin@zerow.local
```

1. Deploy subsequent updates from your workstation (no rebuilding on the Pi):

```sh
ZEROW_IP=<the-pi-ip>
SSH_USER=<the-admin-user-on-the-pi>
nix run github:serokell/deploy-rs .#zerow -- --ssh-user $SSH_USER --hostname $ZEROW_IP
```

## `lib.mkDeployNode` reference

```nix
nixos-pi-zero-w.lib.mkDeployNode {
  nixosConfiguration = self.nixosConfigurations.zerow; # required
  hostname = "zerow.local";                            # required
  user    = "root";                                    # optional, default: "root"
  sshUser = "admin";                                   # optional, default: same as user
}
```

## Notes

- **The Pi Zero W cannot build itself.** 512 MB RAM is not enough. Builds happen on your workstation via cross-compilation; `deploy-rs` pushes only the resulting closure to the Pi.
- **`deploy-rs` works on both NixOS and Darwin.** `nixos-rebuild --target-host` is an alternative but not available on Darwin.
- **`sdImage.extraFirmwareConfig`** appends key=value pairs to `config.txt` during image build. It cannot modify the firmware partition of a card that has already been flashed.

## See also

- [NixOS issue #216886](https://github.com/NixOS/nixpkgs/issues/216886)
- [Reference gist](https://gist.github.com/plmercereau/0c8e6ed376dc77617a7231af319e3d29)
