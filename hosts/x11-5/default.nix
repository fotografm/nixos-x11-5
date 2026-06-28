{ config, pkgs, lib, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./incus.nix
  ];

  # ----- Bootloader -----
  # UEFI systemd-boot. Keep last 10 generations on the boot menu so
  # we can roll back from the IPMI console if a rebuild breaks SSH.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.loader.systemd-boot.configurationLimit = 10;

  networking.hostName = "x11-5";

  # Match the version of NixOS this host was installed with.
  # DO NOT change this without reading the release notes.
  # https://nixos.org/manual/nixos/stable/release-notes
  system.stateVersion = "26.05";
}
