# x11-5 — Supermicro X11 Incus hypervisor at 192.168.8.80
#
# This file is the authoritative config for x11-5. It is deployed from
# this repo, NOT from /etc/nixos/ on the machine. To rebuild:
#
#   nixos-rebuild switch --flake github:fotografm/nixos-config#x11-5
#   -- or from a local clone --
#   nixos-rebuild switch --flake /path/to/nixos-config#x11-5
#
# /etc/nixos/configuration.nix on the machine is the default install
# template and is intentionally unused. Do not edit it.

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
