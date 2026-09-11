# The rev comes from app/flake.lock: a second copy would split the store paths
# between the devShell and the prebuilt tools.
let
  lock = builtins.fromJSON (builtins.readFile ./../app/flake.lock);
  nixpkgs = lock.nodes.nixpkgs.locked;
in
builtins.fetchTarball {
  url = "https://github.com/${nixpkgs.owner}/${nixpkgs.repo}/archive/${nixpkgs.rev}.tar.gz";
  sha256 = nixpkgs.narHash;
}
