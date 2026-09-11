{
  description = "Nix Hands-on DevShell";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/e73de5be04e0eff4190a1432b946d469c794e7b4";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forEachSystem = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in {
      devShells = forEachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [ pkgs.figlet pkgs.cowsay pkgs.lolcat ];
        };
      });
    };
}
