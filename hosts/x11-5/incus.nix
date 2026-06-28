{ config, lib, pkgs, ... }:

{
  virtualisation.incus = {
    enable = true;
    package = pkgs.incus;     # current feature release; switch to
                              # pkgs.incus-lts if you want the LTS line.
    ui.enable = true;

    preseed = {
      # ----- Daemon -----
      config = {
        # Listen on all interfaces. Firewall only opens 8443 on LAN.
        "core.https_address" = ":8443";
        # Refresh remote image metadata every 6 hours.
        "images.auto_update_interval" = "6";
      };

      # ----- Storage -----
      # Incus will format /dev/sda3 as btrfs and manage it as a
      # subvolume-based pool. /dev/sda3 must be an UNFORMATTED block
      # device when this preseed first runs. Do NOT mkfs.btrfs on it
      # during installation.
      storage_pools = [
        {
          name = "default";
          driver = "btrfs";
          config = {
            source = "/dev/sda3";
          };
        }
      ];

      # ----- Networks -----
      # We do NOT create an Incus-managed bridge. Instances attach to
      # the host's br0 (defined in networking.nix), so they get real
      # 192.168.8.0/24 IPs - same model as a Proxmox vmbr0.
      networks = [];

      # ----- Profiles -----
      # The default profile gives every new instance:
      #   - eth0 bridged to host br0 (LAN-attached)
      #   - root disk on the default btrfs pool
      # Static IPs are assigned per-container after creation, e.g.:
      #   incus config device set <name> eth0 ipv4.address=192.168.8.175
      profiles = [
        {
          name = "default";
          description = "LAN-bridged onto host br0";
          devices = {
            eth0 = {
              name = "eth0";
              nictype = "bridged";
              parent = "br0";
              type = "nic";
            };
            root = {
              path = "/";
              pool = "default";
              type = "disk";
            };
          };
        }
      ];
    };
  };
}
