{ system ? "x86_64-linux" }:

let
  pkgs = import (builtins.fetchTarball {
    url = "https://github.com/NixOS/nixpkgs/archive/cd3cab093d1d5b523e9c7efbb970f4f016cd35a9.tar.gz";
    sha256 = "sha256-RLuUREj5j5Y0nNJYYoFiH6JNV7FzXx6fOyd9Eq3gf8k=";
  }) {
    inherit system;
  };

  fastfetch = pkgs.fastfetch.override {
    enlightenmentSupport = false;
  };

  lolcatCompat = pkgs.runCommand "lolcat-compat-${pkgs.clolcat.version}" { } ''
    mkdir -p "$out/bin"
    ln -s "${pkgs.clolcat}/bin/clolcat" "$out/bin/lolcat"
  '';
in
pkgs.symlinkJoin {
  name = "runner-prebuilt-tools";
  paths = [
    fastfetch
    pkgs.cowsay
    pkgs.pokemonsay
    pkgs.clolcat
    pkgs.figlet
    pkgs.iproute2
    pkgs.gawk
    lolcatCompat
  ];
}
