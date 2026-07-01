{
  # Root flake — entry point for repo-managed hosts (currently x11-5).
  # x11-4 has its own standalone flake in hosts/x11-4/flake.nix (backup only).
  description = "fotografm NixOS fleet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations = {

      # Supermicro X11 server at c38 (192.168.8.80).
      # Incus hypervisor host.
      x11-5 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/common.nix
          ./hosts/x11-5
        ];
      };

    };
  };
}
