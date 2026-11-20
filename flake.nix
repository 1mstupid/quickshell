{
  description = "quickshell config";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    wrappers.url = "github:BirdeeHub/nix-wrapper-modules/ec3ec32509e1bd97cd9886658b04702a2a7b7007";
    wrappers.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    wrappers,
    ...
  }: let
    systems = ["x86_64-linux"];
  in {
    packages = nixpkgs.lib.genAttrs systems (system: let
      pkgs = import nixpkgs {inherit system;};

      repoSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type: let
          name = baseNameOf path;
        in
          !(name == ".git" || name == ".gitignore" || name == "result" || name == ".direnv");
      };

      files = pkgs.stdenvNoCC.mkDerivation {
        pname = "quickshell-files";
        version = "1.0";
        src = repoSrc;
        dontBuild = true;
        installPhase = ''
          mkdir -p $out
          cp -r . $out/
        '';
      };
    in {
      quickshell-files = files;
      default = wrappers.wrappers.quickshell.wrap {
        inherit pkgs;
        configDir = files;
        configFile = "${files}/shell.qml";
      };
    });
  };
}
