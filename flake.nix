{
  description = "Quickshell configuration";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      forAllSystems = nixpkgs.lib.genAttrs systems;
    in {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};

          quickshellRuntime = with pkgs; [
            quickshell
            qt6.qtbase

            maple-mono.NL-NF
            bash
            coreutils
            gnugrep
            procps
            networkmanager
            findutils
            util-linux
          ];
        in {
          default = pkgs.writeShellApplication {
            name = "quickshell";
            runtimeInputs = quickshellRuntime;
          };

          qs = pkgs.writeShellApplication {
            name = "qs";
            runtimeInputs = quickshellRuntime;
          };
        }
      );
    };
}
