{
  config,
  pkgs,
  lib,
  ...
}:
{
  # Some packages (ahci fail... this bypasses that) https://discourse.nixos.org/t/does-pkgs-linuxpackages-rpi3-build-all-required-kernel-modules/42509
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x: super.makeModulesClosure (x // { allowMissing = true; });
      # efivar is marked broken on 32-bit platforms (armv6l), but profiles/base.nix
      # pulls it in unconditionally via sd-image-raspberrypi.nix. Stub it out since
      # the Pi Zero W has no use for EFI tools.
      efivar = final.runCommand "efivar-stub" { } "mkdir $out";
      efibootmgr = final.runCommand "efibootmgr-stub" { } "mkdir $out";
    })
  ];

  nixpkgs.hostPlatform = "armv6l-linux";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  hardware = {
    enableRedistributableFirmware = lib.mkForce false;
    firmware = [ pkgs.raspberrypiWirelessFirmware ]; # Keep this to make sure wifi works
    i2c.enable = true;

    deviceTree = {
      enable = true;
      # Point to the currently configured (and patched!) kernel
      kernelPackage = config.boot.kernelPackages.kernel;
      filter = "*2835*";

      overlays = [
        {
          name = "enable-i2c";
          dtsFile = ./dts/i2c.dts;
        }
        {
          name = "pwm-2chan";
          dtsFile = ./dts/pwm.dts;
        }
        {
          name = "spi1-2cs";
          dtsFile = ./dts/spi.dts;
        }
      ];
    };
  };

  boot = {
    # Set the base kernel package directly
    kernelPackages = lib.mkForce pkgs.linuxPackages_rpi1;

    # Use kernelPatches to safely inject our configuration changes
    kernelPatches = [
      {
        name = "disable-rpi5-armv6-incompatible-drivers";
        patch = null;
        # Changed from extraStructuredConfig to structuredExtraConfig
        structuredExtraConfig = with lib.kernel; {
          # Disable Raspberry Pi 5 specific drivers that break ARMv6 build
          PWM_RP1 = no;
          VIDEO_RP1_CFE = no;
          DRM_RP1_VEC = no;

          # Disable Designware I2C (Not needed for Zero W)
          I2C_DESIGNWARE_CORE = no;
          I2C_DESIGNWARE_PLATFORM = no;

          # Ensure we keep the Broadcom drivers we actually need
          I2C_BCM2835 = yes;
          PWM_BCM2835 = yes;
        };
      }
    ];

    initrd.availableKernelModules = [
      "usbhid"
      "usb_storage"
    ];

    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
      efi.canTouchEfiVariables = lib.mkForce false;
    };

    # Avoids warning: mdadm: Neither MAILADDR nor PROGRAM has been set. This will cause the `mdmon` service to crash.
    # See: https://github.com/NixOS/nixpkgs/issues/254807
    swraid.enable = lib.mkForce false;
  };
}
