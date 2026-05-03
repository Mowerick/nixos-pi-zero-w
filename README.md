# NixOS SD image for Raspberry Pi Zero W v1.1

A NixOS flake that provides modules for building a bootable SD image for the Raspberry Pi Zero W (BCM2835, ARMv6).

This is a **library flake** — it exposes `nixosModules` and `lib.mkDeployNode` only. You wire it into your own flake's `nixosConfigurations`.

## What this flake provides

| Output                  | Description                                                                                                                    |
| ----------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| `nixosModules.sd-image` | SD image builder — imports upstream `sd-image-raspberrypi.nix` plus the `sdImage.extraFirmwareConfig` option and sane defaults |
| `nixosModules.hardware` | Hardware config — kernel, device tree overlays, WiFi firmware, boot loader                                                     |
| `lib.mkDeployNode`      | Helper to build a `deploy-rs` node for the Pi                                                                                  |

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
- Defaults: `compressImage = false`, output filename `"${config.networking.hostName}.img"`, GPU memory reduced to 16 MB, camera disabled, HDMI 800×600

## Usage

> [!NOTE]
> `zerow` is used as a **placeholder hostname** throughout the examples below — substitute it with whatever you set in `networking.hostName`. The output SD image filename is automatically derived from the hostname (`sd-defaults.nix` sets `image.fileName = "${config.networking.hostName}.img"`), so a host named `host_hostinger` produces `host_hostinger.img`, etc.

### Cross-compilation prerequisites (x86_64 hosts)

The Pi Zero W cannot build itself (512 MB RAM). Builds happen on your workstation via QEMU user-mode emulation. Two things must be configured on the **build host** for this to work.

> [!IMPORTANT] 
> `boot.binfmt.emulatedSystems` alone is not enough. ARMv6 bootstrap derivations now require the `gccarch-armv6kz` system feature to be explicitly advertised. Without it, Nix refuses to build even though emulation is active, with an error like:
>
> ```log
> error: a 'armv6l-linux' with features {gccarch-armv6kz} is required to build
> '...-bootstrap-stage0-glibc-bootstrapFiles.drv', but I am a 'x86_64-linux'
> with features {benchmark, big-parallel, kvm, nixos-test}
> ```

Add the following to your **x86_64 workstation's** NixOS configuration, then `sudo nixos-rebuild switch`:

```nix
{
  # Enable QEMU binfmt wrapper so the Nix daemon can execute ARMv6 binaries
  boot.binfmt.emulatedSystems = [ "armv6l-linux" ];

  # Advertise the ARMv6KZ gcc-arch feature that armv6 bootstrap derivations require.
  # Note: nix.settings.system-features replaces the defaults, so the four
  # standard x86_64 features must be listed here alongside the new one.
  nix.settings.system-features = [
    "gccarch-armv6kz"
  ];
}
```

> [!WARNING]
> The **first** build or deploy compiles a full ARMv6 toolchain, kernel, and userland under emulation. Expect **several hours** depending on your build host — roughly 90 minutes on a modern desktop CPU (e.g. Ryzen 7, recent Core i7), 3–6 hours on a typical laptop. The build is interruptible and resumable; subsequent builds are fast once the store is populated and pinned.

> [!NOTE]
> On Apple Silicon / AArch64 hosts, `boot.binfmt.emulatedSystems` is not needed (ARMv6 runs natively), but you still need to add `gccarch-armv6kz` to `nix.settings.system-features`.

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
          # Cross-compile from your workstation to ARMv6.
          # nixpkgs.hostPlatform is already set to "armv6l-linux" by the hardware module.
          nixpkgs.buildPlatform = "x86_64-linux"; # change to "aarch64-linux" if on Apple Silicon / ARM host

          networking.hostName = "zerow"; # ← this also determines the SD image filename (zerow.img)

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

The resulting image lands at `result/sd-image/<hostname>.img` — for the example above, `result/sd-image/zerow.img`.

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

3. Verify SSH access:

```sh
ssh admin@zerow.local
```

4. Deploy subsequent updates from your workstation (no rebuilding on the Pi):

```sh
nix run github:serokell/deploy-rs .#zerow
```

### Preventing garbage collection of build artifacts

The first ARMv6 build can take **several hours** under QEMU emulation (see the warning in the prerequisites section). By default, the `result` symlinks left behind by `nix build` are not permanent GC roots — the next `nix-collect-garbage` run will sweep all those expensive armv6l store paths away, forcing a full rebuild on the next deploy.

To keep build artifacts safe across garbage collections, register them as **permanent GC roots** under `/nix/var/nix/gcroots/per-user/$USER/` using `--out-link`.

> [!NOTE]
> The `per-user` directory may not exist yet on a fresh machine. Create it once with sudo, then chown it to your user — after that, no further sudo is needed:
>
> ```sh
> sudo mkdir -p /nix/var/nix/gcroots/per-user/$USER
> sudo chown $USER /nix/var/nix/gcroots/per-user/$USER
> ```

#### Pin the SD image

Pin both the `.img` file and all the armv6l packages that went into building it. Useful if you ever need to re-flash a fresh SD card without rebuilding from scratch:

```sh
nix build .#nixosConfigurations.zerow.config.system.build.sdImage \
  --out-link /nix/var/nix/gcroots/per-user/$USER/zerow-sdimage
```

#### Pin the deploy-rs activatable path

This is what `deploy-rs` actually pushes to the Pi. Pinning it keeps the system closure **plus** the armv6l deploy-rs binary and its transitive dependencies (Rust toolchain, gmp, openssl, …) alive across GC runs:

```sh
nix build .#deploy.nodes.zerow.profiles.system.path \
  --out-link /nix/var/nix/gcroots/per-user/$USER/zerow-activatable
```

> [!TIP]
> The `deploy-rs` activation wrapper is a separate derivation from `config.system.build.toplevel` — pinning the toplevel alone is not enough, since the wrapper drags in its own armv6l-native deploy-rs binary that takes hours to build under emulation. Always pin `deploy.nodes.<host>.profiles.system.path` for the full deploy-rs closure.

#### Updating pins after config changes

Re-run the same `nix build --out-link` command. The symlink is atomically re-pointed to the new store path, and the previously-pinned closure becomes eligible for collection on the next GC run (assuming nothing else still references it).

#### Removing a pin

Just delete the symlink — no sudo needed if you used `per-user/$USER`:

```sh
rm /nix/var/nix/gcroots/per-user/$USER/zerow-activatable
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

- [Reference gist](https://gist.github.com/plmercereau/0c8e6ed376dc77617a7231af319e3d29)
