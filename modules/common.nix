{ config, pkgs, lib, ... }:

{
  # ----- Nix / flakes -----
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    auto-optimise-store = true;
  };
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # ----- Locale / time -----
  time.timeZone = "Europe/London";
  i18n.defaultLocale = "en_GB.UTF-8";
  console.keyMap = "uk";

  # ----- User -----
  # Single user 'user', SSH-key login only, passwordless sudo.
  users.mutableUsers = false;
  users.users.user = {
    isNormalUser = true;
    description = "Simon";
    extraGroups = [ "wheel" "incus-admin" ];
    shell = pkgs.bash;
    openssh.authorizedKeys.keys = [
      # =====================================================================
      # PASTE YOUR SSH PUBLIC KEY HERE BEFORE PUSHING / INSTALLING.
      # On your workstation: cat ~/.ssh/id_ed25519.pub  (or id_rsa.pub)
      # If this list is empty, you will have NO ssh access after install -
      # only IPMI console.
      # =====================================================================
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRXYcz44CkrLPcHpb92ueOuHdM1hSL3Kq0dORghTbCw fotografm@gmail.com"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  # ----- SSH daemon -----
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # ----- Firewall -----
  # nftables is REQUIRED by the Incus NixOS module (iptables fails eval).
  networking.nftables.enable = true;
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [
      22     # ssh
      8443   # incus REST API + web UI
    ];
  };

  # ----- Base toolbox -----
  environment.systemPackages = with pkgs; [
    vim
    git
    htop
    tmux
    curl
    wget
    rsync
    tree
    pciutils       # lspci
    usbutils       # lsusb
    dnsutils       # dig, host
    btrfs-progs    # btrfs CLI for inspecting the Incus pool
    file
    jq
  ];
}
