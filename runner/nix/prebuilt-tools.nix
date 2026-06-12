{ system ? "x86_64-linux" }:

let
  pkgs = import (import ./nixpkgs-pin.nix) {
    inherit system;
  };
in
pkgs.symlinkJoin {
  name = "runner-prebuilt-tools";
  paths = [
    pkgs.fastfetch
    pkgs.cowsay
    pkgs.pokemonsay
    pkgs.lolcat
    pkgs.figlet
    pkgs.iproute2
    pkgs.gawk
  ];
}
