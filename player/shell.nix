{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  strictDeps = true;

  packages = with pkgs; [
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
}
