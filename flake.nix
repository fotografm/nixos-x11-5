{
  description = "fotografm NixOS fleet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
  };

  outputs = { self, nixpkgs, ... }:
  let
    system = "x86_64-linux";
  in {
    nixosConfigurations = {

      # Supermicro X11 server at c38 (192.168.8.50).
      # Incus hypervisor host.
      x11-4 = nixpkgs.lib.nixosSystem {
        inherit system;
        modules = [
          ./modules/common.nix
          ./hosts/x11-4
        ];
      };

    };
  };
}
