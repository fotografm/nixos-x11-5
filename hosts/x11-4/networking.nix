{ config, lib, pkgs, ... }:

let
  # =====================================================================
  # SET THIS BEFORE FIRST INSTALL.
  #
  # In the NixOS installer, run:   ip -o link
  # Find the physical ethernet interface (likely 'eno1' on a Supermicro
  # X11). Put the name here, commit, push, THEN run nixos-install.
  #
  # If this is wrong, the bridge will fail to come up and you will need
  # the IPMI console to fix it.
  # =====================================================================
  physicalNic = "eno1";
in {
  # No DHCP anywhere - this host has a known static address.
  networking.useDHCP = false;

  # Bridge br0 enslaves the physical NIC. The host's IP lives on the
  # bridge so Incus instances attached to br0 share the same L2 segment
  # as the host and the rest of 192.168.8.0/24.
  networking.bridges.br0.interfaces = [ physicalNic ];

  networking.interfaces.br0.ipv4.addresses = [{
    address = "192.168.8.50";
    prefixLength = 24;
  }];

  networking.defaultGateway = "192.168.8.1";
  networking.nameservers = [
    "192.168.8.70"   # Pi-hole at c38
    "1.1.1.1"        # Cloudflare fallback
    "9.9.9.9"        # Quad9 second fallback
  ];
}
