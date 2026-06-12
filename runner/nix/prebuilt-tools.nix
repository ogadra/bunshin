{ system ? "x86_64-linux" }:

let
  # This rev must match the nixpkgs source bundled for the runtime registry so
  # that prebuilt outputs are exactly what `nix run nixpkgs#...` resolves to.
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/cd3cab093d1d5b523e9c7efbb970f4f016cd35a9.tar.gz";
    sha256 = "sha256-RLuUREj5j5Y0nNJYYoFiH6JNV7FzXx6fOyd9Eq3gf8k=";
  }) {
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
